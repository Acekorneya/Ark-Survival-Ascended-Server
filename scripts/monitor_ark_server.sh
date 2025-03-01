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
    check_stale_update_flag 6
    if [ $? -eq 0 ]; then
      # Stale flag was detected and cleared, continue with normal monitoring
      echo "Stale update flag was cleared. Continuing with normal monitoring."
    else
      # Update is still in progress or flag is not stale yet
      echo "Update/Installation in progress. Please wait for it to complete..."
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
    echo "Detected server is not running, attempting immediate restart..."
    /home/pok/scripts/restart_server.sh immediate
  fi

  sleep 30 # Short sleep to prevent high CPU usage
done