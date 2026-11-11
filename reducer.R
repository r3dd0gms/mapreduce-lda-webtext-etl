#!/usr/bin/env Rscript
# ==============================================================================
# reducer.R  -  REDUCE phase of the keyword-location job   (Hadoop Streaming, R)
# ITBDA4-14  Project 2  -  Question 1.3
#
# Input  : the shuffled + sorted map output on STDIN, one pair per line
#              <document name> TAB <row:col>
#          Hadoop guarantees all lines of one document arrive together and that
#          documents arrive in key order. (It does NOT guarantee the order of the
#          values, so this reducer sorts them itself.)
# Output : ONE line per document that contains the keyword
#              <document name> TAB <number of hits> TAB (row,col) (row,col) ...
#          locations are in reading order (row, then column).
# ==============================================================================

CHUNK_LINES <- 20000L

state <- new.env()
state$key  <- NULL      # document currently being collected
state$rows <- list()    # row numbers seen for that document
state$cols <- list()    # column numbers seen for that document

emit_document <- function() {
  if (is.null(state$key)) return(invisible(NULL))
  r <- unlist(state$rows)
  c <- unlist(state$cols)
  o <- order(r, c)                                   # reading order
  r <- r[o]
  c <- c[o]
  line <- sprintf("%s\t%d\t%s", state$key, length(r),
                  paste0("(", r, ",", c, ")", collapse = " "))
  writeLines(line, stdout(), useBytes = TRUE)
  cat("reporter:counter:KeywordSearch,DOCUMENTS_WITH_MATCH,1\n", file = stderr())
  state$key  <- NULL
  state$rows <- list()
  state$cols <- list()
}

con <- file("stdin", open = "r")
repeat {
  lines <- readLines(con, n = CHUNK_LINES, warn = FALSE, skipNul = TRUE)
  if (length(lines) == 0L) break

  # split "<key>\t<row>:<col>" into its three parts
  tab   <- regexpr("\t", lines, fixed = TRUE)
  key   <- substr(lines, 1L, tab - 1L)
  val   <- substring(lines, tab + 1L)
  colon <- regexpr(":", val, fixed = TRUE)
  row   <- suppressWarnings(as.integer(substr(val, 1L, colon - 1L)))
  col   <- suppressWarnings(as.integer(substring(val, colon + 1L)))

  ok <- tab > 0L & colon > 0L & !is.na(row) & !is.na(col)
  if (any(!ok)) {
    cat(sprintf("reporter:counter:KeywordSearch,MALFORMED_RECORDS,%d\n", sum(!ok)), file = stderr())
  }
  key <- key[ok]; row <- row[ok]; col <- col[ok]
  if (length(key) == 0L) next

  # walk through runs of identical keys (input is already sorted by key)
  runs   <- rle(key)
  ends   <- cumsum(runs$lengths)
  starts <- ends - runs$lengths + 1L
  for (i in seq_along(runs$values)) {
    if (!identical(state$key, runs$values[i])) {
      emit_document()                                # previous document is complete
      state$key <- runs$values[i]
    }
    idx <- starts[i]:ends[i]
    state$rows[[length(state$rows) + 1L]] <- row[idx]
    state$cols[[length(state$cols) + 1L]] <- col[idx]
  }
}
emit_document()                                      # flush the last document
close(con)
