#!/bin/bash
#
# Health-state tracking helpers for the long-running monitor.
# Safe to source; no work is performed until functions are called.

MONITOR_HEALTH_FAILURE_THRESHOLD="${MONITOR_HEALTH_FAILURE_THRESHOLD:-3}"
MONITOR_HEALTH_FAILURE_COUNT="${MONITOR_HEALTH_FAILURE_COUNT:-0}"
MONITOR_LAST_HEALTH_STATE="${MONITOR_LAST_HEALTH_STATE:-}"
MONITOR_LAST_HEALTH_MESSAGE="${MONITOR_LAST_HEALTH_MESSAGE:-}"
MONITOR_DEGRADED_RECOVERY_GRACE_SECONDS="${MONITOR_DEGRADED_RECOVERY_GRACE_SECONDS:-86400}"
MONITOR_DEGRADED_STARTED_AT="${MONITOR_DEGRADED_STARTED_AT:-0}"
MONITOR_DEGRADED_RECOVERY_ATTEMPTED="${MONITOR_DEGRADED_RECOVERY_ATTEMPTED:-0}"
MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT="${MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT:-0}"
MONITOR_DEGRADED_POST_RECOVERY_LOGGED="${MONITOR_DEGRADED_POST_RECOVERY_LOGGED:-0}"
MONITOR_DEGRADED_EPISODE_ACTIVE="${MONITOR_DEGRADED_EPISODE_ACTIVE:-0}"

monitor_health_state_dir() {
  local asa_dir="${ASA_DIR:-/home/pok/arkserver}"
  echo "${asa_dir}/ShooterGame/Saved/Config/POK-manager"
}

monitor_health_state_file() {
  echo "$(monitor_health_state_dir)/monitor_health_state.env"
}

monitor_health_now() {
  date +%s
}

monitor_health_reset_degraded_state() {
  MONITOR_DEGRADED_STARTED_AT=0
  MONITOR_DEGRADED_RECOVERY_ATTEMPTED=0
  MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT=0
  MONITOR_DEGRADED_POST_RECOVERY_LOGGED=0
  MONITOR_DEGRADED_EPISODE_ACTIVE=0
}

monitor_health_save_state() {
  local state_dir=""
  local state_file=""

  state_dir="$(monitor_health_state_dir)"
  state_file="$(monitor_health_state_file)"

  mkdir -p "$state_dir"

  cat >"$state_file" <<EOF
MONITOR_DEGRADED_STARTED_AT=${MONITOR_DEGRADED_STARTED_AT}
MONITOR_DEGRADED_RECOVERY_ATTEMPTED=${MONITOR_DEGRADED_RECOVERY_ATTEMPTED}
MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT=${MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT}
MONITOR_DEGRADED_POST_RECOVERY_LOGGED=${MONITOR_DEGRADED_POST_RECOVERY_LOGGED}
MONITOR_DEGRADED_EPISODE_ACTIVE=${MONITOR_DEGRADED_EPISODE_ACTIVE}
EOF
}

monitor_health_load_state() {
  local state_file=""

  monitor_health_reset_degraded_state
  state_file="$(monitor_health_state_file)"

  [ -f "$state_file" ] || return 0

  # shellcheck source=/dev/null
  source "$state_file"

  MONITOR_DEGRADED_STARTED_AT="${MONITOR_DEGRADED_STARTED_AT:-0}"
  MONITOR_DEGRADED_RECOVERY_ATTEMPTED="${MONITOR_DEGRADED_RECOVERY_ATTEMPTED:-0}"
  MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT="${MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT:-0}"
  MONITOR_DEGRADED_POST_RECOVERY_LOGGED="${MONITOR_DEGRADED_POST_RECOVERY_LOGGED:-0}"
  MONITOR_DEGRADED_EPISODE_ACTIVE="${MONITOR_DEGRADED_EPISODE_ACTIVE:-0}"
}

monitor_health_clear_degraded_state() {
  local state_file=""

  monitor_health_reset_degraded_state
  state_file="$(monitor_health_state_file)"
  rm -f "$state_file"
}

monitor_health_degraded_elapsed_seconds() {
  local now="${1:-}"

  if [ "${MONITOR_DEGRADED_EPISODE_ACTIVE:-0}" -ne 1 ] || [ "${MONITOR_DEGRADED_STARTED_AT:-0}" -le 0 ]; then
    echo 0
    return 0
  fi

  if [ -z "$now" ]; then
    now="$(monitor_health_now)"
  fi

  echo $((now - MONITOR_DEGRADED_STARTED_AT))
}

monitor_health_note_degraded() {
  local now="${1:-}"

  if [ -z "$now" ]; then
    now="$(monitor_health_now)"
  fi

  if [ "${MONITOR_DEGRADED_EPISODE_ACTIVE:-0}" -ne 1 ] || [ "${MONITOR_DEGRADED_STARTED_AT:-0}" -le 0 ]; then
    MONITOR_DEGRADED_STARTED_AT="$now"
    MONITOR_DEGRADED_RECOVERY_ATTEMPTED=0
    MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT=0
    MONITOR_DEGRADED_POST_RECOVERY_LOGGED=0
    MONITOR_DEGRADED_EPISODE_ACTIVE=1
    monitor_health_save_state
    return 0
  fi

  return 1
}

monitor_health_should_trigger_degraded_recovery() {
  local now="${1:-}"
  local elapsed=0

  if [ "${MONITOR_DEGRADED_EPISODE_ACTIVE:-0}" -ne 1 ]; then
    return 1
  fi

  if [ "${MONITOR_DEGRADED_RECOVERY_ATTEMPTED:-0}" -eq 1 ]; then
    return 1
  fi

  elapsed="$(monitor_health_degraded_elapsed_seconds "$now")"
  [ "$elapsed" -ge "${MONITOR_DEGRADED_RECOVERY_GRACE_SECONDS}" ]
}

monitor_health_mark_degraded_recovery_attempted() {
  local now="${1:-}"

  if [ -z "$now" ]; then
    now="$(monitor_health_now)"
  fi

  MONITOR_DEGRADED_RECOVERY_ATTEMPTED=1
  MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT="$now"
  MONITOR_DEGRADED_POST_RECOVERY_LOGGED=0
  MONITOR_DEGRADED_EPISODE_ACTIVE=1
  monitor_health_save_state
}

monitor_health_should_log_post_recovery_degraded() {
  if [ "${MONITOR_DEGRADED_EPISODE_ACTIVE:-0}" -ne 1 ]; then
    return 1
  fi

  if [ "${MONITOR_DEGRADED_RECOVERY_ATTEMPTED:-0}" -ne 1 ]; then
    return 1
  fi

  [ "${MONITOR_DEGRADED_POST_RECOVERY_LOGGED:-0}" -ne 1 ]
}

monitor_health_mark_post_recovery_degraded_logged() {
  MONITOR_DEGRADED_POST_RECOVERY_LOGGED=1
  monitor_health_save_state
}

monitor_health_probe_command() {
  /home/pok/scripts/health_probe.sh
}

monitor_health_read_state() {
  local output=""
  local status=0
  local state=""

  output="$(monitor_health_probe_command 2>&1)"
  status=$?

  case "$output" in
  ok:*)
    state="ok"
    ;;
  degraded:*)
    state="degraded"
    ;;
  starting:*)
    state="starting"
    ;;
  unhealthy:*)
    state="unhealthy"
    ;;
  *)
    if [ "$status" -eq 0 ]; then
      state="ok"
      output="ok: health probe passed"
    else
      state="unhealthy"
      output="unhealthy: health probe failed"
    fi
    ;;
  esac

  printf '%s\n%s\n' "$state" "$output"
}

monitor_health_track_state() {
  local state="$1"

  case "$state" in
  ok|degraded)
    MONITOR_HEALTH_FAILURE_COUNT=0
    return 1
    ;;
  starting)
    return 1
    ;;
  unhealthy)
    MONITOR_HEALTH_FAILURE_COUNT=$((MONITOR_HEALTH_FAILURE_COUNT + 1))
    if [ "$MONITOR_HEALTH_FAILURE_COUNT" -ge "$MONITOR_HEALTH_FAILURE_THRESHOLD" ]; then
      return 0
    fi
    return 1
    ;;
  *)
    return 1
    ;;
  esac
}

monitor_health_should_log_state() {
  local state="$1"
  local message="$2"

  if [ "$state" = "unhealthy" ] || [ "$state" != "$MONITOR_LAST_HEALTH_STATE" ] || [ "$message" != "$MONITOR_LAST_HEALTH_MESSAGE" ]; then
    MONITOR_LAST_HEALTH_STATE="$state"
    MONITOR_LAST_HEALTH_MESSAGE="$message"
    return 0
  fi

  return 1
}
