#!/usr/bin/env Rscript
# ==============================================================================
# mapper.R  -  MAP phase of the keyword-location job   (Hadoop Streaming, R)
# ITBDA4-14  Project 2  -  Question 1.2
#
# Task      : find every occurrence of a keyword in a document and report the
#             ROW (line number) and COLUMN (character position) of each one.
# Input     : one input split on STDIN = one whole document, one line per record.
# Output    : one <key, value> pair per occurrence, tab separated, on STDOUT
#                 key   = document (file) name
#                 value = "row:col"        e.g.   news_02_trade.txt <TAB> 2:7
# Keyword   : supplied at run time - NEVER hard-coded. Either
#                 Rscript mapper.R <keyword> [word|substring]
#             or  environment variables KEYWORD / MATCH_MODE
#             (the Hadoop driver uses  -cmdenv KEYWORD=africa).
# Matching  : case-insensitive. Default "word" = whole-word match, so
#             "Africa" / "AFRICA" / "africa," match but "African" does not.
#             "substring" also counts "African", "Africana", ...
# Row/col   : both 1-based. Row = line number in the document (blank lines
#             count). Col = position of the first letter of the match.
# ==============================================================================

CHUNK_LINES <- 5000L   # lines read per iteration (keeps memory flat on big files)

# ---- 1. Read the dynamic parameters ------------------------------------------
args       <- commandArgs(trailingOnly = TRUE)
keyword    <- if (length(args) >= 1L) args[1L] else Sys.getenv("KEYWORD", unset = "")
match_mode <- tolower(if (length(args) >= 2L) args[2L] else Sys.getenv("MATCH_MODE", unset = "word"))
keyword    <- trimws(enc2utf8(keyword))

if (!nzchar(keyword)) {
  cat("mapper.R: no keyword supplied. Use 'Rscript mapper.R <keyword>' or -cmdenv KEYWORD=<keyword>\n",
      file = stderr())
  quit(save = "no", status = 1L)
}
if (!match_mode %in% c("word", "substring")) {
  cat("mapper.R: MATCH_MODE must be 'word' or 'substring', got '", match_mode, "'\n",
      sep = "", file = stderr())
  quit(save = "no", status = 1L)
}

# ---- 2. Which document is this task reading? ---------------------------------
# Hadoop exports the job configuration to streaming tasks as environment
# variables (dots become underscores): mapreduce.map.input.file -> mapreduce_map_input_file
input_file <- Sys.getenv("mapreduce_map_input_file",
                         unset = Sys.getenv("map_input_file", unset = ""))
doc_name   <- if (nzchar(input_file)) basename(input_file) else "STDIN"

# Row numbers are only correct if this task sees the document from its first
# byte. The job config forces one split per file; this guard stops the job
# loudly rather than reporting wrong row numbers if that setting is missing.
split_start <- suppressWarnings(as.numeric(Sys.getenv("mapreduce_map_input_start", unset = "0")))
if (!is.na(split_start) && split_start > 0) {
  cat("mapper.R: this task starts mid-file (offset ", split_start, ") so row numbers would be wrong. ",
      "Set mapreduce.input.fileinputformat.split.minsize larger than the biggest file.\n",
      sep = "", file = stderr())
  quit(save = "no", status = 2L)
}

# ---- 3. Build the search pattern from the keyword -----------------------------
# Escape regex metacharacters so keywords such as "c++" or "u.s." are literal.
escape_regex <- function(x) gsub("([.\\\\|()\\[\\]{}^$*+?-])", "\\\\\\1", x, perl = TRUE)
core    <- escape_regex(keyword)
pattern <- if (match_mode == "word") {
  # not preceded / followed by a letter, digit or underscore
  paste0("(?<![\\p{L}\\p{N}_])", core, "(?![\\p{L}\\p{N}_])")
} else {
  core
}

# ---- 4. Scan the document line by line ----------------------------------------
con        <- file("stdin", open = "r")
row_offset <- 0L      # lines already processed = row number of the previous line

repeat {
  lines <- readLines(con, n = CHUNK_LINES, warn = FALSE, skipNul = TRUE)
  n     <- length(lines)
  if (n == 0L) break

  lines <- iconv(lines, from = "UTF-8", to = "UTF-8", sub = "?")      # repair bad bytes
  if (row_offset == 0L && identical(utf8ToInt(substr(lines[1L], 1L, 1L)), 65279L)) {
    lines[1L] <- substring(lines[1L], 2L)                             # drop a UTF-8 BOM (U+FEFF)
  }

  # gregexpr returns, for every line, the start position of EVERY match (or -1)
  hits   <- gregexpr(pattern, lines, ignore.case = TRUE, perl = TRUE)
  cols   <- lapply(hits, function(h) if (h[1L] == -1L) integer(0) else as.integer(h))
  counts <- lengths(cols)

  if (any(counts > 0L)) {
    rows <- rep.int(row_offset + seq_len(n), counts)               # row for each hit
    out  <- sprintf("%s\t%d:%d", doc_name, rows, unlist(cols))     # <key> TAB <row:col>
    writeLines(out, stdout(), useBytes = TRUE)
    cat(sprintf("reporter:counter:KeywordSearch,MATCHES,%d\n", length(out)), file = stderr())
  }

  cat(sprintf("reporter:counter:KeywordSearch,LINES_SCANNED,%d\n", n), file = stderr())
  row_offset <- row_offset + n
}
close(con)
