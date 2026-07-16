#!/bin/bash
#
# Update monitor worker. Coordinates player warnings, restart orchestration,
# and the handoff into either legacy lock flow or master/follower coordination.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/rcon_commands.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/update_coordination.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/shutdown_server.sh"

LOCK_HELD=false
TEMP_DOWNLOAD_DIR=""

# Note: RESTART_NOTICE_MINUTES is set by the user in docker-compose.yaml
# We'll use it directly in the script with appropriate defaults where needed

# Create a cleanup function to remove the updating.flag
cleanup() {
  local exit_code=$?
  
  echo "[INFO] Update script cleanup triggered (exit code: $exit_code)"
  
  if [ "$LOCK_HELD" = true ]; then
    # Use the proper lock release function from common.sh if available
    if declare -f release_update_lock >/dev/null 2>&1; then
      echo "[INFO] Using proper lock release function..."
      release_update_lock
    else
      # Fallback to manual cleanup
      echo "[INFO] Using fallback lock cleanup..."
      if [ -f "$ASA_DIR/updating.flag" ]; then
        echo "[INFO] Removing updating.flag due to script exit"
        rm -f "$ASA_DIR/updating.flag"
      fi
      
      # Clean up any flock file descriptors
      if [ -n "$UPDATE_LOCK_FD" ]; then
        echo "[INFO] Closing update lock file descriptor $UPDATE_LOCK_FD"
        flock -u $UPDATE_LOCK_FD 2>/dev/null || true
        exec {UPDATE_LOCK_FD}>&- 2>/dev/null || true
        unset UPDATE_LOCK_FD
      fi
    fi
    LOCK_HELD=false
  fi
  
  if [ -n "$TEMP_DOWNLOAD_DIR" ] && [ -d "$TEMP_DOWNLOAD_DIR" ]; then
    echo "[INFO] Removing temporary download directory: $TEMP_DOWNLOAD_DIR"
    rm -rf "$TEMP_DOWNLOAD_DIR"
  fi

  # Clean up SteamCMD temporary files to save disk space
  echo "[INFO] Cleaning up SteamCMD temporary files..."
  rm -rf /opt/steamcmd/Steam/logs/* 2>/dev/null || true
  rm -rf /opt/steamcmd/Steam/appcache/httpcache/* 2>/dev/null || true
  rm -rf /tmp/SteamCMD_* 2>/dev/null || true
  
  echo "[INFO] Update script cleanup completed"
  
  # Return the original exit code
  exit $exit_code
}

# Function to check if the server needs to be updated - enhanced with dirty flag support
server_needs_update() {
  echo "[INFO] Checking for updates using enhanced system (SteamCMD + dirty flags)..."
  
  # Use the enhanced function from common.sh that includes dirty flag check
  if server_needs_update_or_restart; then
    # Check if this is due to a dirty flag (other instance updated) vs actual update
    if has_dirty_flag; then
      echo "[INFO] ✅ RESTART REQUIRED - Instance marked dirty by another instance that updated server files"
      current_build_id=$(get_current_build_id)  # Get current for consistency
      return 0  # Restart needed
    else
      # This is a real update case
      local current_build=$(get_current_build_id)
      
      if [ -z "$current_build" ] || [[ "$current_build" == error* ]]; then
        echo "[WARNING] Could not get current build ID from SteamCMD. Retrying up to 3 times..."
        
        # Retry logic for getting build ID
        for retry in {1..3}; do
          echo "[INFO] Retry $retry/3 getting build ID from SteamCMD..."
          sleep 5
          current_build=$(get_current_build_id)
          if [ -n "$current_build" ] && [[ ! "$current_build" == error* ]]; then
            echo "[SUCCESS] Successfully got build ID on retry $retry: $current_build"
            break
          fi
          
          if [ $retry -eq 3 ] && ([ -z "$current_build" ] || [[ "$current_build" == error* ]]); then
            echo "[ERROR] Failed to get current build ID from SteamCMD after 3 retries."
            return 1
          fi
        done
      fi
      
      # Validate that the current build ID is numeric only
      if ! [[ "$current_build" =~ ^[0-9]+$ ]]; then
        echo "[WARNING] SteamCMD returned invalid build ID format: '$current_build'"
        return 1
      fi
      
      # Get saved build ID from ACF file
      local saved_build_id=$(get_build_id_from_acf)
      
      # Validate that the saved build ID is numeric only
      if ! [[ "$saved_build_id" =~ ^[0-9]+$ ]]; then
        echo "[WARNING] Saved build ID has invalid format: '$saved_build_id'. Will attempt update."
        saved_build_id=""  # Force update by invalidating the saved ID
      fi
      
      # Ensure both IDs are stripped of any whitespace
      current_build=$(echo "$current_build" | tr -d '[:space:]')
      saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')
      
      echo "========================================================"
      echo "[INFO] 🔵 SteamCMD Current Build ID: $current_build"
      echo "[INFO] 🟢 Server Installed Build ID: $saved_build_id"
      echo "========================================================"
      
      # Diagnostic comparison for debugging
      if [ "${VERBOSE_DEBUG}" = "TRUE" ]; then
        echo "[DEBUG] Detailed comparison:"
        echo "   - Current: '${current_build}' (length: ${#current_build})"
        echo "   - Saved: '${saved_build_id}' (length: ${#saved_build_id})"
        if [ "$current_build" = "$saved_build_id" ]; then
          echo "   - String comparison result: MATCH"
        else
          echo "   - String comparison result: DIFFERENT"
        fi
      fi
      
      echo "[INFO] ✅ UPDATE AVAILABLE - SteamCMD has newer build ($current_build) than installed ($saved_build_id)"
      current_build_id=$current_build  # Update global variable for later use
      return 0  # Update needed
    fi
  else
    echo "[INFO] ✅ Server is up to date - no update or restart needed"
    return 1  # No update needed
  fi
}

# Function to notify players about the upcoming update
notify_players_of_update() {
  local minutes=$1
  
  echo "[INFO] Notifying players about update in $minutes minutes..."
  
  # Send message through RCON
  send_rcon_command "ServerChat Server update detected! Server will restart in $minutes minutes for the update."
  
  # If minutes is greater than 5, send additional notices at intervals
  if [ $minutes -gt 5 ]; then
    # Send notice at half-way point
    local halfway_minutes=$((minutes / 2))
    sleep $((halfway_minutes * 60))
    send_rcon_command "ServerChat Server update reminder: Restart in $halfway_minutes minutes."
    
    # Additional reminders at 5, 2, and 1 minute marks
    if [ $halfway_minutes -gt 5 ]; then
      sleep $(( (halfway_minutes - 5) * 60 ))
      send_rcon_command "ServerChat Server update imminent: Restart in 5 minutes."
      sleep 180 # 3 minutes
      send_rcon_command "ServerChat Server update imminent: Restart in 2 minutes."
      sleep 60 # 1 minute
      send_rcon_command "ServerChat FINAL WARNING: Server restart in 1 minute for update!"
    else
      local remaining_minutes=$((halfway_minutes))
      sleep $(( (remaining_minutes - 1) * 60 ))
      send_rcon_command "ServerChat FINAL WARNING: Server restart in 1 minute for update!"
    fi
  else
    # For short countdowns, just wait until the last minute
    if [ $minutes -gt 1 ]; then
      sleep $(( (minutes - 1) * 60 ))
      send_rcon_command "ServerChat FINAL WARNING: Server restart in 1 minute for update!"
    fi
  fi
  
  # Final countdown in seconds
  sleep 30
  send_rcon_command "ServerChat Server restarting in 30 seconds for update..."
  sleep 20
  send_rcon_command "ServerChat Server restarting in 10 seconds for update..."
  sleep 5
  send_rcon_command "ServerChat 5..."
  sleep 1
  send_rcon_command "ServerChat 4..."
  sleep 1
  send_rcon_command "ServerChat 3..."
  sleep 1
  send_rcon_command "ServerChat 2..."
  sleep 1
  send_rcon_command "ServerChat 1..."
  sleep 1
  send_rcon_command "ServerChat Server restarting NOW!"
}

# Function to prepare for container exit and restart
shutdown_server_for_update() {
  echo "[INFO] Preparing server for update/restart..."

  if ! safe_container_stop; then
    echo "[ERROR] Update/restart aborted: SaveWorld and DoExit saves were not both verified." >&2
    return 1
  fi

  echo "[INFO] Both save stages verified. Ready for staging update."
  return 0
}

trigger_container_restart() {
  local reason="${1:-UPDATE_RESTART}"
  local expected_build="${2:-$current_build_id}"

  echo "🔄 Container will now exit for restart via Docker"
  echo "⚠️ Docker will automatically restart the container"
  request_verified_container_restart "$reason" "$expected_build" "/home/pok/container_update_restart.log"
}

main() {
  prepare_runtime_env
  current_build_id=$(get_current_build_id)
  update_coordination_cleanup || true

  if ! env_value_is_truthy "${UPDATE_SERVER:-FALSE}"; then
    echo "[INFO] UPDATE_SERVER disabled; skipping update workflow."
    exit 0
  fi

  trap cleanup EXIT INT TERM

  echo "[INFO] Checking for ARK server updates..."
  remove_stale_lock

  if server_needs_update; then
    echo "[INFO] Server update/restart required: Current build ID: $current_build_id, Installed build ID: $(get_build_id_from_acf)"

    if has_dirty_flag; then
      echo "[INFO] This instance needs restart due to server files updated by another instance"
      echo "[INFO] No download required - just restarting to load updated files"

      clear_dirty_flag

      local dirty_restart_notice
      dirty_restart_notice=${RESTART_NOTICE_MINUTES:-5}
      echo "[INFO] Notifying players about restart (dirty flag) with $dirty_restart_notice minute notice"
      notify_players_of_update $dirty_restart_notice

      echo "[INFO] Countdown completed. Preparing server for restart..."
      shutdown_server_for_update || return 1
      trigger_container_restart "DIRTY_RESTART" "$current_build_id"
    elif update_coordination_enabled; then
      # Coordinated multi-instance path. The configured master is the only
      # instance allowed to lead the shared update/startup cycle.
      if update_coordination_is_master_role; then
        if ! update_coordination_begin_cycle "$current_build_id"; then
          echo "[WARNING] Unable to create a new coordination cycle right now. Another cycle may already be active."
          exit 0
        fi

        echo "[INFO] This instance is the configured coordination master and will lead the shared update cycle"

        local update_notice_minutes
        update_notice_minutes=${RESTART_NOTICE_MINUTES:-30}
        echo "[INFO] Notifying players about update with $update_notice_minutes minute notice"
        notify_players_of_update $update_notice_minutes

        echo "[INFO] Countdown completed. Stopping server for update..."
        shutdown_server_for_update || return 1
        echo "[INFO] Server shutdown confirmed. Update will be applied during container startup."
        trigger_container_restart "UPDATE_RESTART" "$current_build_id"
      else
        echo "[INFO] This instance is a coordination follower. Waiting briefly for the configured master to begin the cycle..."

        if ! update_coordination_wait_for_master_cycle "$current_build_id"; then
          echo "[WARNING] No active master-led cycle detected yet. Leaving this follower running and waiting for the next update check."
          exit 0
        fi

        echo "[INFO] Master-led cycle detected. Preparing this follower to restart and wait for the leader-ready signal."

        local follower_notice_minutes
        follower_notice_minutes=${RESTART_NOTICE_MINUTES:-30}
        echo "[INFO] Notifying players about update with $follower_notice_minutes minute notice"
        notify_players_of_update $follower_notice_minutes

        echo "[INFO] Countdown completed. Preparing follower for coordinated restart..."
        shutdown_server_for_update || return 1
        trigger_container_restart "FOLLOWER_COORDINATION_RESTART" "$current_build_id"
      fi
    else
      # Legacy-compatible path for single-instance installs or setups that do
      # not participate in master/follower coordination.
      echo "[INFO] Actual server update required - will restart container and apply on startup"

      if ! acquire_update_lock; then
        echo "[WARNING] Another instance is coordinating the update. Waiting for it to finish..."

        if wait_for_update_lock; then
          echo "[INFO] Peer released the update lock. Re-checking if restart is still required..."

          if ! server_needs_update; then
            echo "[INFO] Server is now up to date. No restart needed."
            exit 0
          fi

          echo "[WARNING] Server still reports an outdated build. Attempting to coordinate update again."
          if ! acquire_update_lock; then
            echo "[ERROR] Unable to acquire update lock after peer completed update"
            exit 1
          fi
        else
          echo "[ERROR] Timed out waiting for update lock. Aborting update."
          exit 1
        fi
      fi

      LOCK_HELD=true
      echo "[INFO] Acquired update lock. Preparing graceful shutdown before container restart..."

      local update_notice_minutes
      update_notice_minutes=${RESTART_NOTICE_MINUTES:-30}
      echo "[INFO] Notifying players about update with $update_notice_minutes minute notice"
      notify_players_of_update $update_notice_minutes

      echo "[INFO] Countdown completed. Stopping server for update..."
      shutdown_server_for_update || return 1

      echo "[INFO] Server shutdown confirmed. Update will be applied during container startup."

      if [ "$LOCK_HELD" = true ]; then
        release_update_lock
        LOCK_HELD=false
      fi

      trigger_container_restart "UPDATE_RESTART" "$current_build_id"
    fi
  else
    echo "[INFO] Server is already running the latest build ID: $current_build_id; no update needed."

    if [ "$LOCK_HELD" = true ]; then
      release_update_lock
      LOCK_HELD=false
    fi
  fi
  echo "[INFO] Update check completed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
