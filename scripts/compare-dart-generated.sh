#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 || ! -d "$1" || ! -d "$2" ]]; then
  echo 'usage: compare-dart-generated.sh <working-client-dir> <fresh-client-dir>' >&2
  exit 2
fi

working_dir="$(cd -- "$1" && pwd -P)"
fresh_dir="$(cd -- "$2" && pwd -P)"

working_files="$(cd -- "$working_dir" && find . \
  -type d \( -name .git -o -name .dart_tool -o -name build \) -prune -o \
  -type f -name '*.g.dart' -print | sed 's#^\./##' | LC_ALL=C sort)"
fresh_files="$(cd -- "$fresh_dir" && find . \
  -type d \( -name .git -o -name .dart_tool -o -name build \) -prune -o \
  -type f -name '*.g.dart' -print | sed 's#^\./##' | LC_ALL=C sort)"

if ! diff -u \
  <(printf '%s\n' "$working_files") \
  <(printf '%s\n' "$fresh_files"); then
  echo 'Dart generated file paths differ from a fresh build.' >&2
  exit 1
fi

while IFS= read -r relative_path; do
  [[ -n "$relative_path" ]] || continue
  if ! cmp -s "$working_dir/$relative_path" "$fresh_dir/$relative_path"; then
    echo "Dart generated file differs from a fresh build: $relative_path" >&2
    exit 1
  fi
done <<< "$working_files"

echo 'Dart generated files match a fresh build.'
