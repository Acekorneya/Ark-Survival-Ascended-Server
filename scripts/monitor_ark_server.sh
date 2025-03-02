#!/bin/bash
source /home/pok/scripts/rcon_commands.sh
source /home/pok/scripts/common.sh

NO_RESTART_FLAG="/home/pok/shutdown.flag"
INITIAL_STARTUP_DELAY=120  # Delay in seconds before starting the monitoring
lock_file="$ASA_DIR/updating.flag"
RECOVERY_LOG="/home/pok/server_recovery.log"

# Restart update window
RESTART_NOTICE_MINUTES=${RESTART_NOTICE_MINUTES:-30}  # Default to 30 minutes if not set
UPDATE_WINDOW_MINIMUM_TIME=${UPDATE_WINDOW_MINIMUM_TIME:-12:00 AM} # Default to "12:00 AM" if not set
UPDATE_WINDOW_MAXIMUM_TIME=${UPDATE_WINDOW_MAXIMUM_TIME:-11:59 PM} # Default to "11:59 PM" if not set

# Enhanced recovery function with better logging and recovery 
recover_server() {
  local current_time=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$current_time] Initiating server recovery procedure..." | tee -a "$RECOVERY_LOG"
  
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
  
  # Server is not running, check for Wine/Proton processes that might be stuck
  if pgrep -f "wine" >/dev/null 2>&1 || pgrep -f "wineserver" >/dev/null 2>&1; then
    echo "[$current_time] Found stuck Wine/Proton processes. Cleaning up..." | tee -a "$RECOVERY_LOG"
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    sleep 3
  fi
  
  # Check for Xvfb and clean it up
  if pgrep -f "Xvfb" >/dev/null 2>&1; then
    echo "[$current_time] Found Xvfb processes. Cleaning up..." | tee -a "$RECOVERY_LOG"
    pkill -9 -f "Xvfb" >/dev/null 2>&1 || true
    sleep 2
  fi
  
  # Clean up X11 sockets
  if [ -d "/tmp/.X11-unix" ]; then
    echo "[$current_time] Cleaning up X11 sockets..." | tee -a "$RECOVERY_LOG"
    rm -rf /tmp/.X11-unix/* 2>/dev/null || true
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
  fi
  
  # Remove PID file if it exists
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi
  
  # Attempt server restart
  echo "[$current_time] Attempting server restart..." | tee -a "$RECOVERY_LOG"
  
  # For API mode, need extra care
  if [ "${API}" = "TRUE" ]; then
    echo "[$current_time] API mode requires special handling. Verifying environment..." | tee -a "$RECOVERY_LOG"
    # Run the environment verification like init.sh does
    export DISPLAY=:0.0
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
    export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
    export WINEDLLOVERRIDES="version=n,b"
    
    # Set up Xvfb again
    Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
    sleep 2
  fi
  
  # Use screen to launch the server with log visibility
  # Attempt to use screen if available, otherwise fall back to basic method
  SCREEN_AVAILABLE=false
  if command -v screen >/dev/null 2>&1; then
    SCREEN_AVAILABLE=true
  else
    # Try to install screen but don't fail if it doesn't work
    echo "[$current_time] Attempting to install screen for better log visibility (optional)..." | tee -a "$RECOVERY_LOG"
    apt-get update -qq && apt-get install -y screen >/dev/null 2>&1
    # Check if installation succeeded
    if command -v screen >/dev/null 2>&1; then
      SCREEN_AVAILABLE=true
      echo "[$current_time] ✅ Screen installed successfully!" | tee -a "$RECOVERY_LOG"
    else
      echo "[$current_time] ⚠️ Screen installation failed. Will use fallback method instead." | tee -a "$RECOVERY_LOG"
    fi
  fi
  
  # Launch the server differently based on whether screen is available
  echo "[$current_time] Launching server via init.sh..." | tee -a "$RECOVERY_LOG"
  mkdir -p /home/pok/logs
  
  if [ "$SCREEN_AVAILABLE" = true ]; then
    # Launch using screen to maintain log visibility
    screen -dmS ark_recovery bash -c "/home/pok/scripts/init.sh 2>&1 | tee -a /home/pok/recovery_launch.log; exec bash"
    echo "[$current_time] Server launched in screen session. View logs with: screen -r ark_recovery" | tee -a "$RECOVERY_LOG"
  else
    # Fallback method - use nohup to run in background
    nohup /home/pok/scripts/init.sh > /home/pok/logs/recovery_console.log 2>&1 &
    echo "[$current_time] Server launched with fallback method. View logs with: tail -f /home/pok/logs/recovery_console.log" | tee -a "$RECOVERY_LOG"
    echo "[$current_time] For detailed server logs once started: tail -f /home/pok/logs/server_console.log" | tee -a "$RECOVERY_LOG"
  fi
  
  # Wait for the restart to take effect
  sleep 20
  
  # Check if server came up
  if is_process_running "true"; then
    if [ "$SCREEN_AVAILABLE" = true ]; then
      echo "[$current_time] Server successfully restarted! Use 'screen -r ark_recovery' to view logs." | tee -a "$RECOVERY_LOG"
    else
      echo "[$current_time] Server successfully restarted! View logs with: tail -f /home/pok/logs/server_console.log" | tee -a "$RECOVERY_LOG"
    fi
    return 0
  else
    echo "[$current_time] Server restart failed! Check logs for details." | tee -a "$RECOVERY_LOG"
    return 1
  fi
}

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