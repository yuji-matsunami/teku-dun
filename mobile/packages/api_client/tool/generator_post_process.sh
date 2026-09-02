#!/usr/bin/env bash

# This deterministic post-process is part of the generation pipeline. Generated
# files must not be edited by hand; change this script when the generated
# package policy needs to change.
set -euo pipefail

package_dir="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
gitignore_path="$package_dir/.gitignore"
analysis_options_path="$package_dir/analysis_options.yaml"

rewrite_file() {
  local path="$1"
  shift
  local temporary_path
  temporary_path="$(mktemp "$package_dir/.generator-post-process.XXXXXX")"
  if ! "$@" <"$path" >"$temporary_path"; then
    rm -f "$temporary_path"
    return 1
  fi
  if ! cmp -s "$path" "$temporary_path"; then
    mv "$temporary_path" "$path"
  else
    rm -f "$temporary_path"
  fi
}

append_pubspec_lock_exception() {
  # 通常の Dart ライブラリとは異なり、このアプリ専用クライアントでは
  # 開発環境と CI の依存関係を再現するため pubspec.lock を追跡する。
  awk '$0 != "!pubspec.lock" { print } END { print "!pubspec.lock" }'
}

remove_generated_test_exclude_and_ignore_unused_import() {
  awk '
    /^  exclude:[[:space:]]*$/ {
      in_exclude = 1
      next
    }
    in_exclude {
      if ($0 ~ /^    - test\/\*\.dart[[:space:]]*$/) {
        in_exclude = 0
      }
      next
    }
    /^    # OpenAPI Generator emits imports unused by small schemas\.$/ {
      next
    }
    /^    unused_import:[[:space:]]*ignore[[:space:]]*$/ {
      next
    }
    /^  errors:[[:space:]]*$/ {
      print
      print "    # OpenAPI Generator emits imports unused by small schemas."
      print "    unused_import: ignore"
      errors_seen = 1
      next
    }
    { print }
    END {
      if (!errors_seen) {
        print ""
        print "analyzer:"
        print "  errors:"
        print "    # OpenAPI Generator emits imports unused by small schemas."
        print "    unused_import: ignore"
      }
    }
  '
}

rewrite_file "$gitignore_path" append_pubspec_lock_exception
rewrite_file "$analysis_options_path" remove_generated_test_exclude_and_ignore_unused_import
