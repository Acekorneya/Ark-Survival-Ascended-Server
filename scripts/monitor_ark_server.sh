#!/bin/bash
source /home/pok/scripts/rcon_commands.sh
source /home/pok/scripts/common.sh

NO_RESTART_FLAG="/home/pok/shutdown.flag"
INITIAL_STARTUP_DELAY=120  # Delay in seconds before starting the monitoring
lock_file="$ASA_DIR/updating.flag"

# Restart update window
RESTART_NOTICE_MINUTES=${RESTART_NOTICE_MINUTES:-30}  # Default to 30 minutes if not set
UPDATE_WINDOW_MINIMUM_TIME=${UPDATE_WINDOW_MINIMUM_TIME:-12:00 AM} # Default to "12:00 AM" if not set
UPDATE_WINDOW_MAXIMUM_TIME=${UPDATE_WINDOW_MAXIMUM_TIME:-11:59 PM} # Default to "11:59 PM" if not set

# Wait for the initial startup before monitoring
sleep $INITIAL_STARTUP_DELAY

# Monitoring loop
while true; do
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
      if /home/pok/scripts/POK_Update_Monitor.sh; then
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
    # Double-check by looking for the server process with ps before restarting
    local server_process_count=$(ps aux | grep -v grep | grep -c "ArkAscendedServer.exe\|AsaApiLoader.exe")
    if [ "$server_process_count" -eq 0 ]; then
      echo "Detected server is not running (confirmed via process check), attempting immediate restart..."
      /home/pok/scripts/restart_server.sh immediate
    else
      echo "Process check suggests server is running but PID file may be missing. Skipping restart."
      # Try to recover the PID
      local detected_pid=$(ps aux | grep -v grep | grep "ArkAscendedServer.exe\|AsaApiLoader.exe" | awk '{print $2}' | head -1)
      if [ -n "$detected_pid" ]; then
        echo "Found server process with PID: $detected_pid. Updating PID file."
        echo "$detected_pid" > "$PID_FILE"
      fi
    fi
  fi

  sleep 30 # Short sleep to prevent high CPU usage
done