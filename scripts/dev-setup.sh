#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/lib/dev-common.sh"

profile="${PROFILE:-core}"
if ! dev_validate_profile "$profile"; then
  exit 2
fi

repo_root="${ROOT_DIR:-$(cd -- "$script_dir/.." && pwd -P)}"
if ! repo_root="$(cd -- "$repo_root" && pwd -P)"; then
  dev_error 'ROOT_DIR must name an existing repository directory.'
  exit 2
fi
app_dir="$repo_root/mobile/app"
if [[ ! -f "$repo_root/Taskfile.yml" || ! -f "$repo_root/api/go.mod" || ! -f "$app_dir/.fvmrc" ]]; then
  dev_error 'expected Taskfile.yml, api/go.mod, and mobile/app/.fvmrc in the repository.'
  exit 1
fi

for tool in task docker curl fvm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    dev_error "required command not found: $tool"
    exit 1
  fi
done
flutter_version="$(sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$app_dir/.fvmrc" | head -n 1)"
if [[ -z "$flutter_version" ]]; then
  dev_error 'could not read the pinned Flutter version from mobile/app/.fvmrc.'
  exit 1
fi
if ! docker info >/dev/null; then
  dev_error 'Docker Engine is not responding to docker info; refusing to start setup.'
  exit 1
fi
if ! dev_check_compose; then
  exit 1
fi

echo "==> dev:setup: install the pinned Flutter SDK $flutter_version."
(cd -- "$app_dir" && fvm install "$flutter_version")

if [[ "$profile" == 'android' ]]; then
  echo '==> dev:setup: inspect the Android toolchain.'
  doctor_output=''
  doctor_status=0
  doctor_output="$(cd -- "$app_dir" && fvm flutter doctor -v 2>&1)" || doctor_status=$?
  printf '%s\n' "$doctor_output"
  android_status="$(printf '%s\n' "$doctor_output" | sed -nE '/Android toolchain - develop for Android devices/p' | head -n 1)"
  case "$android_status" in
    '[✓] Android toolchain - develop for Android devices'*) ;;
    '[!] Android toolchain - develop for Android devices'*)
      android_section="$(printf '%s\n' "$doctor_output" | awk '
        /^\[[^]]+\] Android toolchain - develop for Android devices/ { capture = 1 }
        capture { print }
        capture && /^$/ { exit }
      ')"
      if dev_android_license_only_issue "$android_section"; then
        license_probe_status=0
        dev_probe_android_licenses "$app_dir" || license_probe_status=$?
        if ((license_probe_status != 0)); then
          dev_error 'Android setup stopped before dependency or DB changes.'
          exit 1
        fi
      else
        dev_error 'Flutter doctor reported an Android toolchain error unrelated to licenses; setup stopped before dependency or DB changes.'
        exit 1
      fi
      ;;
    *)
      dev_error 'Flutter doctor did not report a recognizable Android toolchain status; setup stopped before dependency or DB changes.'
      exit 1
      ;;
  esac
fi

echo '==> dev:setup: fetch Flutter dependencies.'
(cd -- "$repo_root" && FLUTTER='fvm flutter' task flutter:pub-get)
echo '==> dev:setup: fetch locked Dart API client dependencies.'
(cd -- "$repo_root" && task dart:pub-get)
echo '==> dev:setup: start the local database.'
(cd -- "$repo_root" && task db:up)
echo '==> dev:setup: apply database migrations.'
(cd -- "$repo_root" && task db:migrate)
echo '==> dev:setup: verify PostGIS.'
(cd -- "$repo_root" && task db:verify)
echo "dev:setup ($profile) passed; the database is left running."
