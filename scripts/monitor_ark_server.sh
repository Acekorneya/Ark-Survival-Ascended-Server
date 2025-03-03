#!/bin/bash
source /home/pok/scripts/rcon_commands.sh
source /home/pok/scripts/common.sh
source /home/pok/scripts/shutdown_server.sh

NO_RESTART_FLAG="/home/pok/shutdown.flag"
RESTART_FLAG="/home/pok/restart.flag"
SHUTDOWN_COMPLETE_FLAG="/home/pok/shutdown_complete.flag"
INITIAL_STARTUP_DELAY=120  # Delay in seconds before starting the monitoring
lock_file="$ASA_DIR/updating.flag"
RECOVERY_LOG="/home/pok/server_recovery.log"
EXIT_ON_API_RESTART="${EXIT_ON_API_RESTART:-TRUE}" # Default to TRUE - controls container exit behavior

# Restart update window
RESTART_NOTICE_MINUTES=${RESTART_NOTICE_MINUTES:-30}  # Default to 30 minutes if not set
UPDATE_WINDOW_MINIMUM_TIME=${UPDATE_WINDOW_MINIMUM_TIME:-12:00 AM} # Default to "12:00 AM" if not set
UPDATE_WINDOW_MAXIMUM_TIME=${UPDATE_WINDOW_MAXIMUM_TIME:-11:59 PM} # Default to "11:59 PM" if not set

# Function to restart container for API mode
exit_container_for_recovery() {
  local current_time=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$current_time] 🔄 Using container exit/restart strategy for API mode recovery..." | tee -a "$RECOVERY_LOG"
  
  # Create a flag file to indicate a clean exit for restart
  echo "$(date) - Container exiting for automatic restart/recovery by orchestration system" > /home/pok/container_recovery.log
  
  # Create a flag file that will be detected on container restart
  echo "API_RESTART" > /home/pok/restart_reason.flag
  
  echo "[$current_time] ⚠️ Container will now exit with code 0 for orchestration system to restart it" | tee -a "$RECOVERY_LOG"
  echo "[$current_time] 📝 If container does not restart automatically, please restart it manually" | tee -a "$RECOVERY_LOG"
  
  # Before exiting, ensure world save is complete
  # Use safe_container_stop function to ensure world save
  echo "[$current_time] 💾 Ensuring world data is saved before container exit..." | tee -a "$RECOVERY_LOG"
  safe_container_stop
  
  # Kill any running server processes first
  if pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 || pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
    echo "[$current_time] Terminating any running server processes before exit..." | tee -a "$RECOVERY_LOG"
    pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
    pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    sleep 2
  fi
  
  # Make sure any existing shutdown flag is removed so a fresh restart can occur
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "[$current_time] Removing existing shutdown complete flag..." | tee -a "$RECOVERY_LOG"
    rm -f "$SHUTDOWN_COMPLETE_FLAG"
  fi
  
  # Allow some time for logs to be written
  sleep 3
  
  # Exit the container with success code (0) which should trigger restart by orchestration
  exit 0
}

# Enhanced recovery function with better logging and recovery 
recover_server() {
  local current_time=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$current_time] Initiating server recovery procedure..." | tee -a "$RECOVERY_LOG"
  
  # Before recovery, ensure any ongoing shutdown completes
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "[$current_time] Found shutdown complete flag. Waiting for shutdown to complete..." | tee -a "$RECOVERY_LOG"
    sleep 10
    rm -f "$SHUTDOWN_COMPLETE_FLAG"
  fi
  
  # For API mode, use the container exit/restart strategy if enabled
  if [ "${API}" = "TRUE" ] && [ "${EXIT_ON_API_RESTART}" = "TRUE" ]; then
    echo "[$current_time] API mode recovery - using container restart strategy..." | tee -a "$RECOVERY_LOG"
    exit_container_for_recovery
    # This function will not return as it exits the container
  fi
  
  # Double-check server status with a more thorough approach
  local server_running=false
  
  # Check for AsaApi processes first if in API mode
  if [ "${API}" = "TRUE" ]; then
    if pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1; then
      local api_pid=$(pgrep -f "AsaApiLoader.exe" | head -1)
      echo "[$current_time] AsaApi server is running (PID: $api_pid)" | tee -a "$RECOVERY_LOG"
      echo "$api_pid" > "$PID_FILE"
      server_running=true
    fi
  fi
  
  # Check for main server process if API didn't find anything
  if [ "$server_running" = "false" ]; then
    if pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
      local server_pid=$(pgrep -f "ArkAscendedServer.exe" | head -1)
      echo "[$current_time] ARK server is running (PID: $server_pid)" | tee -a "$RECOVERY_LOG"
      echo "$server_pid" > "$PID_FILE"
      server_running=true
    fi
  fi
  
  # If server is running, we're done
  if [ "$server_running" = "true" ]; then
    echo "[$current_time] Server processes are running, recovery not needed" | tee -a "$RECOVERY_LOG"
    return 0
  fi
  
  # Make sure any existing shutdown flag is removed for a clean restart
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "[$current_time] Removing existing shutdown complete flag before recovery..." | tee -a "$RECOVERY_LOG"
    rm -f "$SHUTDOWN_COMPLETE_FLAG"
  fi
  
  # Server is not running, using restart_server.sh for recovery
  echo "[$current_time] Server is not running, using restart_server.sh for recovery..." | tee -a "$RECOVERY_LOG"
  
  # Use restart_server.sh for consistency - with "immediate" parameter for instant restart
  echo "[$current_time] Running restart_server.sh immediate..." | tee -a "$RECOVERY_LOG"
  /home/pok/scripts/restart_server.sh immediate
  
  # Return success, as we've delegated the restart to restart_server.sh
  echo "[$current_time] Restart command issued via restart_server.sh" | tee -a "$RECOVERY_LOG"
  return 0
}

# Wait for the initial startup before monitoring
sleep $INITIAL_STARTUP_DELAY

# Monitoring loop
while true; do
  # Check if there's an active shutdown in progress
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "Server shutdown/restart in progress, waiting before continuing monitoring..."
    sleep 30
    continue
  fi

  # Check for stale update flags (older than 6 hours) 
  # This prevents server from being stuck in "updating" mode if an update was interrupted
  if [ -f "$lock_file" ]; then
    # Use the enhanced lock checking mechanism
    lock_status=$(check_lock_status)
    status_code=$?
    
    if [ $status_code -eq 1 ]; then
      # Lock seems stale, try to clear it
      echo "Stale update lock detected. Details:"
      echo "$lock_status"
      echo "Attempting to clear stale update flag..."
      
      if check_stale_update_flag 6; then
        # Stale flag was detected and cleared, continue with normal monitoring
        echo "Stale update flag was cleared. Continuing with normal monitoring."
      else
        # Flag might not be stale enough yet for automatic clearing
        echo "Update flag not cleared automatically. It may still be valid or not old enough."
        echo "If you believe this is stuck, manually clear it with: ./POK-manager.sh -clearupdateflag <instance_name>"
      fi
    elif [ $status_code -eq 0 ]; then
      # Lock is valid
      echo "Update/Installation in progress. Please wait for it to complete..."
      echo "Update details: "
      echo "$lock_status"
      sleep 15
      continue
    fi
  fi
  
  if [ "${UPDATE_SERVER}" = "TRUE" ]; then
    # Check for updates at the interval specified by CHECK_FOR_UPDATE_INTERVAL
    current_time=$(date +%s)
    last_update_check_time=${last_update_check_time:-0}
    update_check_interval_seconds=$((CHECK_FOR_UPDATE_INTERVAL * 3600))

    # Put constraints around the update check interval to prevent it from running outside of desired time windows
    update_window_lower_bound=$(date -d "${UPDATE_WINDOW_MINIMUM_TIME}" +%s)
    update_window_upper_bound=$(date -d "${UPDATE_WINDOW_MAXIMUM_TIME}" +%s)

    if ((current_time - last_update_check_time > update_check_interval_seconds)) && ((current_time >= update_window_lower_bound && current_time <= update_window_upper_bound)); then
      # Make sure any stale shutdown flags are cleared before update check
      if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
        echo "Removing stale shutdown complete flag before update check..."
        rm -f "$SHUTDOWN_COMPLETE_FLAG"
      fi
      
      if /home/pok/scripts/POK_Update_Monitor.sh; then
        # Set restart mode flag for proper messaging during restart
        export API_CONTAINER_RESTART="TRUE"
        /home/pok/scripts/restart_server.sh $RESTART_NOTICE_MINUTES
      fi
      last_update_check_time=$current_time
    fi
  fi
  # Check if the no_restart flag is present before checking the server running state
  if [ -f "$NO_RESTART_FLAG" ]; then
    echo "Shutdown flag is present, skipping server status check and potential restart..."
    sleep 30 # Adjust sleep as needed
    continue # Skip the rest of this loop iteration, avoiding the server running state check and restart
  fi

  # Restart the server if it's not running and not currently updating
  if ! is_process_running && ! is_server_updating; then
    echo "Detected server is not running, performing thorough process check before restarting..."
    
    # Use the enhanced recovery function instead of simple restart
    recover_server
    
    # Sleep a bit after recovery attempt to avoid rapid restart loops
    sleep 60
  else
    # Server is running normally, just do regular short sleep
    sleep 30 # Short sleep to prevent high CPU usage
  fi
done