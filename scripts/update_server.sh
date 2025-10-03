#!/bin/bash
source /home/pok/scripts/common.sh
source /home/pok/scripts/rcon_commands.sh
# Get the current build ID at the start to ensure it's defined for later use
current_build_id=$(get_current_build_id)
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

# Set up trap to call cleanup on exit (including normal exit, crashes, and signals)
trap cleanup EXIT INT TERM

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
  
  # Send RCON commands to save world and shut down the server
  echo "[INFO] Sending SaveWorld command to server..."
  if send_rcon_command "SaveWorld"; then
    echo "[SUCCESS] World save command sent. Waiting for completion..."
    # Allow time for the save to complete
    sleep 10
    
    # Now send the exit command to properly shut down the server
    echo "[INFO] Sending DoExit command to server..."
    send_rcon_command "DoExit"
    echo "[INFO] DoExit command sent. Waiting for server to shut down..."
    
    # Wait for server process to exit
    local timeout=60
    local elapsed=0
    local is_server_down=false
    
    echo "[INFO] Waiting for server to shut down (timeout: $timeout seconds)..."
    while [ $elapsed -lt $timeout ]; do
      # Check if server processes are still running
      if ! pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1 && ! pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1; then
        echo "[SUCCESS] Server has shut down properly."
        is_server_down=true
        break
      fi
      
      # Wait and increment counter
      sleep 5
      elapsed=$((elapsed + 5))
      echo "[INFO] Still waiting for server shutdown... ($elapsed/$timeout seconds)"
    done
    
    # If server didn't shut down gracefully, force kill it
    if [ "$is_server_down" != "true" ]; then
      echo "[WARNING] Server didn't shut down gracefully within timeout. Force killing processes..."
      pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
      pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
      pkill -9 -f "wine" >/dev/null 2>&1 || true
      pkill -9 -f "wineserver" >/dev/null 2>&1 || true
      sleep 2
    fi
  else
    echo "[WARNING] Failed to send SaveWorld command. Server might not be running or RCON might be unavailable."
    echo "[INFO] Will attempt to force stop any running server processes..."
    pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
    pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    sleep 2
  fi
  
  echo "[INFO] Server processes stopped. Ready for staging update"
}

trigger_container_restart() {
  local reason="${1:-UPDATE_RESTART}"
  local expected_build="${2:-$current_build_id}"

  echo "$(date) - Container exiting for automatic restart due to update" > /home/pok/container_update_restart.log
  echo "$reason" > /home/pok/restart_reason.flag

  if [ -n "$expected_build" ]; then
    echo "$expected_build" > /home/pok/expected_build_id.txt
  fi

  echo "true" > /home/pok/stop_monitor.flag

  echo "🔄 Container will now exit for restart via Docker"
  echo "⚠️ Docker will automatically restart the container"

  sync
  sleep 1
  kill -9 1
  exit 1
}

# Main update logic
echo "[INFO] Checking for ARK server updates..."

# First check for and remove any stale lock files
remove_stale_lock

# Check if update is needed using the enhanced function
if server_needs_update; then
  echo "[INFO] Server update/restart required: Current build ID: $current_build_id, Installed build ID: $(get_build_id_from_acf)"
  
  # Check if this is just a dirty flag restart (no actual update needed)
  if has_dirty_flag; then
    echo "[INFO] This instance needs restart due to server files updated by another instance"
    echo "[INFO] No download required - just restarting to load updated files"
    
    # Clear the dirty flag since we're handling it
    clear_dirty_flag
    
    # Notify players about the restart 
    # Use user's configured restart notice time, default to 5 minutes if not set
    dirty_restart_notice=${RESTART_NOTICE_MINUTES:-5}
    echo "[INFO] Notifying players about restart (dirty flag) with $dirty_restart_notice minute notice"
    notify_players_of_update $dirty_restart_notice
    
    echo "[INFO] Countdown completed. Preparing server for restart..."
    shutdown_server_for_update
    trigger_container_restart "DIRTY_RESTART" "$current_build_id"
  else
    # This is an actual update that requires downloading
    echo "[INFO] Actual server update required - will download new files"
    
    # Attempt to acquire the update lock using common.sh function
    if ! acquire_update_lock; then
      echo "[WARNING] Another instance is currently updating. Waiting for update to complete..."
      
      # Wait for the update to complete
      if wait_for_update_lock; then
        echo "[INFO] Update completed by another instance. Checking if server restart is still needed..."
        
        # Check if the server is now up to date
        if ! server_needs_update; then
          echo "[INFO] Server is now up to date. No restart needed."
          exit 0
        else
          echo "[WARNING] Server is still not up to date after waiting. Will attempt update again."
          if ! acquire_update_lock; then
            echo "[ERROR] Unable to acquire update lock after peer completed update"
            exit 1
          fi
        fi
      else
        echo "[ERROR] Timed out waiting for update lock. Aborting update."
        exit 1
      fi
    fi

    # We now have the update lock and need to perform actual update
    LOCK_HELD=true
    echo "[INFO] Acquired update lock. Performing server files update..."

    # Notify players about the upcoming update and initiate countdown
    update_notice_minutes=${RESTART_NOTICE_MINUTES:-30}
    echo "[INFO] Notifying players about update with $update_notice_minutes minute notice"
    notify_players_of_update $update_notice_minutes

    echo "[INFO] Countdown completed. Stopping server for update..."
    shutdown_server_for_update

    TEMP_DOWNLOAD_DIR=$(create_temp_download_dir)
    if [ -z "$TEMP_DOWNLOAD_DIR" ]; then
      echo "[ERROR] Failed to create temporary download directory"
      exit 1
    fi

    echo "[INFO] Temporary download directory created at $TEMP_DOWNLOAD_DIR"

    if ! perform_staged_server_download "$TEMP_DOWNLOAD_DIR"; then
      echo "[ERROR] Failed to download and stage server update"
      exit 1
    fi

    echo "[INFO] Server files updated successfully. Marking other instances as dirty..."
    mark_other_instances_dirty

    # Refresh current build information for logging and restart expectations
    installed_build=$(get_build_id_from_acf)
    if [ -n "$installed_build" ]; then
      echo "[INFO] Installed build after update: $installed_build"
      current_build_id="$installed_build"
    fi

    # Manual cleanup of temp directory before restart
    if [ -n "$TEMP_DOWNLOAD_DIR" ] && [ -d "$TEMP_DOWNLOAD_DIR" ]; then
      rm -rf "$TEMP_DOWNLOAD_DIR"
      TEMP_DOWNLOAD_DIR=""
    fi

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
