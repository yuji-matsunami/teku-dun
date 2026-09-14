#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
source "$repo_root/scripts/lib/dev-common.sh"
tmp_root="${TMPDIR:-/tmp}"
test_dir="$(mktemp -d "$tmp_root/teku-dun-dev-tools-test.XXXXXX")"
export GOCACHE="${GOCACHE:-$test_dir/go-build-cache}"

cleanup() {
  case "$test_dir" in
    "$tmp_root"/teku-dun-dev-tools-test.*) rm -rf -- "$test_dir" ;;
    *) printf 'refusing to remove unexpected test directory: %s\n' "$test_dir" >&2; return 1 ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'dev-tools-test: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  local description="$1"
  shift
  if "$@" >"$test_dir/command.out" 2>"$test_dir/command.err"; then
    fail "$description unexpectedly succeeded"
  fi
}

working="$test_dir/working"
fresh="$test_dir/fresh"
mkdir -p "$working/lib" "$fresh/lib" "$working/.dart_tool/pub-cache/pkg/lib" "$fresh/.dart_tool/pub-cache/pkg/lib"
printf 'generated\n' >"$working/lib/model.g.dart"
printf 'generated\n' >"$fresh/lib/model.g.dart"
printf 'old cache\n' >"$working/.dart_tool/pub-cache/pkg/lib/cache.g.dart"
printf 'new cache\n' >"$fresh/.dart_tool/pub-cache/pkg/lib/cache.g.dart"
"$repo_root/scripts/compare-dart-generated.sh" "$working" "$fresh" >/dev/null

printf 'different\n' >"$fresh/lib/model.g.dart"
expect_failure 'generated content mismatch' "$repo_root/scripts/compare-dart-generated.sh" "$working" "$fresh"
printf 'generated\n' >"$fresh/lib/model.g.dart"
printf 'extra\n' >"$working/lib/extra.g.dart"
expect_failure 'extra generated file' "$repo_root/scripts/compare-dart-generated.sh" "$working" "$fresh"

expect_failure 'invalid development profile' env ROOT_DIR="$repo_root" PROFILE=unknown "$repo_root/scripts/dev-check.sh"
expect_failure 'invalid run target' env ROOT_DIR="$repo_root" TARGET=unknown DEVICE_ID=test API_BASE_URL=http://10.0.2.2:8080 "$repo_root/scripts/dev-session.sh"
expect_failure 'invalid APK URL' env ROOT_DIR="$repo_root" API_BASE_URL='http://user@example.test:8080' "$repo_root/scripts/flutter-build-android.sh"

go build -o "$test_dir/run-in-session" "$repo_root/scripts/run-in-session.go"
RUN_IN_SESSION_READY_FILE="$test_dir/launcher.ready" \
  "$test_dir/run-in-session" /bin/sh -c 'sleep 30 & wait' &
launcher_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -s "$test_dir/launcher.ready" ]]; then
    break
  fi
  sleep 0.1
done
[[ "$(tr -d '[:space:]' <"$test_dir/launcher.ready")" == "$launcher_pid" ]] || fail 'launcher did not report its owned process group'
kill -TERM -- "-$launcher_pid"
wait "$launcher_pid" >/dev/null 2>&1 || :
if kill -0 -- "-$launcher_pid" >/dev/null 2>&1; then
  fail 'launcher process group remained after TERM'
fi

RUN_IN_SESSION_READY_FILE="$test_dir/exited-launcher.ready" \
  "$test_dir/run-in-session" /bin/sh -c 'trap "" HUP; sleep 30 &' &
exited_launcher_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -s "$test_dir/exited-launcher.ready" ]]; then
    break
  fi
  sleep 0.1
done
[[ "$(tr -d '[:space:]' <"$test_dir/exited-launcher.ready")" == "$exited_launcher_pid" ]] || fail 'exited launcher did not report its owned process group'
wait "$exited_launcher_pid" >/dev/null 2>&1 || :
kill -0 -- "-$exited_launcher_pid" >/dev/null 2>&1 || fail 'child process group did not survive its launcher leader'
exited_launcher_pgid="$(dev_wait_for_owned_group "$exited_launcher_pid" fixture "$test_dir/exited-launcher.ready")"
[[ "$exited_launcher_pgid" == "$exited_launcher_pid" ]] || fail 'wait helper did not retain the leaderless process group ID'
dev_stop_owned_group "$exited_launcher_pid" "$exited_launcher_pgid" fixture || fail 'stop helper failed for the leaderless process group'
if kill -0 -- "-$exited_launcher_pid" >/dev/null 2>&1; then
  kill -KILL -- "-$exited_launcher_pid" >/dev/null 2>&1 || :
  fail 'leaderless process group remained after TERM'
fi

printf 'dev-tools-test: passed\n'
