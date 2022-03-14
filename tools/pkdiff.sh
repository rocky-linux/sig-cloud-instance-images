#!/bin/sh

base="$1"
compare="${2-$(git rev-parse --abbrev-ref HEAD)}"
file=${3:-packages.txt}

usage () {
  echo "$0: <from> [to] (defaults to current HEAD)"
  exit
}

if [[ -z $base || -z $compare ]]; then
  usage
fi

git diff "${base}:${file}" "${compare}:${file}" \
  | grep -E '^([+-]\w)' \
  | awk '!(NR%2){print substr(p,2,length(p)),"=>",substr($0,2,length($0))}{p=$0}'\
  | column -t

