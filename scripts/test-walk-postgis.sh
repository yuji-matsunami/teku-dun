#!/bin/sh

set -eu

: "${POSTGIS_TEST_IMAGE:?POSTGIS_TEST_IMAGE is required}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/teku-dun-postgis-test.XXXXXX")"
cid_file="$tmp_dir/cid"
container_id=''
test_pid=''

cleanup() {
  exit_code=$?
  trap - EXIT
  trap '' INT TERM
  if [ -z "$container_id" ] && [ -s "$cid_file" ]; then
    container_id="$(cat "$cid_file" 2>/dev/null || true)"
  fi
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir" || true
  exit "$exit_code"
}
signal_exit() {
  signal_status=$1
  trap '' INT TERM
  set +u
  if [ "$test_pid" = 'starting' ]; then
    test_pid=$!
  fi
  if [ -n "$test_pid" ]; then
    kill -TERM -"$test_pid" >/dev/null 2>&1 || kill -TERM "$test_pid" >/dev/null 2>&1 || true
    wait "$test_pid" 2>/dev/null || true
    test_pid=''
  fi
  exit "$signal_status"
}
trap cleanup EXIT
trap 'signal_exit 130' INT
trap 'signal_exit 143' TERM

docker run --detach --rm \
  --cidfile "$cid_file" \
  --platform linux/amd64 \
  --env POSTGRES_DB=walk_test \
  --env POSTGRES_USER=walk_test \
  --env POSTGRES_PASSWORD=walk_test \
  --publish 127.0.0.1::5432 \
  "$POSTGIS_TEST_IMAGE" >/dev/null
container_id="$(cat "$cid_file")"

attempt=0
until docker exec "$container_id" pg_isready -h 127.0.0.1 -U walk_test -d walk_test >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ] || [ "$(docker inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || true)" != 'true' ]; then
    docker logs "$container_id" >&2 || true
    echo 'PostGIS test container did not become ready' >&2
    exit 1
  fi
  sleep 1
done

published="$(docker port "$container_id" 5432/tcp)"
host_port="${published##*:}"
case "$host_port" in
  ''|*[!0-9]*)
    echo "Could not determine the PostGIS test port: $published" >&2
    exit 1
    ;;
esac

cd api
set -m
test_pid='starting'
TEST_DATABASE_URL="postgres://walk_test:walk_test@127.0.0.1:${host_port}/walk_test?sslmode=disable" \
  go test -race -count=1 ./internal/httpapi -run '^TestWalkHTTPPostGIS$' &
test_pid=$!
if wait "$test_pid"; then
  test_status=0
else
  test_status=$?
fi
set +m
test_pid=''
exit "$test_status"
