#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/lib/dev-common.sh"

if [[ "${CONFIRM_ANDROID_LICENSES:-}" != '1' ]]; then
  dev_error 'set CONFIRM_ANDROID_LICENSES=1 only after the user explicitly agrees to the Android SDK licenses.'
  exit 2
fi

repo_root="${ROOT_DIR:-$(cd -- "$script_dir/.." && pwd -P)}"
if ! repo_root="$(cd -- "$repo_root" && pwd -P)"; then
  dev_error 'ROOT_DIR must name an existing repository directory.'
  exit 2
fi
app_dir="$repo_root/mobile/app"
if [[ ! -f "$app_dir/.fvmrc" ]]; then
  dev_error 'expected mobile/app/.fvmrc in the repository.'
  exit 1
fi
if ! command -v fvm >/dev/null 2>&1; then
  dev_error 'fvm is required to accept Android SDK licenses.'
  exit 1
fi

echo '==> dev:accept-android-licenses: accept every Android SDK license presented by the installed SDK tools.'
set +o pipefail
yes | (cd -- "$app_dir" && fvm flutter doctor --android-licenses)
license_status="${PIPESTATUS[1]}"
set -o pipefail
exit "$license_status"
