#!/usr/bin/env bash
# lib/corpus.sh  -  shared helper for run_local.sh and run_hadoop.sh
#
# prepare_corpus <folder-or-zip> <stage_dir>
#   Copies / unzips the corpus into <stage_dir> and removes the packaging junk that
#   zips made on a Mac contain (__MACOSX/, ._doc1.txt, .DS_Store), so that only real
#   documents are searched. The original files are never modified.

die() { echo "ERROR: $*" >&2; exit 1; }

prepare_corpus() {
  local src="$1" stage="$2"
  mkdir -p "$stage"
  if [ -d "$src" ]; then
    cp -R "$src"/. "$stage"/
  else
    case "$src" in
      *.zip|*.ZIP)
        [ -f "$src" ] || die "corpus file not found: $src"
        command -v unzip >/dev/null 2>&1 || die "'unzip' is not installed. Unzip $src yourself and pass the folder instead."
        unzip -q -o "$src" -d "$stage"
        ;;
      *) die "corpus must be a folder or a .zip file (got: $src)";;
    esac
  fi
  rm -rf "$stage/__MACOSX"
  find "$stage" -type f \( -name '._*' -o -name '.DS_Store' -o -name 'Thumbs.db' \) -delete
  [ -n "$(find "$stage" -type f | head -n 1)" ] || die "no documents found in $src"
}
