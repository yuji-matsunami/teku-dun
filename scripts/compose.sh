#!/usr/bin/env bash

set -euo pipefail

fail_input() {
  echo "db: $1" >&2
  exit 1
}

compose_command="${COMPOSE:-docker compose}"
db_service="${DB_SERVICE:-db}"
migrate_service="${MIGRATE_SERVICE:-migrate}"

# COMPOSE is intentionally a command string for compatibility with the old
# Make targets. Only shell-free command-line characters are accepted, so the
# simple whitespace split below cannot turn into shell syntax. Bash 3 (the
# version shipped with macOS) supports read -a and array expansion used here.
if [[ -z "$compose_command" || "$compose_command" =~ [^[:alnum:]_./:=+,\ -] ]]; then
  fail_input 'COMPOSE must contain only command, option, path, and space characters.'
fi
read -r -a compose_argv <<< "$compose_command"
if ((${#compose_argv[@]} == 0)); then
  fail_input 'COMPOSE must not be empty.'
fi

case "$db_service" in
  ''|*[![:alnum:]_.-]*)
    fail_input 'DB_SERVICE must be a simple Compose service name.'
    ;;
esac
case "$migrate_service" in
  ''|*[![:alnum:]_.-]*)
    fail_input 'MIGRATE_SERVICE must be a simple Compose service name.'
    ;;
esac

if (($# != 1)); then
  fail_input 'an internal database task name is required.'
fi

case "$1" in
  up)
    "${compose_argv[@]}" up -d --wait "$db_service"
    ;;
  migrate)
    "${compose_argv[@]}" run --rm -e 'MIGRATE_COMMAND=up' "$migrate_service"
    ;;
  migrate-down)
    "${compose_argv[@]}" run --rm -e 'MIGRATE_COMMAND=down 1' "$migrate_service"
    ;;
  verify)
    "${compose_argv[@]}" exec -T "$db_service" sh -c \
      'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT PostGIS_Version();"'
    ;;
  down)
    "${compose_argv[@]}" down
    ;;
  reset)
    "${compose_argv[@]}" down -v
    ;;
  *)
    fail_input "unknown database task: $1"
    ;;
esac
