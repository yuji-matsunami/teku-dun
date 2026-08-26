#!/usr/bin/env bash

set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

task_exe="${TASK_EXE:-task}"
api_dir="${API_DIR:-api}"
api_addr="${SMOKE_API_ADDR:-127.0.0.1}"
api_port="${SMOKE_API_PORT:-18080}"
timeout_seconds="${SMOKE_API_TIMEOUT:-30}"

fail_input() {
  echo "smoke: $1" >&2
  exit 1
}

case "$task_exe" in
  '') fail_input 'TASK_EXE must not be empty.' ;;
  *$'\n'*|*$'\r'*) fail_input 'TASK_EXE must not contain a newline.' ;;
esac

case "$api_dir" in
  ''|/*|*'..'*|*[![:alnum:]_./-]*) fail_input 'API_DIR must be a relative path without parent traversal.' ;;
esac
case "$api_addr" in
  ''|*[![:print:]]*|*' '*|*$'\t'*) fail_input 'SMOKE_API_ADDR must be a non-empty host or address without whitespace.' ;;
esac
case "$api_port" in
  ''|*[!0-9]*) fail_input 'SMOKE_API_PORT must be an integer between 1 and 65535.' ;;
esac
if ((10#$api_port < 1 || 10#$api_port > 65535)); then
  fail_input 'SMOKE_API_PORT must be an integer between 1 and 65535.'
fi
case "$timeout_seconds" in
  ''|*[!0-9]*) fail_input 'SMOKE_API_TIMEOUT must be a positive integer.' ;;
esac
if ((10#$timeout_seconds <= 0)); then
  fail_input 'SMOKE_API_TIMEOUT must be a positive integer.'
fi

tmp_root="${TMPDIR:-/tmp}"
if [[ ! -d "$tmp_root" ]]; then
  fail_input "temporary directory does not exist: $tmp_root"
fi
tmp_root="$(cd -- "$tmp_root" && pwd -P)"
case "$tmp_root" in
  "$repo_root"|"$repo_root"/*)
    fail_input 'refusing to create a temporary directory in the repository.'
    ;;
esac

log_dir=''
if ! log_dir="$(mktemp -d "$tmp_root/teku-dun-smoke.XXXXXX")"; then
  echo 'smoke: mktemp failed; refusing to start services.' >&2
  exit 1
fi
log_dir="$(cd -- "$log_dir" && pwd -P)"
case "$log_dir" in
  "$tmp_root"/teku-dun-smoke.*) ;;
  *)
    echo "smoke: refusing to clean unexpected temporary directory: $log_dir" >&2
    exit 1
    ;;
esac

api_pid=''
db_state='unknown'
db_start_attempted=0

run_task() {
  "$task_exe" "$@"
}

cleanup() {
  status=$?
  trap - EXIT INT TERM
  cleanup_failed=0

  if [[ -n "$api_pid" ]]; then
    if kill -0 "$api_pid" >/dev/null 2>&1; then
      kill "$api_pid" >/dev/null 2>&1 || true
    fi
    wait "$api_pid" >/dev/null 2>&1 || true
  fi

  if ((db_start_attempted == 0)); then
    echo 'smoke: DB was not started; leaving its preflight state unchanged.' >&2
  else
    case "$db_state" in
      running)
        echo 'smoke: leaving the pre-existing DB running after migrations.' >&2
        ;;
      stopped_existing)
        if ! docker compose stop db >"$log_dir/db-stop.log" 2>&1; then
          echo 'smoke: cleanup failed to restore the pre-existing stopped DB.' >&2
          cleanup_failed=1
        fi
        ;;
      nonexistent)
        # The DB container did not exist before this run. Stop and remove only
        # that container; never use `compose down`, and never remove volumes.
        if ! docker compose stop db >"$log_dir/db-stop.log" 2>&1; then
          echo 'smoke: cleanup failed to stop the temporary DB.' >&2
          cleanup_failed=1
        fi
        if ! docker compose rm -f db >"$log_dir/db-rm.log" 2>&1; then
          echo 'smoke: cleanup failed to remove the temporary DB container.' >&2
          cleanup_failed=1
        fi
        ;;
      unknown)
        echo 'smoke: DB state was not recorded; refusing cleanup changes.' >&2
        cleanup_failed=1
        ;;
    esac
  fi

  if ((status != 0)); then
    echo 'smoke: failed; captured logs follow.' >&2
    for log_file in "$log_dir"/*.log "$log_dir"/*.out "$log_dir"/*.err; do
      [[ -f "$log_file" ]] || continue
      echo "--- $log_file ---" >&2
      cat "$log_file" >&2 || true
    done
  fi

  case "$log_dir" in
    "$tmp_root"/teku-dun-smoke.*)
      if ! rm -rf -- "$log_dir"; then
        echo "smoke: failed to remove temporary directory: $log_dir" >&2
        cleanup_failed=1
      fi
      ;;
    *)
      echo "smoke: refusing to remove unexpected temporary directory: $log_dir" >&2
      cleanup_failed=1
      ;;
  esac

  if ((cleanup_failed == 1 && status == 0)); then
    status=1
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! running_services="$(docker compose ps --status running --services db 2>"$log_dir/db-state.err")"; then
  echo 'smoke: could not inspect the Compose db state; refusing to change DB state.' >&2
  exit 1
fi
if printf '%s\n' "$running_services" | grep -Fxq db; then
  db_state='running'
elif ! existing_services="$(docker compose ps -a --services db 2>>"$log_dir/db-state.err")"; then
  echo 'smoke: could not inspect whether the Compose db exists; refusing to change DB state.' >&2
  exit 1
elif printf '%s\n' "$existing_services" | grep -Fxq db; then
  db_state='stopped_existing'
else
  db_state='nonexistent'
fi

api_url="http://$api_addr:$api_port"
if curl --silent --show-error --connect-timeout 1 --max-time 2 \
  -o "$log_dir/preflight-healthz.out" -w '%{http_code}' \
  "$api_url/healthz" >"$log_dir/preflight-healthz.status" \
  2>"$log_dir/preflight-healthz.err"; then
  preflight_status="$(cat "$log_dir/preflight-healthz.status")"
  if [[ "$preflight_status" != 000 ]]; then
    echo "smoke: $api_url already has an HTTP listener; refusing to use an existing API." >&2
    exit 1
  fi
fi
if command -v lsof >/dev/null 2>&1 && \
  lsof -nP -iTCP:"$api_port" -sTCP:LISTEN >"$log_dir/preflight-port.out" \
  2>"$log_dir/preflight-port.err"; then
  echo "smoke: TCP port $api_port is already occupied; choose SMOKE_API_PORT." >&2
  exit 1
fi

echo 'smoke: starting PostGIS'
db_start_attempted=1
if ! run_task db:up >"$log_dir/db-up.log" 2>&1; then
  exit 1
fi

echo 'smoke: applying migrations'
if ! run_task db:migrate >"$log_dir/db-migrate.log" 2>&1; then
  exit 1
fi

api_binary="$log_dir/teku-dun-api"
echo 'smoke: building Go API'
if ! (cd -- "$repo_root/$api_dir" && go build -o "$api_binary" ./cmd/api) >"$log_dir/api-build.log" 2>&1; then
  exit 1
fi

echo "smoke: starting Go API on $api_url"
API_ADDR="$api_addr:$api_port" "$api_binary" >"$log_dir/api.log" 2>&1 &
api_pid=$!

deadline=$(( $(date +%s) + 10#$timeout_seconds ))
health_ok=0
while (( $(date +%s) < deadline )); do
  if ! kill -0 "$api_pid" >/dev/null 2>&1; then
    echo 'smoke: Go API exited before /healthz became available.' >&2
    exit 1
  fi
  if health_response="$(curl --silent --show-error --fail --connect-timeout 1 --max-time 2 \
    "$api_url/healthz" 2>"$log_dir/healthz.err")"; then
    if [[ "$health_response" == '{"status":"ok"}' ]]; then
      health_ok=1
      break
    fi
    printf '%s\n' "$health_response" >"$log_dir/healthz-response.out"
  fi
  sleep 1
done
if ((health_ok != 1)); then
  echo "smoke: /healthz did not return {\"status\":\"ok\"} within ${timeout_seconds}s." >&2
  exit 1
fi

if ! ready_response="$(curl --silent --show-error --fail --connect-timeout 1 --max-time 2 \
  "$api_url/readyz" 2>"$log_dir/readyz.err")"; then
  echo 'smoke: /readyz request failed.' >&2
  exit 1
fi
if [[ "$ready_response" != '{"status":"ready"}' ]]; then
  echo "smoke: unexpected /readyz response: $ready_response" >&2
  exit 1
fi

echo 'smoke: /healthz -> {"status":"ok"}'
echo 'smoke: /readyz -> {"status":"ready"}'
echo 'smoke: checks passed; restoring the preflight DB state (DB volume is retained).'
