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
api_dir="$repo_root/api"
if [[ ! -f "$repo_root/Taskfile.yml" || ! -f "$api_dir/go.mod" || ! -f "$app_dir/.fvmrc" ]]; then
  dev_error 'expected Taskfile.yml, api/go.mod, and mobile/app/.fvmrc in the repository.'
  exit 1
fi

failures=0
report_failure() {
  dev_error "$1"
  failures=$((failures + 1))
}

flutter_expected="$(sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$app_dir/.fvmrc" | head -n 1)"
go_expected="$(awk '$1 == "toolchain" { toolchain = $2; sub(/^go/, "", toolchain) } $1 == "go" { go_version = $2 } END { if (toolchain != "") print toolchain; else print go_version }' "$api_dir/go.mod")"
task_minimum="${TASK_VERSION_MIN:-3.53.1}"
if [[ -z "$flutter_expected" ]]; then
  report_failure 'could not read the pinned Flutter version from mobile/app/.fvmrc.'
fi
if [[ -z "$go_expected" ]]; then
  report_failure 'could not read the required Go version from api/go.mod.'
fi

echo '==> dev:check: SDK resolution can download a missing pinned Go or Flutter toolchain.'
for tool in task docker curl fvm go; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    report_failure "required command not found: $tool"
  fi
done

if command -v task >/dev/null 2>&1; then
  task_output=''
  if task_output="$(task --version 2>&1)"; then
    printf '%s\n' "$task_output"
    task_version="$(printf '%s\n' "$task_output" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
    if [[ -z "$task_version" ]] || ! dev_version_at_least "$task_version" "$task_minimum"; then
      report_failure "Task $task_minimum or newer is required (found: ${task_version:-unknown})."
    fi
  else
    printf '%s\n' "$task_output" >&2
    report_failure 'Task version could not be checked.'
  fi
fi

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null; then
    echo 'Docker Engine is available.'
  else
    report_failure 'Docker Engine is not responding to docker info.'
  fi
  if ! dev_check_compose; then
    failures=$((failures + 1))
  fi
fi

if command -v fvm >/dev/null 2>&1 && [[ -n "$flutter_expected" ]]; then
  flutter_output=''
  if flutter_output="$(cd -- "$app_dir" && fvm flutter --version 2>&1)"; then
    printf '%s\n' "$flutter_output"
    flutter_version="$(printf '%s\n' "$flutter_output" | sed -nE 's/^Flutter ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
    if [[ "$flutter_version" != "$flutter_expected" ]]; then
      report_failure "FVM Flutter $flutter_expected is required (found: ${flutter_version:-unknown})."
    fi
  else
    printf '%s\n' "$flutter_output" >&2
    report_failure "the pinned FVM Flutter SDK $flutter_expected is unavailable."
  fi
fi

if command -v go >/dev/null 2>&1 && [[ -n "$go_expected" ]]; then
  go_output=''
  if go_output="$(cd -- "$api_dir" && go version 2>&1)"; then
    printf '%s\n' "$go_output"
    go_version="$(printf '%s\n' "$go_output" | sed -nE 's/^go version go([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
    if [[ "$go_version" != "$go_expected" ]]; then
      report_failure "Go $go_expected is required for api/ (found: ${go_version:-unknown})."
    fi
  else
    printf '%s\n' "$go_output" >&2
    report_failure "Go toolchain $go_expected is unavailable in api/."
  fi
fi

if [[ "$profile" == 'android' ]] && command -v fvm >/dev/null 2>&1; then
  echo '==> dev:check: inspect Android toolchain and connected targets.'
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
        case "$license_probe_status" in
          0) ;;
          10) failures=$((failures + 1)) ;;
          *) failures=$((failures + 1)) ;;
        esac
      else
        report_failure 'Flutter doctor reported an Android toolchain error unrelated to licenses.'
      fi
      ;;
    *) report_failure 'Flutter doctor did not report a recognizable Android toolchain status.' ;;
  esac

  device_output=''
  if device_output="$(cd -- "$app_dir" && fvm flutter devices --machine 2>&1)"; then
    printf '%s\n' "$device_output"
    has_android_device=0
    if printf '%s\n' "$device_output" | grep -Eiq '"targetPlatform"[[:space:]]*:[[:space:]]*"android-'; then
      has_android_device=1
    fi
  else
    printf '%s\n' "$device_output" >&2
    has_android_device=0
    report_failure 'Flutter could not list connected devices.'
  fi

  emulator_output=''
  if emulator_output="$(cd -- "$app_dir" && fvm flutter emulators 2>&1)"; then
    printf '%s\n' "$emulator_output"
    has_emulator=0
    if printf '%s\n' "$emulator_output" | grep -Eq '^[^[:space:]].*•[[:space:]]+android[[:space:]]*$'; then
      has_emulator=1
    fi
  else
    printf '%s\n' "$emulator_output" >&2
    has_emulator=0
    report_failure 'Flutter could not list Android emulators.'
  fi
  if ((has_android_device == 0 && has_emulator == 0)); then
    report_failure 'connect an Android device or create an Android emulator before using PROFILE=android.'
  fi
fi

if ((failures != 0)); then
  dev_error "check found $failures issue(s)."
  exit 1
fi
echo "dev:check ($profile) passed."
