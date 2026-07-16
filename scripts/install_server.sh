#!/bin/bash
#
# Shared server-file installer/updater.
# Handles both the legacy single-updater lock flow and the newer
# master/follower coordination path for shared ServerFiles.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/update_coordination.sh"

LOCK_HELD=false
TEMP_DOWNLOAD_DIR=""
COORDINATION_LEADER=false

cleanup() {
  local exit_code=$?

  update_coordination_stop_heartbeat
  update_coordination_clear_waiting || true

  if [ -n "$TEMP_DOWNLOAD_DIR" ] && [ -d "$TEMP_DOWNLOAD_DIR" ]; then
    echo "[INFO] Removing temporary download directory: $TEMP_DOWNLOAD_DIR"
    rm -rf "$TEMP_DOWNLOAD_DIR"
  fi

  if [ "$LOCK_HELD" = true ] && declare -f release_update_lock >/dev/null 2>&1; then
    release_update_lock
    LOCK_HELD=false
  fi

  exit $exit_code
}

saved_build_id=""
current_build_id=""

refresh_build_ids() {
  saved_build_id=""
  current_build_id=""

  if saved_build_id=$(get_build_id_from_acf); then
    saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')
    echo "[INFO] Installed build ID: ${saved_build_id:-<none>}"
  else
    echo "[WARNING] Unable to read installed build ID: $saved_build_id"
    saved_build_id=""
  fi

  if current_build_id=$(get_current_build_id); then
    current_build_id=$(echo "$current_build_id" | tr -d '[:space:]')
    echo "[INFO] Available build ID: ${current_build_id:-<unknown>}"
  else
    echo "[WARNING] Unable to query current build ID: $current_build_id"
    current_build_id=""
  fi
}

install_required() {
  refresh_build_ids

  if rollback_state_is_active; then
    if rollback_retry_is_available "$current_build_id"; then
      echo "[INFO] A rollback-protected candidate is eligible for staged compatibility preflight"
      return 0
    fi
    echo "[INFO] Rollback protection remains active; keeping the known-good server files"
    return 1
  fi

  if [ -z "$current_build_id" ] || [[ "$current_build_id" == error* ]]; then
    echo "[WARNING] Current build ID unavailable; proceeding with staged download as precaution"
    return 0
  fi

  if [ -z "$saved_build_id" ] || [[ "$saved_build_id" == error* ]]; then
    echo "[INFO] No existing installation detected"
    return 0
  fi

  if [[ "$saved_build_id" =~ ^[0-9]+$ ]] && [[ "$current_build_id" =~ ^[0-9]+$ ]]; then
    if [ "$saved_build_id" = "$current_build_id" ]; then
      echo "[INFO] Server files already match the latest build"
      return 1
    fi
  else
    echo "[WARNING] Build IDs not in numeric format. Forcing staged download"
    return 0
  fi

  echo "[INFO] Installed build ($saved_build_id) differs from latest ($current_build_id). Update required"
  return 0
}

wait_for_other_install_if_needed() {
  echo "[INFO] Installation lock held by another instance; waiting for completion"
  if wait_for_update_lock; then
    echo "[INFO] Installation lock released by peer. Re-checking build state"
    if install_required; then
      echo "[INFO] Update still required after peer completed. Attempting to acquire lock again"
      if acquire_update_lock; then
        LOCK_HELD=true
        return 0
      else
        echo "[ERROR] Unable to acquire installation lock after waiting"
        return 1
      fi
    else
      echo "[INFO] Peer completed installation; nothing more to do"
      return 2
    fi
  else
    echo "[ERROR] Timed out waiting for installation lock"
    return 1
  fi
}

install_server_wait_for_coordination_release() {
  local target_build="$1"
  local wait_status=0

  echo "[INFO] FOLLOWER waiting for configured master before touching shared server files"
  update_coordination_mark_waiting

  if ! update_coordination_wait_for_master_cycle "$target_build"; then
    update_coordination_clear_waiting
    echo "[ERROR] This container is configured as UPDATE_COORDINATION_ROLE=FOLLOWER, but no master-led coordination cycle appeared within ${UPDATE_COORDINATION_FOLLOWER_WAIT_FOR_MASTER_SECONDS} seconds."
    echo "[ERROR] If you manage instances with POK-manager.sh, start through ./POK-manager.sh so it can promote or order the leader automatically."
    echo "[ERROR] If you are starting containers manually, change the intended leader instance to UPDATE_COORDINATION_ROLE=MASTER before startup."
    return 1
  fi

  echo "[INFO] Master-led coordination cycle detected. Waiting for leader-ready signal..."

  update_coordination_wait_until_ready_or_promoted
  wait_status=$?
  update_coordination_clear_waiting

  case "$wait_status" in
    0)
      echo "[INFO] Coordination master is ready. Re-checking shared server files before follower startup..."
      update_coordination_followers_start_delay

      if ! install_required; then
        echo "[INFO] Leader already updated the shared server files. Follower can continue startup."
        return 2
      fi

      echo "[ERROR] Coordination cycle reported ready, but installed build still appears outdated. Aborting follower startup."
      return 1
      ;;
    2)
      COORDINATION_LEADER=true
      echo "[WARNING] Promoted this follower to coordination leader for the current cycle"
      return 0
      ;;
    *)
      echo "[ERROR] Coordination cycle failed before this follower was released"
      return 1
      ;;
  esac
}

main() {
  prepare_runtime_env
  trap cleanup EXIT INT TERM
  update_coordination_clear_waiting || true
  update_coordination_cleanup || true

  echo "[INFO] Starting server installation/update process"

  # Coordinated multi-instance path: one leader updates shared files, followers
  # wait for the leader to finish its first startup before proceeding.
  if update_coordination_enabled && update_coordination_has_active_cycle; then
    if update_coordination_is_active_leader; then
      COORDINATION_LEADER=true
      echo "[INFO] This instance is the active coordination leader for the current update cycle"
    elif update_coordination_is_follower_role; then
      install_server_wait_for_coordination_release "${current_build_id:-$saved_build_id}"
      case $? in
        0)
          ;;
        2)
          exit 0
          ;;
        *)
          exit 1
          ;;
      esac
    fi
  fi

  if ! install_required; then
    echo "[INFO] Installation not required"
    if [ "$COORDINATION_LEADER" = true ]; then
      update_coordination_mark_leader_starting || true
    fi
    exit 0
  fi

  if update_coordination_enabled && [ "$COORDINATION_LEADER" != true ]; then
    if update_coordination_is_master_role; then
      echo "[INFO] MASTER starting startup-install coordination cycle for shared server files"
      if update_coordination_begin_cycle "${current_build_id:-$saved_build_id}"; then
        COORDINATION_LEADER=true
      elif update_coordination_has_active_cycle && ! update_coordination_is_active_leader; then
        echo "[INFO] Another coordination cycle already exists. Waiting for that leader before touching shared server files..."
        install_server_wait_for_coordination_release "${current_build_id:-$saved_build_id}"
        case $? in
          0)
            ;;
          2)
            exit 0
            ;;
          *)
            exit 1
            ;;
        esac
      else
        echo "[ERROR] Unable to begin the coordination cycle for startup installation"
        exit 1
      fi
    elif update_coordination_is_follower_role; then
      install_server_wait_for_coordination_release "${current_build_id:-$saved_build_id}"
      case $? in
        0)
          ;;
        2)
          exit 0
          ;;
        *)
          exit 1
          ;;
      esac
    fi
  fi

  if [ "$COORDINATION_LEADER" = true ]; then
    echo "[INFO] Running shared server-file update as the active coordination leader"
    update_coordination_set_phase "leader_updating"
    update_coordination_start_heartbeat

    TEMP_DOWNLOAD_DIR=$(create_temp_download_dir) || exit 1

    echo "[INFO] Temporary download directory created at $TEMP_DOWNLOAD_DIR"

    if ! perform_staged_server_download "$TEMP_DOWNLOAD_DIR"; then
      echo "[ERROR] Staged installation failed"
      exit 1
    fi

    echo "[SUCCESS] Server files downloaded and staged successfully"

    local post_install_build_id
    post_install_build_id=$(get_build_id_from_acf)
    if [ -n "$post_install_build_id" ]; then
      echo "[INFO] Post-install build ID: $post_install_build_id"
    fi

    mark_other_instances_dirty
    update_coordination_stop_heartbeat
    update_coordination_mark_leader_starting || true
    echo "[INFO] Leader update completed. Followers will wait for full server startup before continuing."
    exit 0
  fi

  # Legacy-compatible path for single-instance installs or instances outside the
  # master/follower coordination model.
  echo "[INFO] Attempting to acquire installation lock"
  if acquire_update_lock; then
    LOCK_HELD=true
  else
    wait_for_other_install_if_needed
    case $? in
      0)
        ;;
      2)
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
  fi

  if ! install_required; then
    echo "[INFO] Update already applied by another instance. Skipping download."
    if [ "$LOCK_HELD" = true ]; then
      release_update_lock
      LOCK_HELD=false
    fi
    exit 0
  fi

  TEMP_DOWNLOAD_DIR=$(create_temp_download_dir) || exit 1

  echo "[INFO] Temporary download directory created at $TEMP_DOWNLOAD_DIR"

  if ! perform_staged_server_download "$TEMP_DOWNLOAD_DIR"; then
    echo "[ERROR] Staged installation failed"
    exit 1
  fi

  echo "[SUCCESS] Server files downloaded and staged successfully"

  local post_install_build_id
  post_install_build_id=$(get_build_id_from_acf)
  if [ -n "$post_install_build_id" ]; then
    echo "[INFO] Post-install build ID: $post_install_build_id"
  fi

  mark_other_instances_dirty

  echo "[INFO] Installation/update completed successfully"

  if [ "$LOCK_HELD" = true ]; then
    release_update_lock
    LOCK_HELD=false
  fi

  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
