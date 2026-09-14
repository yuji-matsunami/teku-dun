#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/lib/dev-common.sh"

repo_root="${ROOT_DIR:-$(cd -- "$script_dir/.." && pwd -P)}"
if ! repo_root="$(cd -- "$repo_root" && pwd -P)"; then
  dev_error 'ROOT_DIR must name an existing repository directory.'
  exit 2
fi
api_base_url="${API_BASE_URL:-http://10.0.2.2:8080}"
if ! dev_parse_api_url "$api_base_url"; then
  dev_error 'API_BASE_URL must be an AppConfig-compatible HTTP(S) base URL without credentials, path, query, or fragment.'
  exit 2
fi

app_dir="$repo_root/mobile/app"
if [[ ! -f "$app_dir/.fvmrc" || ! -f "$repo_root/Taskfile.yml" ]]; then
  dev_error 'expected mobile/app/.fvmrc and Taskfile.yml in the repository.'
  exit 1
fi
if ! command -v fvm >/dev/null 2>&1; then
  dev_error 'fvm is required to build the Android APK.'
  exit 1
fi

echo '==> flutter:build-android: build a debug APK with API_BASE_URL injected.'
(cd -- "$app_dir" && fvm flutter build apk --debug "--dart-define=API_BASE_URL=$api_base_url")

apk_path="$app_dir/build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -s "$apk_path" ]]; then
  dev_error "Flutter returned successfully but the debug APK is missing or empty: $apk_path"
  exit 1
fi
printf 'Android debug APK: %s\n' "$apk_path"
