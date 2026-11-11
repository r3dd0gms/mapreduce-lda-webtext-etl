#!/usr/bin/env bash
# ==============================================================================
# run_local.sh  -  run the SAME mapper.R / reducer.R without a cluster
#
# Hadoop Streaming is, by definition,  map  |  sort  |  reduce  on text streams.
# This script performs those phases by hand so every stage can be inspected
# (useful for demonstration evidence and for debugging before using the cluster).
# On Windows, use  Rscript main.R <keyword>  instead (same result, no bash needed).
#
# Usage:   ./run_local.sh <keyword> [word|substring] [corpus folder or .zip]
# Example: ./run_local.sh africa
#          ./run_local.sh africa substring data/map_reduce_test_docs.zip
# Default corpus: data/map_reduce_test_docs
# ==============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/corpus.sh
. "$HERE/lib/corpus.sh"

KEYWORD="${1:?Usage: $0 <keyword> [word|substring] [corpus folder or .zip]}"
MATCH_MODE="${2:-word}"
CORPUS="${3:-$HERE/data/map_reduce_test_docs}"
TAB=$'\t'

command -v Rscript >/dev/null 2>&1 || die "Rscript not found. Install R first (https://cran.r-project.org)."

STAGE="$(mktemp -d)"; MAP_OUT="$(mktemp)"; SORTED_OUT="$(mktemp)"
trap 'rm -rf "$STAGE" "$MAP_OUT" "$SORTED_OUT"' EXIT
prepare_corpus "$CORPUS" "$STAGE"

echo "=== Keyword: '$KEYWORD'   match mode: $MATCH_MODE   corpus: $(basename "$CORPUS") ==="

echo; echo "--- 1. INPUT SPLITS: one split (= one map task) per document ---"
find "$STAGE" -type f | sort | while read -r f; do
  printf '  %-28s %6d lines\n' "$(basename "$f")" "$(awk 'END { print NR }' "$f")"
done

echo; echo "--- 2. MAP: <document, row:col> for every occurrence ---"
find "$STAGE" -type f | sort | while read -r f; do
  # Hadoop tells each map task which file it reads through this variable.
  mapreduce_map_input_file="$f" mapreduce_map_input_start=0 \
    Rscript "$HERE/mapper.R" "$KEYWORD" "$MATCH_MODE" < "$f" 2>/dev/null
done > "$MAP_OUT"
cat "$MAP_OUT"

echo; echo "--- 3. SHUFFLE & SORT: group by key (document name) ---"
LC_ALL=C sort -t "$TAB" -k1,1 "$MAP_OUT" > "$SORTED_OUT"
cat "$SORTED_OUT"

echo; echo "--- 4. REDUCE: one line per document  ->  document, hits, (row,col) list ---"
Rscript "$HERE/reducer.R" < "$SORTED_OUT" 2>/dev/null
[ -s "$SORTED_OUT" ] || echo "(no occurrences of '$KEYWORD' in any document)"
