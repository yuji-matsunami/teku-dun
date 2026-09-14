#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/lib/dev-common.sh"

target="${TARGET:-}"
device_id="${DEVICE_ID:-}"
api_base_url="${API_BASE_URL:-}"
case "$target" in
  emulator|device) ;;
  *) dev_error 'TARGET must be emulator or device.'; exit 2 ;;
esac
case "$device_id" in
  ''|*[![:alnum:]_.:@+-]*)
    dev_error 'DEVICE_ID must be a non-empty Flutter device ID without whitespace or shell punctuation.'
    exit 2
    ;;
esac
if ! dev_validate_run_url "$target" "$api_base_url"; then
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
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
for tool in task docker curl fvm go lsof; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    dev_error "required command not found: $tool"
    exit 1
  fi
done
fvm_path="$(command -v fvm)"

echo '==> dev:run: verify the selected device before starting services.'
device_output=''
if ! device_output="$(cd -- "$app_dir" && fvm flutter devices --machine 2>&1)"; then
  printf '%s\n' "$device_output" >&2
  dev_error 'Flutter could not list connected devices.'
  exit 1
fi
device_count="$(printf '%s\n' "$device_output" | tr '{' '\n' | sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | awk -v expected="$device_id" '$0 == expected { count++ } END { print count + 0 }')"
if [[ "$device_count" != '1' ]]; then
  dev_error "DEVICE_ID must match exactly one entry from flutter devices --machine (found: $device_count)."
  printf '%s\n' "$device_output" >&2
  exit 1
fi

port_output=''
port_status=0
port_output="$(lsof -nP -iTCP:8080 -sTCP:LISTEN 2>&1)" || port_status=$?
if [[ -n "$port_output" ]]; then
  dev_error 'TCP port 8080 is already occupied; refusing to start the local API.'
  printf '%s\n' "$port_output" >&2
  exit 1
elif ((port_status != 1)); then
  dev_error "could not inspect TCP port 8080 (lsof exited $port_status)."
  exit 1
fi

if ! docker info >/dev/null; then
  dev_error 'Docker Engine is not responding to docker info; refusing to start the session.'
  exit 1
fi
if ! dev_check_compose; then
  exit 1
fi

if running_services="$(docker compose ps --status running --services db 2>&1)"; then
  if printf '%s\n' "$running_services" | grep -Fxq db; then
    db_state='running'
  else
    existing_services=''
    if ! existing_services="$(docker compose ps -a --services db 2>&1)"; then
      printf '%s\n' "$existing_services" >&2
      dev_error 'could not inspect whether the Compose db container exists.'
      exit 1
    fi
    if printf '%s\n' "$existing_services" | grep -Fxq db; then
      db_state='stopped_existing'
    else
      db_state='nonexistent'
    fi
  fi
else
  printf '%s\n' "$running_services" >&2
  dev_error 'could not inspect the Compose db state; refusing to start services.'
  exit 1
fi

tmp_root="${TMPDIR:-/tmp}"
if [[ ! -d "$tmp_root" ]]; then
  dev_error "temporary directory does not exist: $tmp_root"
  exit 1
fi
tmp_root="$(cd -- "$tmp_root" && pwd -P)"
case "$tmp_root" in
  "$repo_root"|"$repo_root"/*)
    dev_error 'refusing to create a temporary API build directory in the repository.'
    exit 1
    ;;
esac

tmp_dir=''
api_pid=''
api_pgid=''
flutter_pid=''
flutter_pgid=''
db_start_attempted=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  cleanup_failed=0

  if ! dev_stop_owned_group "$flutter_pid" "$flutter_pgid" Flutter; then
    cleanup_failed=1
  fi
  if ! dev_stop_owned_group "$api_pid" "$api_pgid" API; then
    cleanup_failed=1
  fi

  if ((db_start_attempted == 1)); then
    case "$db_state" in
      running)
        echo 'dev:run cleanup: leaving the pre-existing DB running; migration data remains.' >&2
        ;;
      stopped_existing)
        echo 'dev:run cleanup: restoring the pre-existing stopped DB state.' >&2
        if ! docker compose stop db; then
          dev_error 'cleanup failed to stop the DB that was stopped before this run.'
          cleanup_failed=1
        fi
        ;;
      nonexistent)
        echo 'dev:run cleanup: removing only the temporary DB container; volumes are retained.' >&2
        if ! docker compose stop db; then
          dev_error 'cleanup failed to stop the temporary DB.'
          cleanup_failed=1
        fi
        if ! docker compose rm -f db; then
          dev_error 'cleanup failed to remove the temporary DB container.'
          cleanup_failed=1
        fi
        ;;
      *)
        dev_error 'DB state was not recorded; refusing cleanup changes.'
        cleanup_failed=1
        ;;
    esac
  fi

  if [[ -n "$tmp_dir" ]]; then
    tmp_parent="${tmp_dir%/*}"
    tmp_basename="${tmp_dir##*/}"
    if [[ "$tmp_parent" != "$tmp_root" ]]; then
      dev_error "refusing to remove unexpected temporary directory: $tmp_dir"
      cleanup_failed=1
    else
      case "$tmp_basename" in
        teku-dun-dev-session.*)
          if [[ -d "$tmp_dir" ]] && ! rm -rf -- "$tmp_dir"; then
            dev_error "failed to remove temporary directory: $tmp_dir"
            cleanup_failed=1
          fi
          ;;
        *)
          dev_error "refusing to remove unexpected temporary directory: $tmp_dir"
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
trap 'exit 130' INT
trap 'exit 143' TERM

tmp_dir="$(mktemp -d "$tmp_root/teku-dun-dev-session.XXXXXX")"
tmp_dir="$(cd -- "$tmp_dir" && pwd -P)"
case "${tmp_dir%/*}/${tmp_dir##*/}" in
  "$tmp_root"/teku-dun-dev-session.*) ;;
  *) dev_error "refusing to use unexpected temporary directory: $tmp_dir"; exit 1 ;;
esac

echo '==> dev:run: start the DB and apply migrations.'
db_start_attempted=1
(cd -- "$repo_root" && task db:up)
(cd -- "$repo_root" && task db:migrate)

echo '==> dev:run: build the Go API into a temporary directory.'
(cd -- "$api_dir" && go build -o "$tmp_dir/teku-dun-api" ./cmd/api)
echo '==> dev:run: build the owned-process launcher.'
go build -o "$tmp_dir/run-in-session" "$script_dir/run-in-session.go"

echo "==> dev:run: start the local API on port 8080 and wait up to 30 seconds."
(cd -- "$api_dir" && exec env API_ADDR=:8080 RUN_IN_SESSION_READY_FILE="$tmp_dir/api.ready" \
  "$tmp_dir/run-in-session" "$tmp_dir/teku-dun-api") >"$tmp_dir/api.log" 2>&1 &
api_pid=$!
api_pgid="$(dev_wait_for_owned_group "$api_pid" API "$tmp_dir/api.ready")"

api_ready=0
deadline=$(( $(date +%s) + 30 ))
while (( $(date +%s) < deadline )); do
  if ! kill -0 "$api_pid" >/dev/null 2>&1; then
    dev_error 'Go API exited before /healthz became available.'
    cat "$tmp_dir/api.log" >&2 || :
    exit 1
  fi
  health_status=''
  if health_status="$(curl --silent --show-error --connect-timeout 1 --max-time 2 \
    -o "$tmp_dir/healthz.out" -w '%{http_code}' http://127.0.0.1:8080/healthz 2>"$tmp_dir/healthz.err")" && \
    [[ "$health_status" == '200' ]] && [[ "$(cat "$tmp_dir/healthz.out")" == '{"status":"ok"}' ]]; then
    api_ready=1
    break
  fi
  sleep 1
done
if ((api_ready != 1)); then
  dev_error 'API /healthz did not return {"status":"ok"} within 30 seconds.'
  if [[ -f "$tmp_dir/api.log" ]]; then cat "$tmp_dir/api.log" >&2; fi
  if [[ -f "$tmp_dir/healthz.err" ]]; then cat "$tmp_dir/healthz.err" >&2; fi
  exit 1
fi

if ! ready_status="$(curl --silent --show-error --fail --connect-timeout 1 --max-time 2 \
  -o "$tmp_dir/readyz.out" -w '%{http_code}' http://127.0.0.1:8080/readyz 2>"$tmp_dir/readyz.err")" || \
  [[ "$ready_status" != '200' ]] || [[ "$(cat "$tmp_dir/readyz.out")" != '{"status":"ready"}' ]]; then
  dev_error 'API /readyz did not return {"status":"ready"}.'
  if [[ -f "$tmp_dir/api.log" ]]; then cat "$tmp_dir/api.log" >&2; fi
  if [[ -f "$tmp_dir/readyz.err" ]]; then cat "$tmp_dir/readyz.err" >&2; fi
  exit 1
fi
echo 'dev:run: /healthz and /readyz are ready.'

echo "==> dev:run: launch Flutter on device $device_id."
# Bash connects an asynchronous command's stdin to /dev/null when job control is
# disabled. Keep the caller's terminal on a dedicated descriptor so Flutter's
# q/hot-reload input remains interactive.
exec 3<&0
(
  cd -- "$app_dir"
  exec env RUN_IN_SESSION_READY_FILE="$tmp_dir/flutter.ready" \
    "$tmp_dir/run-in-session" "$fvm_path" flutter run -d "$device_id" "--dart-define=API_BASE_URL=$api_base_url"
) <&3 &
flutter_pid=$!
flutter_pgid="$(dev_wait_for_owned_group "$flutter_pid" Flutter "$tmp_dir/flutter.ready")"
if wait "$flutter_pid"; then
  flutter_status=0
else
  flutter_status=$?
fi
exit "$flutter_status"
