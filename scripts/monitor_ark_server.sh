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
  
  # Extra check: See if the server process actually disappeared temporarily but came back
  # This prevents unnecessary restarts of healthy servers
  sleep 5
  if is_process_running; then
    echo "[$current_time] Server process found running on second check. No recovery needed." | tee -a "$RECOVERY_LOG"
    return 0
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
  
  # Check for Wine or Proton processes that could indicate the server is still starting up
  if [ "$server_running" = "false" ]; then
    if pgrep -f "wine" >/dev/null 2>&1; then
      echo "[$current_time] Wine/Proton processes found, server might still be initializing" | tee -a "$RECOVERY_LOG"
      # Wait a bit more to see if server processes appear
      sleep 30
      
      # Check again after waiting
      if pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 || pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
        echo "[$current_time] Server processes appeared after waiting" | tee -a "$RECOVERY_LOG"
        server_running=true
      else
        echo "[$current_time] No server processes appeared after waiting 30 seconds" | tee -a "$RECOVERY_LOG"
      fi
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

# Function to check if the server is running
is_process_running() {
  local display_message=${1:-false} # Default to not displaying the message

  # First check PID file
  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE")
    
    # Check if the process with this PID is running
    if ps -p $pid >/dev/null 2>&1; then
      # Verify that this PID is actually an ARK server process
      if ps -p $pid -o cmd= | grep -q -E "ArkAscendedServer.exe|AsaApiLoader.exe"; then
        if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
          echo "ARK server process (PID: $pid) is running."
        fi
        return 0
      else
        # PID exists but it's not an ARK server process - stale PID file
        if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
          echo "PID file contains process ID $pid which is not an ARK server process."
        fi
      fi
    fi
  fi
  
  # If we got here, either PID file doesn't exist or PID is not valid
  # Try to find ARK server processes directly
  
  # First look for AsaApiLoader.exe if API=TRUE
  if [ "${API}" = "TRUE" ]; then
    local api_pid=$(pgrep -f "AsaApiLoader.exe" | head -1)
    if [ -n "$api_pid" ]; then
      if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "AsaApiLoader process found with PID: $api_pid. Updating PID file."
      fi
      echo "$api_pid" > "$PID_FILE"
      return 0
    fi
  fi
  
  # Then look for the main server executable
  local server_pid=$(pgrep -f "ArkAscendedServer.exe" | head -1)
  if [ -n "$server_pid" ]; then
    if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
      echo "ArkAscendedServer process found with PID: $server_pid. Updating PID file."
    fi
    echo "$server_pid" > "$PID_FILE"
    return 0
  fi
  
  # If we get here, no server process was found
  if [ "$display_message" = "true" ]; then
    echo "No ARK server processes found running."
  fi
  
  # Clean up stale PID file if it exists
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi
  
  return 1
}

# Function to check if this is a first-launch Wine/MSVCP140.dll error
check_for_first_launch_error() {
  local log_file="/home/pok/logs/server_console.log"
  local server_log="${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
  local wine_log_file="/home/pok/logs/wine_launch.log"
  
  # Check if first-launch has already been attempted and completed successfully
  if [ -f "/home/pok/.first_launch_completed" ]; then
    return 1
  fi
  
  # Check for the specific flag files created by launch_ASA.sh
  if [ -f "/home/pok/.first_launch_msvcp140_error" ]; then
    echo ""
    echo "========================================================================="
    echo "⚠️ DETECTED FIRST-LAUNCH MSVCP140.DLL ERROR"
    echo "-------------------------------------------------------------------------"
    echo "This is a NORMAL and EXPECTED issue during the first launch when using API"
    echo "mode. The Windows/Wine environment needs additional initialization that"
    echo "can only be completed after a restart."
    echo ""
    echo "The server will now automatically restart to resolve this issue."
    echo "This process will ONLY happen once during the initial setup."
    echo "========================================================================="
    echo ""
    return 0
  fi
  
  if [ -f "/home/pok/.first_launch_error" ]; then
    echo ""
    echo "========================================================================="
    echo "⚠️ DETECTED FIRST-LAUNCH ERROR"
    echo "-------------------------------------------------------------------------"
    echo "A general first-launch error was detected. This is normal behavior"
    echo "for the first run of ARK with API mode enabled."
    echo ""
    echo "The server will now automatically restart to resolve this issue."
    echo "This process will ONLY happen once during the initial setup."
    echo "========================================================================="
    echo ""
    return 0
  fi
  
  # Check wine log for MSVCP140.dll errors
  if [ -f "$wine_log_file" ] && grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" "$wine_log_file"; then
    echo ""
    echo "========================================================================="
    echo "⚠️ DETECTED MSVCP140.DLL LOADING ERROR IN WINE LOG"
    echo "-------------------------------------------------------------------------"
    echo "This is a common issue during first launch with API enabled. The Wine"
    echo "environment needs to initialize Visual C++ libraries."
    echo ""
    echo "The server will now automatically restart to resolve this issue."
    echo "Subsequent launches will be much faster after this one-time setup."
    echo "========================================================================="
    echo ""
    return 0
  fi
  
  # Check for the specific Wine/MSVCP140.dll error pattern in server console logs
  if [ -f "$log_file" ] && grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" "$log_file"; then
    echo ""
    echo "========================================================================="
    echo "⚠️ DETECTED MSVCP140.DLL LOADING ERROR IN CONSOLE LOG"
    echo "-------------------------------------------------------------------------"
    echo "This error commonly occurs during the first launch with API mode enabled."
    echo "It's related to the Visual C++ initialization process in Wine."
    echo ""
    echo "The server will automatically restart to complete the initialization."
    echo "This is a ONE-TIME process that ensures stable operation going forward."
    echo "========================================================================="
    echo ""
    return 0
  fi
  
  # Check if AsaApiLoader.exe crashed without creating logs
  if [ "${API}" = "TRUE" ] && [ ! -f "$server_log" ] && [ ! -d "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" ]; then
    # If server process is not running and no logs were created after 5 minutes from start
    local container_uptime=$(awk '{print int($1)}' /proc/uptime)
    if [ $container_uptime -gt 300 ] && ! is_process_running; then
      echo ""
      echo "========================================================================="
      echo "⚠️ POTENTIAL FIRST-LAUNCH FAILURE DETECTED"
      echo "-------------------------------------------------------------------------"
      echo "The server seems to have failed without creating log files. This can"
      echo "happen during the first launch with API mode when the Windows/Wine"
      echo "environment is still initializing."
      echo ""
      echo "The server will automatically restart to attempt recovery."
      echo "This is normal behavior and will typically resolve after one restart."
      echo "========================================================================="
      echo ""
      return 0
    fi
  fi
  
  return 1
}

# Function to handle first launch error recovery
handle_first_launch_recovery() {
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  echo "┃                AUTOMATIC FIRST-LAUNCH RECOVERY                    ┃"
  echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
  echo "┃ A common first-launch error was detected with the                 ┃"
  echo "┃ Windows/Wine environment and missing MSVCP140.dll.                ┃"
  echo "┃                                                                   ┃"
  echo "┃ ✅ This is EXPECTED during first run with API mode                ┃"
  echo "┃ ✅ The system will AUTOMATICALLY fix this issue                   ┃"
  echo "┃ ✅ This ONE-TIME process only happens on first launch             ┃"
  echo "┃ ✅ Second launch will be MUCH FASTER and stable                   ┃"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
  echo ""
  echo "🔄 Performing first-launch recovery procedure..."
  
  # Create a flag to indicate we've handled the first launch issue
  touch "/home/pok/.first_launch_completed"
  
  # Special log for first-launch recovery
  echo "$(date) - Performing automatic first-launch recovery due to MSVCP140.dll/Wine issues" > /home/pok/first_launch_recovery.log
  
  # Clean up error flag files
  rm -f "/home/pok/.first_launch_msvcp140_error" 2>/dev/null || true
  rm -f "/home/pok/.first_launch_error" 2>/dev/null || true
  
  # Terminate any running processes
  echo "⏳ Stopping any running server processes..."
  pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
  pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
  pkill -9 -f "wine" >/dev/null 2>&1 || true
  pkill -9 -f "wineserver" >/dev/null 2>&1 || true
  
  # Clean up the Wine prefix to force re-initialization
  echo "⏳ Cleaning up Wine/Proton environment..."
  rm -f "/home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg.bak" 2>/dev/null || true
  
  # Create the restart flag
  echo "API_RESTART" > /home/pok/restart_reason.flag
  
  # Remove the PID file if it exists
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi
  
  # Allow monitor process to continue (don't exit the container)
  echo "⏳ Requesting server restart..."
  echo "true" > "/home/pok/.first_launch_restart_requested"
  
  # Now restart the server using restart_server.sh
  if [ -x "/home/pok/scripts/restart_server.sh" ]; then
    echo "⏳ Running restart script with immediate parameter..."
    /home/pok/scripts/restart_server.sh immediate
  else
    echo "WARNING: restart_server.sh not found or not executable"
    # Fallback to direct server launch
    nohup /home/pok/scripts/init.sh --from-restart > /home/pok/logs/restart_console.log 2>&1 &
  fi
  
  # Sleep to give restart time to initialize
  sleep 30
  
  echo "✅ First-launch recovery completed. Server should restart automatically."
  echo "🚀 The server should be much faster and more stable after this restart."
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
  
  # NEW: Check for first-launch error and handle recovery if needed
  if check_for_first_launch_error; then
    handle_first_launch_recovery
    # After recovery attempt, sleep for a bit to let the server restart
    sleep 60
    continue
  fi
  
  # Check for first-launch restart in progress
  if [ -f "/home/pok/.first_launch_restart_requested" ] && [ ! -f "/home/pok/.first_launch_restart_completed" ]; then
    echo "First-launch restart in progress, monitoring..."
    
    # Check if server is now running after the restart
    if is_process_running; then
      echo "Server is now running after first-launch restart. Recovery was successful."
      touch "/home/pok/.first_launch_restart_completed"
      rm -f "/home/pok/.first_launch_restart_requested"
    fi
    
    # Don't do other checks while in this recovery mode
    sleep 30
    continue
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