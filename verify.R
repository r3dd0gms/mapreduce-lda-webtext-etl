# ==============================================================================
# tests/verify.R  -  check the MapReduce result against an independent, naive search
#
# Run from the project folder:   Rscript tests/verify.R
#
# The "oracle" below does NOT use mapper.R / reducer.R / regular expressions with
# look-arounds: it lower-cases each line and walks along it with a plain fixed-string
# search. If the MapReduce job and the oracle agree on every document, for several
# keywords and both match modes, the row/column logic is right.
# ==============================================================================
here <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
                 error = function(e) getwd())
root <- if (file.exists(file.path(here, "..", "main.R"))) normalizePath(file.path(here, "..")) else getwd()
options(keyword_mr.no_autorun = TRUE, keyword_mr.root = root)   # load main.R's functions without running it
source(file.path(root, "main.R"))

is_word_char <- function(ch) grepl("[A-Za-z0-9_]", ch)

naive_locations <- function(file, keyword, mode) {
  raw <- readBin(file, "raw", file.size(file))
  if (length(raw) >= 3L && all(raw[1:3] == as.raw(c(0xef, 0xbb, 0xbf)))) raw <- raw[-(1:3)]   # BOM
  txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
  lines <- strsplit(txt, "\r\n|\n|\r")[[1L]]
  kw <- tolower(keyword); n <- nchar(kw)
  out <- NULL
  for (i in seq_along(lines)) {
    low <- tolower(lines[i]); pos <- 1L
    repeat {
      hit <- regexpr(kw, substring(low, pos), fixed = TRUE)[1L]
      if (hit == -1L) break
      start <- pos + hit - 1L
      ok <- TRUE
      if (mode == "word") {
        before <- if (start > 1L) substr(low, start - 1L, start - 1L) else ""
        after  <- substr(low, start + n, start + n)
        ok <- !(nzchar(before) && is_word_char(before)) && !(nzchar(after) && is_word_char(after))
      }
      if (ok) out <- rbind(out, c(i, start))
      pos <- start + 1L
    }
  }
  out
}

check_corpus <- function(label, corpus, keywords) {
  files <- list_corpus_files(corpus)
  pass <- TRUE
  for (kw in keywords) for (mode in c("word", "substring")) {
    res <- run_job(kw, mode, corpus, verbose = FALSE, save = FALSE)
    expected <- lapply(files, naive_locations, keyword = kw, mode = mode)
    names(expected) <- basename(files)
    expected <- expected[!vapply(expected, is.null, TRUE)]
    exp_str <- vapply(expected, function(m) paste0("(", m[, 1], ",", m[, 2], ")", collapse = " "), "")
    got_str <- setNames(res$summary$locations, res$summary$document)
    same <- identical(sort(names(exp_str)), sort(names(got_str))) &&
            all(exp_str[sort(names(exp_str))] == got_str[sort(names(got_str))])
    pass <- pass && same
    cat(sprintf("%s  %-22s keyword=%-14s mode=%-9s documents=%d hits=%d\n",
                if (same) "PASS" else "FAIL", label, sQuote(kw, FALSE), mode,
                length(got_str), sum(res$summary$hits)))
    if (!same) { print(exp_str); print(got_str) }
  }
  pass
}

ok <- check_corpus("real corpus (folder)", file.path(root, "data", "map_reduce_test_docs"), c("africa", "AFRICA", "south africa", "sars"))
ok <- check_corpus("real corpus (.zip)",    file.path(root, "data", "map_reduce_test_docs.zip"), "africa") && ok
ok <- check_corpus("edge-case documents",   file.path(root, "tests", "edge_case_docs"), c("africa", "south africa")) && ok
cat(if (ok) "\nALL CHECKS PASSED\n" else "\nSOME CHECKS FAILED\n")
if (!ok) quit(status = 1L)
