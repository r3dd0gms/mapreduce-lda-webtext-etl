#!/usr/bin/env bash
# ==============================================================================
# run_hadoop.sh  -  DRIVER: submit the keyword-location job to a Hadoop cluster
# ITBDA4-14  Project 2  -  Question 1.4
#
# Usage:   ./run_hadoop.sh <keyword> [word|substring] [corpus folder or .zip]
# Example: ./run_hadoop.sh africa
#          ./run_hadoop.sh "south africa" word data/map_reduce_test_docs.zip
# Default corpus: data/map_reduce_test_docs
#
# Requirements: hadoop + hdfs on the PATH, and R (Rscript) installed on THIS
# machine AND on every worker node, because mapper.R / reducer.R are R scripts.
# (On a single-node VM that is just the one machine.)
# ==============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/corpus.sh
. "$HERE/lib/corpus.sh"

KEYWORD="${1:?Usage: $0 <keyword> [word|substring] [corpus folder or .zip]}"
MATCH_MODE="${2:-word}"
CORPUS="${3:-$HERE/data/map_reduce_test_docs}"

HDFS_BASE="${HDFS_BASE:-/user/$(whoami)/keyword_search}"
HDFS_INPUT="$HDFS_BASE/input"
HDFS_OUTPUT="$HDFS_BASE/output"

# ---- 1. Pre-flight checks (the usual reasons a streaming job fails) -------------
command -v hadoop >/dev/null 2>&1 || die "'hadoop' not found on PATH. Start your Hadoop environment first."
command -v hdfs   >/dev/null 2>&1 || die "'hdfs' not found on PATH."
command -v Rscript >/dev/null 2>&1 || die "Rscript not found. Install R on this machine and on every worker node
       (e.g. 'sudo apt-get install r-base' or 'sudo yum install R'). Without it every task fails with exit code 127."

# Locate the Hadoop Streaming jar (override with HADOOP_STREAMING_JAR=/path/to.jar)
STREAMING_JAR="${HADOOP_STREAMING_JAR:-}"
if [ -z "$STREAMING_JAR" ]; then
  HADOOP_HOME="${HADOOP_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v hadoop)")")")}"
  for pattern in "$HADOOP_HOME"/share/hadoop/tools/lib/hadoop-streaming-*.jar \
                 /usr/lib/hadoop-mapreduce/hadoop-streaming*.jar \
                 /opt/cloudera/parcels/CDH/lib/hadoop-mapreduce/hadoop-streaming*.jar \
                 "$HADOOP_HOME"/hadoop-streaming*.jar; do
    for jar in $pattern; do [ -f "$jar" ] && { STREAMING_JAR="$jar"; break 2; }; done
  done
fi
[ -n "$STREAMING_JAR" ] || die "hadoop-streaming jar not found. Find it with:  find / -name 'hadoop-streaming*.jar' 2>/dev/null
       then run:  HADOOP_STREAMING_JAR=/that/path.jar $0 $KEYWORD"

# Quick self-test of the R scripts on this machine before involving the cluster
SELFTEST="$(printf 'x %s y\n' "$KEYWORD" | Rscript "$HERE/mapper.R" "$KEYWORD" substring 2>/dev/null || true)"
[ -n "$SELFTEST" ] || die "mapper.R did not run correctly on this machine. Try:  echo 'x africa y' | Rscript mapper.R africa"

echo ">> Keyword: '$KEYWORD'   match mode: $MATCH_MODE   corpus: $(basename "$CORPUS")"
echo ">> Streaming jar: $STREAMING_JAR"

# ---- 2. Clean copy of the corpus, then upload to a FRESH HDFS input folder -----
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
prepare_corpus "$CORPUS" "$STAGE"
echo ">> Uploading $(find "$STAGE" -type f | wc -l) documents to HDFS $HDFS_INPUT"
hdfs dfs -rm -r -f "$HDFS_INPUT"  >/dev/null 2>&1 || true     # no stale files from earlier runs
hdfs dfs -rm -r -f "$HDFS_OUTPUT" >/dev/null 2>&1 || true     # output folder must not exist
hdfs dfs -mkdir -p "$HDFS_INPUT"
hdfs dfs -put "$STAGE"/* "$HDFS_INPUT"/

# ---- 3. Submit the job ------------------------------------------------------------
echo ">> Submitting job"
# Generic options (-conf, -D, -files) must come BEFORE the streaming options.
hadoop jar "$STREAMING_JAR" \
  -conf  "$HERE/config/keyword-search-conf.xml" \
  -D     mapreduce.job.name="keyword-locator [$KEYWORD]" \
  -files "$HERE/mapper.R,$HERE/reducer.R" \
  -input  "$HDFS_INPUT" \
  -output "$HDFS_OUTPUT" \
  -mapper  "Rscript mapper.R" \
  -reducer "Rscript reducer.R" \
  -cmdenv "KEYWORD=$KEYWORD" \
  -cmdenv "MATCH_MODE=$MATCH_MODE"

echo ">> Result  (document <TAB> hits <TAB> (row,col) ...):"
hdfs dfs -cat "$HDFS_OUTPUT"/part-*
