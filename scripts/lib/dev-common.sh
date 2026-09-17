#!/usr/bin/env bash

dev_error() {
  printf 'dev: %s\n' "$1" >&2
}

dev_wait_for_owned_group() {
  local pid="$1"
  local name="$2"
  local ready_file="$3"
  local ready_pid attempt=0
  while ((attempt < 50)); do
    if [[ -f "$ready_file" ]]; then
      ready_pid="$(tr -d '[:space:]' <"$ready_file")"
      if [[ "$ready_pid" == "$pid" ]]; then
        printf '%s\n' "$pid"
        return 0
      fi
      if [[ -n "$ready_pid" ]]; then
        dev_error "$name launcher wrote an unexpected ready PID."
        return 1
      fi
    fi
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      dev_error "$name launcher exited before creating its process group."
      return 1
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done
  dev_error "$name launcher did not establish an isolated process group."
  return 1
}

dev_stop_owned_group() {
  local pid="$1"
  local pgid="$2"
  local name="$3"
  local attempt=0
  local failed=0
  [[ -n "$pid" ]] || return 0

  if [[ -n "$pgid" ]] && kill -0 -- "-$pgid" >/dev/null 2>&1; then
    if ! kill -TERM -- "-$pgid" >/dev/null 2>&1; then
      dev_error "could not stop the owned $name process group ($pgid)."
      failed=1
    fi
    while kill -0 -- "-$pgid" >/dev/null 2>&1 && ((attempt < 5)); do
      sleep 1
      attempt=$((attempt + 1))
    done
    if kill -0 -- "-$pgid" >/dev/null 2>&1; then
      if ! kill -KILL -- "-$pgid" >/dev/null 2>&1; then
        dev_error "could not force-stop the owned $name process group ($pgid)."
        failed=1
      fi
    fi
  elif [[ -z "$pgid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    # The launcher may be interrupted before it establishes the new session.
    if ! kill -TERM "$pid" >/dev/null 2>&1; then
      dev_error "could not stop the starting $name process ($pid)."
      failed=1
    fi
  fi
  wait "$pid" >/dev/null 2>&1 || :
  return "$failed"
}

dev_validate_profile() {
  case "${1:-}" in
    core|android) ;;
    *)
      dev_error 'PROFILE must be core or android.'
      return 2
      ;;
  esac
}

dev_android_license_state() {
  local status="$1"
  local output="$2"

  if ((status == 0)) && printf '%s\n' "$output" | grep -Eq \
    '(All SDK package licenses accepted|The --licenses option is no longer needed)'; then
    printf 'ready\n'
    return 0
  fi
  if printf '%s\n' "$output" | grep -Eiq \
    '(licenses? (have|has) not been accepted|licenses? not accepted|Review licenses that have not been accepted|Accept\?.*\[y/N\])'; then
    printf 'required\n'
    return 0
  fi
  printf 'unknown\n'
}

dev_android_license_only_issue() {
  local android_section="$1"
  local other_android_errors

  if ! printf '%s\n' "$android_section" | grep -Eiq \
    '(Android license status unknown\.|Some Android licenses not accepted\.|Android licenses not accepted\.)'; then
    return 1
  fi
  other_android_errors="$(printf '%s\n' "$android_section" | grep '    ✗' | grep -Eiv \
    '(Android license status unknown\.|Some Android licenses not accepted\.|Android licenses not accepted\.)' || :)"
  [[ -z "$other_android_errors" ]]
}

dev_probe_android_licenses() {
  local app_dir="$1"
  local license_output license_status=0 license_state

  license_output="$(cd -- "$app_dir" && fvm flutter doctor --android-licenses </dev/null 2>&1)" || license_status=$?
  license_state="$(dev_android_license_state "$license_status" "$license_output")"
  case "$license_state" in
    ready)
      echo 'Android SDK licenses do not require additional acceptance.'
      return 0
      ;;
    required)
      printf '%s\n' "$license_output" >&2
      dev_error 'ANDROID_LICENSES_REQUIRED: ask the user to accept the Android SDK licenses, then run task dev:accept-android-licenses CONFIRM_ANDROID_LICENSES=1.'
      return 10
      ;;
    *)
      printf '%s\n' "$license_output" >&2
      dev_error 'Android SDK license status could not be determined.'
      return 11
      ;;
  esac
}

dev_version_at_least() {
  local actual="$1"
  local minimum="$2"
  awk -v actual="$actual" -v minimum="$minimum" '
    BEGIN {
      split(actual, a, /\./)
      split(minimum, m, /\./)
      for (i = 1; i <= 3; i++) {
        if (a[i] + 0 > m[i] + 0) exit 0
        if (a[i] + 0 < m[i] + 0) exit 1
      }
      exit 0
    }
  '
}

dev_check_compose() {
  local version version_pattern major up_help
  version_pattern='^v?([0-9]+)\.[0-9]+\.[0-9]+([-+][[:alnum:].+-]+)?$'

  if ! version="$(docker compose version --short 2>&1)"; then
    printf '%s\n' "$version" >&2
    dev_error 'Docker Compose CLI is required.'
    return 1
  fi
  if [[ ! "$version" =~ $version_pattern ]]; then
    dev_error "unrecognized Docker Compose version: $version"
    return 1
  fi
  major="${BASH_REMATCH[1]}"
  if ((10#$major < 2)); then
    dev_error 'Docker Compose CLI version 2 or later is required.'
    return 1
  fi
  if ! up_help="$(docker compose up --help 2>&1)"; then
    printf '%s\n' "$up_help" >&2
    dev_error 'could not inspect Docker Compose up capabilities.'
    return 1
  fi
  if ! printf '%s\n' "$up_help" | grep -Eq '^[[:space:]]+--wait([[:space:]]|$)'; then
    dev_error 'Docker Compose must support up --wait.'
    return 1
  fi
  echo "Docker Compose $version is available with up --wait."
}

dev_parse_api_url() {
  local value="$1"
  local rest authority path after_open remainder host port default_port

  DEV_URL_SCHEME=''
  DEV_URL_HOST=''
  DEV_URL_PORT=''

  case "$value" in
    ''|*[![:print:]]*|*' '*|*$'\t'*|*$'\r'*|*$'\n'*)
      return 1
      ;;
  esac
  case "$value" in
    http://*) DEV_URL_SCHEME='http'; default_port='80'; rest="${value#http://}" ;;
    https://*) DEV_URL_SCHEME='https'; default_port='443'; rest="${value#https://}" ;;
    *) return 1 ;;
  esac
  case "$rest" in
    *\?*|*\#*|*@*) return 1 ;;
  esac

  case "$rest" in
    */*)
      authority="${rest%%/*}"
      path="/${rest#*/}"
      [[ "$path" == '/' ]] || return 1
      ;;
    *) authority="$rest" ;;
  esac
  [[ -n "$authority" ]] || return 1

  if [[ "$authority" == \[* ]]; then
    after_open="${authority#\[}"
    [[ "$after_open" == *\]* ]] || return 1
    host="${after_open%%]*}"
    remainder="${after_open#*]}"
    [[ -n "$host" ]] || return 1
    [[ "$host" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
    case "$remainder" in
      '') port="$default_port" ;;
      :*) port="${remainder#:}" ;;
      *) return 1 ;;
    esac
  else
    case "$authority" in
      *:*)
        host="${authority%:*}"
        port="${authority##*:}"
        [[ "$host" != *:* ]] || return 1
        ;;
      *)
        host="$authority"
        port="$default_port"
        ;;
    esac
    [[ "$host" =~ ^[A-Za-z0-9._%-]+$ ]] || return 1
  fi

  [[ -n "$host" && -n "$port" && "$port" =~ ^[0-9]{1,5}$ ]] || return 1
  ((10#$port >= 1 && 10#$port <= 65535)) || return 1

  DEV_URL_HOST="$host"
  DEV_URL_PORT="$port"
}

dev_ipv4_is_usable() {
  awk -v ip="$1" 'BEGIN {
    if (split(ip, octet, ".") != 4) exit 1
    for (i = 1; i <= 4; i++) {
      if (octet[i] !~ /^[0-9]+$/ || octet[i] < 0 || octet[i] > 255) exit 1
    }
    if (octet[1] == 0 || octet[1] == 127 ||
        (octet[1] == 169 && octet[2] == 254)) exit 1
    exit 0
  }'
}

dev_local_lan_ipv4s() {
  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '
      /^[^[:space:]].*:/ {
        interface = $1
        sub(/:$/, "", interface)
      }
      $1 == "inet" && interface ~ /^(en[0-9]+|eth[0-9]*|ens[0-9]+|enp[[:alnum:]_.-]+|wlan[0-9]+|wlp[[:alnum:]_.-]+)$/ {
        print $2
      }
    '
  elif command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null | awk '
      {
        interface = $2
        split($4, address, "/")
        if (interface ~ /^(en[0-9]+|eth[0-9]*|ens[0-9]+|enp[[:alnum:]_.-]+|wlan[0-9]+|wlp[[:alnum:]_.-]+)$/) print address[1]
      }
    '
  else
    return 1
  fi
}

dev_validate_run_url() {
  local target="$1"
  local value="$2"
  local local_ips

  if ! dev_parse_api_url "$value"; then
    dev_error 'API_BASE_URL must be an AppConfig-compatible HTTP(S) base URL without credentials, path, query, or fragment.'
    return 2
  fi
  if [[ "$DEV_URL_SCHEME" != 'http' || "$DEV_URL_PORT" != '8080' ]]; then
    dev_error 'API_BASE_URL for dev:run must use local HTTP port 8080.'
    return 2
  fi
  case "$target" in
    emulator)
      if [[ "$DEV_URL_HOST" != '10.0.2.2' ]]; then
        dev_error 'emulator API_BASE_URL host must be 10.0.2.2.'
        return 2
      fi
      ;;
    device)
      if ! local_ips="$(dev_local_lan_ipv4s)"; then
        dev_error 'cannot inspect local LAN addresses; ifconfig or ip is required for device targets.'
        return 2
      fi
      if ! dev_ipv4_is_usable "$DEV_URL_HOST" || ! printf '%s\n' "$local_ips" | grep -Fxq "$DEV_URL_HOST"; then
        dev_error 'device API_BASE_URL host must be a usable IPv4 address on a local LAN interface.'
        return 2
      fi
      ;;
    *)
      dev_error 'TARGET must be emulator or device.'
      return 2
      ;;
  esac
}
