#!/bin/bash
#
# Library-style health classifier used by the HTTP health endpoint and the
# internal monitor. Safe to source; execution only happens via health_probe_main.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/update_coordination.sh"

HEALTH_STARTUP_MARKER="Server has completed startup and is now advertising for join."

health_probe_update_mode_enabled() {
  env_value_is_truthy "${UPDATE_MODE:-FALSE}"
}

health_probe_rcon_enabled() {
  env_value_is_truthy "${RCON_ENABLED:-FALSE}"
}

health_probe_log_file() {
  echo "${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
}

health_probe_server_pid() {
  local pid=""

  if [ -f "${PID_FILE}" ]; then
    pid=$(cat "${PID_FILE}" 2>/dev/null || true)
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1 && ps -p "$pid" -o cmd= | grep -q -E "ArkAscendedServer.exe|AsaApiLoader.exe"; then
      echo "$pid"
      return 0
    fi
  fi

  if [ "${API}" = "TRUE" ]; then
    pid=$(pgrep -f "AsaApiLoader.exe" | head -1)
    if [ -n "$pid" ]; then
      echo "$pid"
      return 0
    fi
  fi

  pid=$(pgrep -f "ArkAscendedServer.exe" | head -1)
  if [ -n "$pid" ]; then
    echo "$pid"
    return 0
  fi

  return 1
}

health_probe_startup_timed_out() {
  local pid=""
  local elapsed=""
  local startup_grace_seconds="${HEALTH_STARTUP_GRACE_SECONDS:-900}"

  pid="$(health_probe_server_pid)" || return 1
  elapsed="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')" || true

  if ! [[ "$elapsed" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  [ "$elapsed" -ge "$startup_grace_seconds" ]
}

health_probe_has_startup_marker() {
  local log_file
  log_file="$(health_probe_log_file)"

  [ -f "$log_file" ] || return 1

  grep -qF "$HEALTH_STARTUP_MARKER" "$log_file"
}

health_probe_run_rcon_command() {
  local timeout_seconds="${HEALTH_RCON_TIMEOUT:-5}"
  timeout "$timeout_seconds" "${RCON_PATH}" -a "${RCON_HOST}:${RCON_PORT}" -p "${RCON_PASSWORD}" "ListPlayers" 2>&1
}

health_probe_check_rcon() {
  local output=""
  local status=0

  if ! health_probe_rcon_enabled; then
    echo "ok: server ready (rcon disabled)"
    return 0
  fi

  output="$(health_probe_run_rcon_command)"
  status=$?

  if [ "$status" -eq 0 ]; then
    echo "ok: server ready and responding to rcon"
    return 0
  fi

  if [ "$status" -eq 124 ]; then
    echo "degraded: rcon probe timed out"
    return 2
  fi

  if echo "$output" | grep -qi "Failed to connect"; then
    echo "degraded: rcon connection failed"
    return 2
  fi

  if echo "$output" | grep -qi "auth"; then
    echo "degraded: rcon authentication failed"
    return 2
  fi

  echo "degraded: rcon probe failed"
  return 2
}

health_probe_main() {
  local rcon_result=""
  local rcon_status=0
  local had_errexit=0

  prepare_runtime_env

  if health_probe_update_mode_enabled; then
    echo "ok: update mode"
    return 0
  fi

  if update_coordination_is_waiting; then
    echo "starting: waiting for coordination master"
    return 1
  fi

  if ! is_process_running >/dev/null 2>&1; then
    echo "unhealthy: server process not running"
    return 1
  fi

  if ! health_probe_has_startup_marker; then
    if health_probe_startup_timed_out; then
      echo "unhealthy: startup marker timed out"
      return 1
    fi

    echo "starting: startup marker not reached"
    return 1
  fi

  case $- in
  *e*)
    had_errexit=1
    set +e
    ;;
  esac

  rcon_result="$(health_probe_check_rcon)"
  rcon_status=$?

  if [ "$had_errexit" -eq 1 ]; then
    set -e
  fi

  echo "$rcon_result"

  case "$rcon_status" in
  0|2)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -o pipefail
  health_probe_main "$@"
fi
