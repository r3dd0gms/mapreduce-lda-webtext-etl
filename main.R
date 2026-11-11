project_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- sub("^--file=", "", ca[grep("^--file=", ca)])
  of <- tryCatch(sys.frame(1L)$ofile, error = function(e) NULL)
  candidates <- c(getOption("keyword_mr.root"),
                  if (length(f)) dirname(normalizePath(f[1L])),
                  if (!is.null(of)) dirname(normalizePath(of)),
                  getwd())
  for (d in candidates) if (file.exists(file.path(d, "mapper.R"))) return(normalizePath(d))
  stop("Cannot find the project folder. setwd() to the folder that contains mapper.R and try again.",
       call. = FALSE)
}

rscript_bin <- function() {
  file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
}

list_corpus_files <- function(corpus) {
  if (!file.exists(corpus)) stop("Corpus not found: ", corpus, call. = FALSE)
  corpus <- normalizePath(corpus)
  if (dir.exists(corpus)) {
    root <- corpus
  } else if (grepl("\\.zip$", corpus, ignore.case = TRUE)) {
    root <- tempfile("corpus_")
    dir.create(root)
    utils::unzip(corpus, exdir = root)
  } else {
    stop("Corpus must be a folder or a .zip file: ", corpus, call. = FALSE)
  }
  rel  <- list.files(root, recursive = TRUE, all.files = TRUE)
  junk <- grepl("(^|/)__MACOSX(/|$)", rel) |
          grepl("(^|/)(\\._[^/]*|\\.DS_Store|Thumbs\\.db)$", rel)
  rel  <- sort(rel[!junk])
  if (!length(rel)) stop("No documents found in ", corpus, call. = FALSE)
  file.path(root, rel)
}

# ---- run one of the streaming scripts and capture its output -----------------
run_script <- function(script, args = character(), stdin_file = NULL, input = NULL) {
  err <- tempfile(fileext = ".err")
  on.exit(unlink(err), add = TRUE)
  out <- suppressWarnings(system2(rscript_bin(), c(shQuote(script), shQuote(args)),
                                  stdout = TRUE, stderr = err,
                                  stdin = if (is.null(stdin_file)) "" else stdin_file,
                                  input = input))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    msg <- paste(readLines(err, warn = FALSE), collapse = "\n")
    stop(basename(script), " failed (exit code ", status, "):\n", msg, call. = FALSE)
  }
  as.character(out)
}

show_lines <- function(x, max_lines = 40L) {
  if (length(x) <= max_lines) { cat(x, sep = "\n"); return(invisible()) }
  cat(head(x, max_lines), sep = "\n")
  cat(sprintf("... (%d more lines)\n", length(x) - max_lines))
}

# ---- the whole job -------------------------------------------------------------
run_job <- function(keyword, match_mode = "word", corpus = NULL, verbose = TRUE, save = TRUE) {
  root <- project_root()
  if (is.null(corpus)) corpus <- file.path(root, "data", "map_reduce_test_docs")
  keyword    <- trimws(keyword)
  match_mode <- tolower(match_mode)
  if (!nzchar(keyword)) stop("Please supply a keyword.", call. = FALSE)
  if (!match_mode %in% c("word", "substring")) stop("match_mode must be 'word' or 'substring'.", call. = FALSE)
  say <- function(...) if (verbose) cat(...)

  files <- list_corpus_files(corpus)
  say(sprintf("=== Keyword: '%s'   match mode: %s   corpus: %s (%d documents) ===\n",
              keyword, match_mode, basename(corpus), length(files)))

  # 1. INPUT SPLITS - one split (= one map task) per document
  say("\n--- 1. INPUT SPLITS: one split (= one map task) per document ---\n")
  if (verbose) for (f in files) {
    say(sprintf("  %-28s %6d lines\n", basename(f), length(readLines(f, warn = FALSE))))
  }

  # 2. MAP - the same mapper.R that Hadoop runs, once per split
  say("\n--- 2. MAP: <document, row:col> for every occurrence ---\n")
  old <- Sys.getenv(c("mapreduce_map_input_file", "mapreduce_map_input_start"), unset = NA)
  on.exit({
    for (n in names(old)) if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(old[[n]]), n))
  }, add = TRUE)
  mapped <- character()
  for (f in files) {
    Sys.setenv(mapreduce_map_input_file = f, mapreduce_map_input_start = "0")   # what Hadoop provides
    mapped <- c(mapped, run_script(file.path(root, "mapper.R"), c(keyword, match_mode), stdin_file = f))
  }
  if (verbose) show_lines(mapped)

  # 3. SHUFFLE & SORT - group by key (document name); values keep their text order
  say("\n--- 3. SHUFFLE & SORT: group by key (document name) ---\n")
  # Same order as `LC_ALL=C sort`: by key, ties by value text (so "40:146" comes before
  # "5:7"). Hadoop promises no particular value order, which is why reducer.R sorts
  # each document's locations numerically itself.
  sorted <- mapped[order(mapped, method = "radix")]
  if (verbose) show_lines(sorted)

  # 4. REDUCE - the same reducer.R that Hadoop runs
  say("\n--- 4. REDUCE: one line per document  ->  document, hits, (row,col) list ---\n")
  reduced <- if (length(sorted)) run_script(file.path(root, "reducer.R"), input = sorted) else character()
  if (verbose) {
    if (length(reduced)) cat(reduced, sep = "\n") else say(sprintf("(no occurrences of '%s' in any document)\n", keyword))
  }

  # 5. OUTPUT - a table, and the files a Hadoop job would leave in HDFS
  parts <- strsplit(reduced, "\t", fixed = TRUE)
  summary_tbl <- data.frame(document  = vapply(parts, `[`, "", 1L),
                            hits      = as.integer(vapply(parts, `[`, "", 2L)),
                            locations = vapply(parts, `[`, "", 3L),
                            stringsAsFactors = FALSE)
  pairs <- regmatches(summary_tbl$locations, gregexpr("\\([0-9]+,[0-9]+\\)", summary_tbl$locations))
  long_tbl <- data.frame(
    document = rep(summary_tbl$document, lengths(pairs)),
    row = as.integer(sub("\\(([0-9]+),.*", "\\1", unlist(pairs))),
    col = as.integer(sub(".*,([0-9]+)\\)", "\\1", unlist(pairs))),
    stringsAsFactors = FALSE)

  if (save) {
    out_dir <- file.path(root, "output")
    dir.create(out_dir, showWarnings = FALSE)
    tag <- gsub("[^A-Za-z0-9_-]+", "_", keyword)
    writeLines(reduced, file.path(out_dir, sprintf("part-00000_%s_%s.txt", tag, match_mode)))
    utils::write.csv(long_tbl, file.path(out_dir, sprintf("locations_%s_%s.csv", tag, match_mode)), row.names = FALSE)
    say(sprintf("\nSaved: output/part-00000_%s_%s.txt  and  output/locations_%s_%s.csv\n", tag, match_mode, tag, match_mode))
  }
  invisible(list(summary = summary_tbl, locations = long_tbl, map_output = mapped, reduce_output = reduced))
}

# ---- command line / RStudio entry point ---------------------------------------
main <- function() {
  args    <- commandArgs(trailingOnly = TRUE)
  keyword <- if (length(args) >= 1L) args[1L] else if (interactive()) readline("Keyword to search for: ") else ""
  if (!nzchar(trimws(keyword))) {
    stop("Usage: Rscript main.R <keyword> [word|substring] [corpus folder or .zip]", call. = FALSE)
  }
  run_job(keyword,
          match_mode = if (length(args) >= 2L) args[2L] else "word",
          corpus     = if (length(args) >= 3L) args[3L] else NULL)
  invisible()
}

# Tests switch this off with  options(keyword_mr.no_autorun = TRUE)  before source().
if (!isTRUE(getOption("keyword_mr.no_autorun"))) main()
