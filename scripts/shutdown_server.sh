#!/bin/bash
#
# Verified two-stage shutdown helpers shared by manager, monitor, and restart flows.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/rcon_commands.sh"

SHUTDOWN_COMPLETE_FLAG="/home/pok/shutdown_complete.flag"
VERIFIED_SHUTDOWN_MARKER="/home/pok/verified_shutdown_save.flag"
SAVE_CONFIRMATION_SOURCE=""
SAVE_CHECKPOINT_LOG_INODE=""
SAVE_CHECKPOINT_LOG_SIZE=0
SAVE_CHECKPOINT_FILE=""
SAVE_CHECKPOINT_FILE_STATE=""

shutdown_save_wait_seconds() {
  local value="${SAVE_WAIT_SECONDS:-60}"

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "Warning: Invalid SAVE_WAIT_SECONDS '$value'; using 60 seconds." >&2
    value=60
  fi

  if [ "$value" -lt 1 ]; then
    value=1
  elif [ "$value" -gt 900 ]; then
    value=900
  fi

  echo "$value"
}

shutdown_write_verified_marker() {
  date +%s > "$VERIFIED_SHUTDOWN_MARKER"
}

shutdown_verified_marker_is_fresh() {
  local verified_at=""
  local now
  local max_age=120

  [ -f "$VERIFIED_SHUTDOWN_MARKER" ] || return 1
  verified_at=$(cat "$VERIFIED_SHUTDOWN_MARKER" 2>/dev/null || true)
  [[ "$verified_at" =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s)
  [ "$now" -ge "$verified_at" ] && [ $((now - verified_at)) -le "$max_age" ]
}

shutdown_server_process_running() {
  pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 || pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1
}

shutdown_normalized_map_name() {
  local map_name="${MAP_NAME:-}"

  case "$map_name" in
  *_WP)
    echo "$map_name"
    ;;
  "")
    return 1
    ;;
  *)
    echo "${map_name}_WP"
    ;;
  esac
}

shutdown_main_save_file() {
  local save_root="${ASA_DIR}/ShooterGame/Saved/SavedArks"
  local map_name="${MAP_NAME:-}"
  local normalized_map=""
  local -a matches=()

  [ -d "$save_root" ] || return 1
  # MAP_NAME is authoritative and may name an official, future, or modded map.
  if [ -n "$map_name" ]; then
    mapfile -t matches < <(find -L "$save_root" -type f -name "${map_name}.ark" -print 2>/dev/null)
    if [ "${#matches[@]}" -eq 1 ]; then
      echo "${matches[0]}"
      return 0
    fi
    if [ "${#matches[@]}" -gt 1 ]; then
      echo "Warning: Multiple saves named ${map_name}.ark were found; file fallback is disabled." >&2
      return 1
    fi
  fi

  normalized_map="$(shutdown_normalized_map_name 2>/dev/null || true)"

  if [ -n "$normalized_map" ] && [ "$normalized_map" != "$map_name" ]; then
    mapfile -t matches < <(find -L "$save_root" -type f -name "${normalized_map}.ark" -print 2>/dev/null)
    if [ "${#matches[@]}" -eq 1 ]; then
      echo "${matches[0]}"
      return 0
    fi
    if [ "${#matches[@]}" -gt 1 ]; then
      echo "Warning: Multiple saves named ${normalized_map}.ark were found; file fallback is disabled." >&2
      return 1
    fi
  fi

  mapfile -t matches < <(find -L "$save_root" -type f -name '*.ark' -print 2>/dev/null)
  if [ "${#matches[@]}" -eq 1 ]; then
    echo "${matches[0]}"
    return 0
  fi

  if [ "${#matches[@]}" -gt 1 ]; then
    echo "Warning: The main .ark save is ambiguous; file fallback is disabled." >&2
  fi
  return 1
}

shutdown_file_state() {
  local save_file="$1"
  [ -f "$save_file" ] || return 1
  stat -Lc '%s|%y|%i' "$save_file" 2>/dev/null
}

shutdown_capture_save_checkpoint() {
  local log_file="${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"

  SAVE_CHECKPOINT_LOG_INODE=""
  SAVE_CHECKPOINT_LOG_SIZE=0
  SAVE_CHECKPOINT_FILE=""
  SAVE_CHECKPOINT_FILE_STATE=""

  if [ -f "$log_file" ]; then
    SAVE_CHECKPOINT_LOG_INODE="$(stat -Lc '%i' "$log_file" 2>/dev/null || true)"
    SAVE_CHECKPOINT_LOG_SIZE="$(stat -Lc '%s' "$log_file" 2>/dev/null || echo 0)"
  fi

  SAVE_CHECKPOINT_FILE="$(shutdown_main_save_file 2>/dev/null || true)"
  if [ -n "$SAVE_CHECKPOINT_FILE" ]; then
    SAVE_CHECKPOINT_FILE_STATE="$(shutdown_file_state "$SAVE_CHECKPOINT_FILE" 2>/dev/null || true)"
  fi
}

shutdown_log_confirmed_since_checkpoint() {
  local log_file="${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
  local current_inode=""
  local current_size=0

  [ -f "$log_file" ] || return 1
  current_inode="$(stat -Lc '%i' "$log_file" 2>/dev/null || true)"
  current_size="$(stat -Lc '%s' "$log_file" 2>/dev/null || echo 0)"

  if [ -n "$SAVE_CHECKPOINT_LOG_INODE" ] && [ "$current_inode" = "$SAVE_CHECKPOINT_LOG_INODE" ] && [ "$current_size" -ge "$SAVE_CHECKPOINT_LOG_SIZE" ]; then
    tail -c "+$((SAVE_CHECKPOINT_LOG_SIZE + 1))" "$log_file" 2>/dev/null | grep -qF "World Save Complete. Took:"
    return $?
  fi

  # The log was created, rotated, or truncated after the checkpoint.
  grep -qF "World Save Complete. Took:" "$log_file" 2>/dev/null
}

shutdown_print_file_change() {
  local new_state="$1"
  local old_size="${SAVE_CHECKPOINT_FILE_STATE%%|*}"
  local new_size="${new_state%%|*}"

  echo "Save file changed and stabilized: ${SAVE_CHECKPOINT_FILE}"
  echo "  Size: ${old_size:-missing} -> ${new_size:-unknown} bytes"
  echo "  Metadata: ${SAVE_CHECKPOINT_FILE_STATE:-missing} -> ${new_state}"
}

shutdown_verify_command_save() {
  local rcon_command="$1"
  local stage_label="$2"
  local wait_seconds
  local started_at
  local deadline
  local current_state=""
  local previous_changed_state=""
  local stable_seconds=0
  local stable_required="${SAVE_FILE_STABLE_SECONDS:-5}"

  if ! [[ "$stable_required" =~ ^[0-9]+$ ]] || [ "$stable_required" -lt 1 ]; then
    stable_required=5
  fi

  wait_seconds="$(shutdown_save_wait_seconds)"
  shutdown_capture_save_checkpoint
  started_at=$(date +%s)
  deadline=$((started_at + wait_seconds))
  SAVE_CONFIRMATION_SOURCE=""

  echo "${stage_label}: sending RCON command '${rcon_command}' (timeout: ${wait_seconds}s)..."
  if ! send_rcon_command "$rcon_command" "$wait_seconds"; then
    echo "Error: ${stage_label} RCON command failed; save was not verified." >&2
    return 1
  fi

  while [ "$(date +%s)" -lt "$deadline" ]; do
    if shutdown_log_confirmed_since_checkpoint; then
      SAVE_CONFIRMATION_SOURCE="log"
      echo "${stage_label}: save confirmed by a new 'World Save Complete. Took:' log entry."
      return 0
    fi

    if [ -n "$SAVE_CHECKPOINT_FILE" ] && [ -f "$SAVE_CHECKPOINT_FILE" ]; then
      current_state="$(shutdown_file_state "$SAVE_CHECKPOINT_FILE" 2>/dev/null || true)"
      if [ -n "$current_state" ] && [ "${current_state%%|*}" -gt 0 ] 2>/dev/null && [ "$current_state" != "$SAVE_CHECKPOINT_FILE_STATE" ]; then
        if [ "$current_state" = "$previous_changed_state" ]; then
          stable_seconds=$((stable_seconds + 1))
        else
          previous_changed_state="$current_state"
          stable_seconds=0
        fi

        if [ "$stable_seconds" -ge "$stable_required" ]; then
          SAVE_CONFIRMATION_SOURCE="file"
          echo "Warning: ${stage_label} had no fresh completion log; accepting stable .ark metadata fallback."
          shutdown_print_file_change "$current_state"
          return 0
        fi
      else
        previous_changed_state=""
        stable_seconds=0
      fi
    fi

    sleep 1
  done

  echo "Error: ${stage_label} was not confirmed within ${wait_seconds} seconds." >&2
  if [ -n "$SAVE_CHECKPOINT_FILE" ]; then
    current_state="$(shutdown_file_state "$SAVE_CHECKPOINT_FILE" 2>/dev/null || true)"
    echo "  Save file: $SAVE_CHECKPOINT_FILE" >&2
    echo "  Before: ${SAVE_CHECKPOINT_FILE_STATE:-missing}" >&2
    echo "  After:  ${current_state:-missing}" >&2
  else
    echo "  No unambiguous main .ark file was available for fallback verification." >&2
  fi
  return 1
}

verified_saveworld() {
  shutdown_verify_command_save "saveworld" "Stage 1 SaveWorld"
}

verified_doexit_save() {
  if shutdown_verify_command_save "DoExit" "Stage 2 DoExit save"; then
    shutdown_write_verified_marker
    return 0
  fi
  return 1
}

shutdown_wait_for_server_exit() {
  local max_wait="${1:-60}"
  local elapsed=0

  while shutdown_server_process_running && [ "$elapsed" -lt "$max_wait" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if shutdown_server_process_running; then
    echo "Warning: ASA is still running after ${max_wait} seconds; both saves are verified, so container termination is data-safe." >&2
    return 1
  fi

  echo "ASA server process exited cleanly."
  return 0
}

# Used by direct container stops and in-container restart/update workflows.
safe_container_stop() {
  rm -f "$SHUTDOWN_COMPLETE_FLAG"

  if shutdown_verified_marker_is_fresh; then
    echo "A fresh verified DoExit save marker is present; no additional save is required."
    touch "$SHUTDOWN_COMPLETE_FLAG"
    return 0
  fi
  rm -f "$VERIFIED_SHUTDOWN_MARKER"

  if ! shutdown_server_process_running; then
    echo "Server is not running, no need to save world before stopping container."
    touch "$SHUTDOWN_COMPLETE_FLAG"
    return 0
  fi

  echo "---- Verified two-stage container stop initiated ----"
  send_rcon_command "ServerChat Server is stopping. Saving world data now..." 10 || true

  verified_saveworld || return 1
  verified_doexit_save || return 1
  shutdown_wait_for_server_exit 60 || true

  touch "$SHUTDOWN_COMPLETE_FLAG"
  echo "---- Both world saves verified; container is safe to stop ----"
  return 0
}

shutdown_handler() {
  local with_restart="${1:-false}"

  if [ "$with_restart" = "true" ]; then
    send_rcon_command "ServerChat Server restart initiated. Saving world data..." 10 || true
  fi

  if ! safe_container_stop; then
    echo "FATAL: Safe shutdown aborted because a world save could not be verified." >&2
    return 1
  fi

  return 0
}

initiate_shutdown() {
  local duration_in_minutes="${1:-}"
  local total_seconds

  if ! [[ "$duration_in_minutes" =~ ^[0-9]+$ ]]; then
    echo "Error: Shutdown command requires a non-negative duration in minutes." >&2
    return 1
  fi

  # rcon_interface.sh already rendered the countdown when this marker exists.
  if [ ! -f "/tmp/enhanced_shutdown_display" ]; then
    total_seconds=$((duration_in_minutes * 60))
    [ "$total_seconds" -gt 0 ] && sleep "$total_seconds"
  fi

  safe_container_stop
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  prepare_runtime_env
  case "${1:-}" in
  restart)
    shutdown_handler true
    ;;
  container-stop)
    safe_container_stop
    ;;
  verify-save)
    verified_saveworld
    ;;
  verify-doexit)
    verified_doexit_save
    ;;
  *)
    shutdown_handler false
    ;;
  esac
fi
