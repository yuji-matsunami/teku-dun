#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="${ROOT_DIR:-$(cd -- "$script_dir/.." && pwd -P)}"
repo_root="$(cd -- "$repo_root" && pwd -P)"
client_relative="${DART_CLIENT_DIR:-mobile/packages/api_client}"
sdk_image="${DART_CLIENT_SDK_IMAGE:-dart:3.7.0@sha256:9fb41fc1eefdf432694e17b0f80c9135b1f79dd3f645c403f98ed5ae71799c36}"

case "$client_relative" in
  ''|/*|*'..'*|*[![:alnum:]_./-]*)
    echo 'dart build-check: DART_CLIENT_DIR must be a normalized relative path.' >&2
    exit 2
    ;;
esac
client_dir="$repo_root/$client_relative"
if [[ ! -d "$client_dir" || ! -f "$client_dir/pubspec.yaml" || ! -f "$client_dir/pubspec.lock" ]]; then
  echo "dart build-check: Dart client input is incomplete: $client_dir" >&2
  exit 1
fi
if [[ -z "$sdk_image" ]]; then
  echo 'dart build-check: DART_CLIENT_SDK_IMAGE must not be empty.' >&2
  exit 2
fi
if ! command -v docker >/dev/null 2>&1; then
  echo 'dart build-check: docker is required.' >&2
  exit 1
fi

tmp_root="${TMPDIR:-/tmp}"
if [[ ! -d "$tmp_root" ]]; then
  echo "dart build-check: temporary directory does not exist: $tmp_root" >&2
  exit 1
fi
tmp_root="$(cd -- "$tmp_root" && pwd -P)"
case "$tmp_root" in
  "$repo_root"|"$repo_root"/*)
    echo 'dart build-check: refusing to create a temporary directory in the repository.' >&2
    exit 1
    ;;
esac

tmp_dir=''
cleanup() {
  status=$?
  trap - EXIT
  cleanup_failed=0
  if [[ -n "$tmp_dir" ]]; then
    tmp_parent="${tmp_dir%/*}"
    tmp_basename="${tmp_dir##*/}"
    if [[ "$tmp_parent" != "$tmp_root" ]]; then
      echo "dart build-check: refusing to remove unexpected temporary directory: $tmp_dir" >&2
      cleanup_failed=1
    else
      case "$tmp_basename" in
        teku-dun-dart-build-check.*)
          if [[ -d "$tmp_dir" ]] && ! rm -rf -- "$tmp_dir"; then
            echo "dart build-check: failed to remove temporary directory: $tmp_dir" >&2
            cleanup_failed=1
          fi
          ;;
        *)
          echo "dart build-check: refusing to remove unexpected temporary directory: $tmp_dir" >&2
          cleanup_failed=1
          ;;
      esac
    fi
  fi
  if ((cleanup_failed != 0 && status == 0)); then
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT

tmp_dir="$(mktemp -d "$tmp_root/teku-dun-dart-build-check.XXXXXX")"
tmp_dir="$(cd -- "$tmp_dir" && pwd -P)"
case "$tmp_dir" in
  "$repo_root"|"$repo_root"/*)
    echo 'dart build-check: refusing to generate inside the repository.' >&2
    exit 1
    ;;
esac
case "${tmp_dir%/*}/${tmp_dir##*/}" in
  "$tmp_root"/teku-dun-dart-build-check.*) ;;
  *)
    echo "dart build-check: refusing to use unexpected temporary directory: $tmp_dir" >&2
    exit 1
    ;;
esac

fresh_client="$tmp_dir/client"
mkdir -p "$fresh_client"
while IFS= read -r input_file; do
  relative_path="${input_file#"$client_dir"/}"
  destination="$fresh_client/$relative_path"
  mkdir -p "$(dirname "$destination")"
  cp -p "$input_file" "$destination"
done < <(find "$client_dir" \
  -type d \( -name .git -o -name .dart_tool -o -name build \) -prune -o \
  -type f ! -name '*.g.dart' -print)

echo '==> Dart build-check: fetch locked dependencies in a fresh copy'
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$fresh_client:/workspace" \
  -w /workspace \
  -e PUB_CACHE=/workspace/.dart_tool/pub-cache \
  -e HOME=/workspace/.dart_tool/home \
  "$sdk_image" dart pub get --enforce-lockfile

echo '==> Dart build-check: generate built_value files in isolation'
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$fresh_client:/workspace" \
  -w /workspace \
  -e PUB_CACHE=/workspace/.dart_tool/pub-cache \
  -e HOME=/workspace/.dart_tool/home \
  "$sdk_image" dart run build_runner build

echo '==> Dart build-check: compare generated files'
"$script_dir/compare-dart-generated.sh" "$client_dir" "$fresh_client"
