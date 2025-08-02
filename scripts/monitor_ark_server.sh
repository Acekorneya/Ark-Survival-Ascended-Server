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
RESTART_TIMESTAMP_FILE="/tmp/restart_timestamp"

# Note: RESTART_NOTICE_MINUTES is configured by user in docker-compose.yaml
UPDATE_WINDOW_MINIMUM_TIME=${UPDATE_WINDOW_MINIMUM_TIME:-12:00 AM} # Default to "12:00 AM" if not set
UPDATE_WINDOW_MAXIMUM_TIME=${UPDATE_WINDOW_MAXIMUM_TIME:-11:59 PM} # Default to "11:59 PM" if not set

# Check for restart timeout (nuclear option)
check_restart_timeout() {
  # If restart flag exists, check if we've been stuck for too long
  if [ -f "/home/pok/restart_reason.flag" ]; then
    # If timestamp file doesn't exist, create it with current time
    if [ ! -f "$RESTART_TIMESTAMP_FILE" ]; then
      TZ="${TZ}" date +%s > "$RESTART_TIMESTAMP_FILE"
      return 0
    fi
    
    # Otherwise, check how long it's been since the restart was initiated
    local start_time=$(cat "$RESTART_TIMESTAMP_FILE")
    local current_time=$(TZ="${TZ}" date +%s)
    local elapsed_time=$((current_time - start_time))
    
    # If it's been more than 5 minutes (300 seconds), force kill the container
    if [ $elapsed_time -gt 300 ]; then
      echo "[CRITICAL] Restart timeout exceeded (${elapsed_time}s) - FORCING CONTAINER KILL"
      
      # Absolutely ensure container dies
      echo "true" > /home/pok/stop_monitor.flag
      sync
      
      # Execute most aggressive kill sequence
      killall -9 -u pok || true
      sleep 1
      kill -9 -1 || true
      sleep 1
      kill -9 1 || true
      sleep 1
      kill -ABRT $$ || true
      exec kill -SEGV $$ || exit 1
    fi
  else
    # If no restart flag, remove the timestamp file if it exists
    if [ -f "$RESTART_TIMESTAMP_FILE" ]; then
      rm -f "$RESTART_TIMESTAMP_FILE"
    fi
  fi
  
  return 0
}

# Function to display monitor status with timestamp
display_monitor_status() {
  # Skip if display is disabled
  if [ "${DISPLAY_POK_MONITOR_MESSAGE}" != "TRUE" ]; then
    return 0
  fi
  
  # Get current timestamp using container timezone
  local timestamp=$(TZ="${TZ}" date "+%Y-%m-%d %H:%M:%S")
  
  # Store parameters in local variables to avoid interpretation issues
  local message="$1"
  local level="${2:-INFO}"
  local separator="${3:-false}"
  
  # Display a separator line if requested
  if [ "$separator" = "true" ]; then
    printf "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ UPDATE MONITOR ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
  fi
  
  # Format the message based on level - use printf for safer output
  case "$level" in
    "INFO")
      printf "┃ ℹ️ [%s] %s\n" "$timestamp" "$message"
      ;;
    "SUCCESS")
      printf "┃ ✅ [%s] %s\n" "$timestamp" "$message"
      ;;
    "WARNING")
      printf "┃ ⚠️ [%s] %s\n" "$timestamp" "$message"
      ;;
    "ERROR")
      printf "┃ ❌ [%s] %s\n" "$timestamp" "$message"
      ;;
    *)
      printf "┃ [%s] %s\n" "$timestamp" "$message"
      ;;
  esac
  
  # Close the separator if requested
  if [ "$separator" = "true" ]; then
    printf "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
  fi
}

# Function to convert the CHECK_FOR_UPDATE_INTERVAL to seconds
# Simplified: whole numbers (1-24) are hours, decimals (0.01-0.99) are interpreted as minutes
convert_interval_to_seconds() {
  # Only calculate the value, no display here
  local interval=${CHECK_FOR_UPDATE_INTERVAL:-1}
  local seconds
  
  # Check if the interval is a decimal (contains a dot)
  if [[ "$interval" == *.* ]]; then
    # Get the digits after the decimal point (these are now minutes)
    # Example: 0.05 -> extract 05 -> 5 minutes
    local minutes=$(echo "$interval" | cut -d. -f2)
    # Remove leading zeros (05 -> 5)
    minutes=$(echo "$minutes" | sed 's/^0*//')
    
    # If empty (in case it was just .0), default to 1 minute
    if [ -z "$minutes" ]; then
      minutes=1
    fi
    
    # Convert minutes to seconds (60 seconds per minute)
    seconds=$((minutes * 60))
    
    # Enforce minimum of 1 minute
    if [ $seconds -lt 60 ]; then
      seconds=60
    fi
  else
    # Whole number = hours, convert to seconds (3600 seconds per hour)
    # Ensure it's a valid number by removing any non-digits
    interval=$(echo "$interval" | tr -cd '0-9')
    if [ -z "$interval" ] || [ "$interval" -lt 1 ]; then
      interval=1
    fi
    seconds=$((interval * 3600))
  fi
  
  echo "$seconds"
}

# Stand-alone function to display interval information to the user
display_interval_info() {
  # Only run if display is enabled
  if [ "${DISPLAY_POK_MONITOR_MESSAGE}" != "TRUE" ]; then
    return
  fi
  
  local interval=${CHECK_FOR_UPDATE_INTERVAL:-1}
  local seconds
  local description
  
  # Calculate interval seconds using our conversion function
  seconds=$(convert_interval_to_seconds)
  
  # Format as hours or minutes for display
  if [ $seconds -ge 3600 ]; then
    local hours=$((seconds / 3600))
    if [ $hours -eq 1 ]; then
      description="$hours hour ($seconds seconds)"
    else
      description="$hours hours ($seconds seconds)"
    fi
  else
    local minutes=$((seconds / 60))
    if [ $minutes -eq 1 ]; then
      description="$minutes minute ($seconds seconds)"
    else
      description="$minutes minutes ($seconds seconds)"
    fi
  fi
  
  # Safely display
  display_monitor_status "🕒 Check interval: $description" "INFO"
}

# Function to restart container for API mode
exit_container_for_recovery() {
  local current_time=$(TZ="${TZ}" date "+%Y-%m-%d %H:%M:%S")
  echo "[$current_time] [INFO] Using container exit/restart strategy for recovery..." | tee -a "$RECOVERY_LOG"
  
  # Create a flag file to indicate a clean exit for restart
  echo "$(TZ="${TZ}" date) - Container exiting for automatic restart/recovery by orchestration system" > /home/pok/container_recovery.log
  
  # Create a flag file that will be detected on container restart
  echo "CONTAINER_RECOVERY" > /home/pok/restart_reason.flag
  
  echo "[$current_time] [WARNING] Container will now be killed to trigger Docker automatic restart" | tee -a "$RECOVERY_LOG"
  
  # First check if server processes are actually running before trying to save or send commands
  if pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 || pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
    # Use safe_container_stop function to ensure world save
    echo "[$current_time] [INFO] Server is running, ensuring world data is saved before container exit..." | tee -a "$RECOVERY_LOG"
    safe_container_stop
    
    # Kill any running server processes after safe stop
    echo "[$current_time] [INFO] Terminating any running server processes after save..." | tee -a "$RECOVERY_LOG"
    pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
    pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    sleep 2
  else
    echo "[$current_time] [INFO] Server not running, no world save needed" | tee -a "$RECOVERY_LOG"
  fi
  
  # Make sure any existing shutdown flag is removed so a fresh restart can occur
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "[$current_time] [INFO] Removing existing shutdown complete flag..." | tee -a "$RECOVERY_LOG"
    rm -f "$SHUTDOWN_COMPLETE_FLAG"
  fi
  
  # Create a special flag to tell other monitors to stop
  echo "true" > /home/pok/stop_monitor.flag
  
  # Flush any pending disk writes
  sync
  
  # Allow some time for logs to be written
  sleep 3
  
  echo "[$current_time] [INFO] Force killing ALL container processes..." | tee -a "$RECOVERY_LOG"
  
  # Super aggressive container kill approach:
  
  # 1. Kill all processes owned by our user
  echo "[$current_time] [INFO] Killing all user processes with SIGKILL..." | tee -a "$RECOVERY_LOG"
  killall -9 -u pok || true
  
  # 2. Kill all processes in our process group
  echo "[$current_time] [INFO] Killing all processes in process group with SIGKILL..." | tee -a "$RECOVERY_LOG"
  kill -9 -1 || true
  
  # 3. Force kill init process (tini)
  echo "[$current_time] [INFO] Directly killing PID 1 (tini) with SIGKILL..." | tee -a "$RECOVERY_LOG"
  kill -9 1 || true
  
  # 4. As absolute last resort, crash our own process with ABORT signal
  echo "[$current_time] [INFO] Last resort: Sending SIGABRT to our own process to force container crash..." | tee -a "$RECOVERY_LOG"
  kill -ABRT $$ || true
  
  # If we somehow get here, exit with failure code
  exit 1
}

# Enhanced recovery function with better logging and recovery 
recover_server() {
  local current_time=$(TZ="${TZ}" date "+%Y-%m-%d %H:%M:%S")
  echo "[$current_time] [INFO] Initiating server recovery procedure..." | tee -a "$RECOVERY_LOG"
  
  # Before recovery, ensure any ongoing shutdown completes
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "[$current_time] [INFO] Found shutdown complete flag. Waiting for shutdown to complete..." | tee -a "$RECOVERY_LOG"
    sleep 10
    rm -f "$SHUTDOWN_COMPLETE_FLAG"
  fi
  
  # Extra check: See if the server process actually disappeared temporarily but came back
  # This prevents unnecessary restarts of healthy servers
  sleep 5
  if is_process_running; then
    echo "[$current_time] [SUCCESS] Server process found running on second check. No recovery needed." | tee -a "$RECOVERY_LOG"
    return 0
  fi
  
  # Clean up any stale flags that might interfere with restart
  echo "[$current_time] [INFO] Cleaning up any stale flags or files before container restart..." | tee -a "$RECOVERY_LOG"
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi
  
  if [ -f "$ASA_DIR/updating.flag" ]; then
    rm -f "$ASA_DIR/updating.flag"
  fi
  
  if [ -f "/tmp/restart_in_progress" ]; then
    rm -f "/tmp/restart_in_progress"
  fi
  
  # Make sure any existing shutdown flag is removed for a clean restart
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "[$current_time] [INFO] Removing existing shutdown complete flag before recovery..." | tee -a "$RECOVERY_LOG"
    rm -f "$SHUTDOWN_COMPLETE_FLAG"
  fi
  
  # Create a flag to ensure all monitors stop
  echo "true" > /home/pok/stop_monitor.flag
  
  # Use container exit/restart strategy for all modes
  echo "[$current_time] [INFO] Server not running - using container restart strategy for clean recovery..." | tee -a "$RECOVERY_LOG"
  
  # Exit the container to trigger Docker restart
  exit_container_for_recovery
  # This function will not return as it exits the container
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
          echo "[INFO] ARK server process (PID: $pid) is running."
        fi
        return 0
      else
        # PID exists but it's not an ARK server process - stale PID file
        if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
          echo "[WARNING] PID file contains process ID $pid which is not an ARK server process."
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
        echo "[INFO] AsaApiLoader process found with PID: $api_pid. Updating PID file."
      fi
      echo "$api_pid" > "$PID_FILE"
      return 0
    fi
  fi
  
  # Then look for the main server executable
  local server_pid=$(pgrep -f "ArkAscendedServer.exe" | head -1)
  if [ -n "$server_pid" ]; then
    if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
      echo "[INFO] ArkAscendedServer process found with PID: $server_pid. Updating PID file."
    fi
    echo "$server_pid" > "$PID_FILE"
    return 0
  fi
  
  # If we get here, no server process was found
  if [ "$display_message" = "true" ]; then
    echo "[WARNING] No ARK server processes found running."
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
  
  # Check multiple locations for first-launch completion markers
  # First check the new persistent config location
  local config_dir="${ASA_DIR}/ShooterGame/Saved/Config/FirstLaunchFlags"
  local api_first_launch_file="${config_dir}/api_first_launch_completed"
  local standard_first_launch_file="${config_dir}/standard_first_launch_completed"
  
  # If we find a marker in any location, consider first launch completed
  if [ -f "/home/pok/.first_launch_completed" ] || \
     ([ "${API}" = "TRUE" ] && [ -f "$api_first_launch_file" ]) || \
     ([ "${API}" != "TRUE" ] && [ -f "$standard_first_launch_file" ]); then
    return 1
  fi
  
  # Check for the specific flag files created by launch_ASA.sh
  if [ -f "/home/pok/.first_launch_msvcp140_error" ]; then
    echo ""
    echo "========================================================================="
    echo "[WARNING] DETECTED FIRST-LAUNCH MSVCP140.DLL ERROR"
    echo "-------------------------------------------------------------------------"
    echo "[INFO] This is a NORMAL and EXPECTED issue during the first launch when using API"
    echo "[INFO] mode. The Windows/Wine environment needs additional initialization that"
    echo "[INFO] can only be completed after a restart."
    echo ""
    echo "[INFO] The server will now automatically restart to resolve this issue."
    echo "[INFO] This process will ONLY happen once during the initial setup."
    echo "========================================================================="
    echo ""
    return 0
  fi
  
  if [ -f "/home/pok/.first_launch_error" ]; then
    echo ""
    echo "========================================================================="
    echo "[WARNING] DETECTED FIRST-LAUNCH ERROR"
    echo "-------------------------------------------------------------------------"
    echo "[INFO] A general first-launch error was detected. This is normal behavior"
    echo "[INFO] for the first run of ARK with API mode enabled."
    echo ""
    echo "[INFO] The server will now automatically restart to resolve this issue."
    echo "[INFO] This process will ONLY happen once during the initial setup."
    echo "========================================================================="
    echo ""
    return 0
  fi
  
  # Check wine log for MSVCP140.dll errors
  if [ -f "$wine_log_file" ] && grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" "$wine_log_file"; then
    echo ""
    echo "========================================================================="
    echo "[WARNING] DETECTED MSVCP140.DLL LOADING ERROR IN WINE LOG"
    echo "-------------------------------------------------------------------------"
    echo "[INFO] This is a common issue during first launch with API enabled. The Wine"
    echo "[INFO] environment needs to initialize Visual C++ libraries."
    echo ""
    echo "[INFO] The server will now automatically restart to resolve this issue."
    echo "[INFO] Subsequent launches will be much faster after this one-time setup."
    echo "========================================================================="
    echo ""
    return 0
  fi
  
  # Check for the specific Wine/MSVCP140.dll error pattern in server console logs
  if [ -f "$log_file" ] && grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" "$log_file"; then
    echo ""
    echo "========================================================================="
    echo "[WARNING] DETECTED MSVCP140.DLL LOADING ERROR IN CONSOLE LOG"
    echo "-------------------------------------------------------------------------"
    echo "[INFO] This error commonly occurs during the first launch with API mode enabled."
    echo "[INFO] It's related to the Visual C++ initialization process in Wine."
    echo ""
    echo "[INFO] The server will automatically restart to complete the initialization."
    echo "[INFO] This is a ONE-TIME process that ensures stable operation going forward."
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
      echo "[WARNING] POTENTIAL FIRST-LAUNCH FAILURE DETECTED"
      echo "-------------------------------------------------------------------------"
      echo "[INFO] The server seems to have failed without creating log files. This can"
      echo "[INFO] happen during the first launch with API mode when the Windows/Wine"
      echo "[INFO] environment is still initializing."
      echo ""
      echo "[INFO] The server will automatically restart to attempt recovery."
      echo "[INFO] This is normal behavior and will typically resolve after one restart."
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
  echo "┃ [SUCCESS] This is EXPECTED during first run with API mode         ┃"
  echo "┃ [SUCCESS] The system will AUTOMATICALLY fix this issue            ┃"
  echo "┃ [SUCCESS] This ONE-TIME process only happens on first launch      ┃"
  echo "┃ [SUCCESS] Second launch will be MUCH FASTER and stable            ┃"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
  echo ""
  echo "[INFO] Performing first-launch recovery procedure..."
  
  # Create flags in the new persistent config directory
  local config_dir="${ASA_DIR}/ShooterGame/Saved/Config/FirstLaunchFlags"
  mkdir -p "$config_dir" 2>/dev/null || true
  
  # Create the appropriate flag based on API mode
  if [ "${API}" = "TRUE" ]; then
    touch "${config_dir}/api_first_launch_completed"
  else
    touch "${config_dir}/standard_first_launch_completed"
  fi
  
  # Maintain backward compatibility with old flag location
  touch "/home/pok/.first_launch_completed"
  
  # Special log for first-launch recovery
  echo "$(TZ="${TZ}" date) - Performing automatic first-launch recovery due to MSVCP140.dll/Wine issues" > /home/pok/first_launch_recovery.log
  
  # Clean up error flag files
  rm -f "/home/pok/.first_launch_msvcp140_error" 2>/dev/null || true
  rm -f "/home/pok/.first_launch_error" 2>/dev/null || true
  
  # Terminate any running processes
  echo "[INFO] Stopping any running server processes..."
  pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
  pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
  pkill -9 -f "wine" >/dev/null 2>&1 || true
  pkill -9 -f "wineserver" >/dev/null 2>&1 || true
  
  # Clean up the Wine prefix to force re-initialization
  echo "[INFO] Cleaning up Wine/Proton environment..."
  rm -f "/home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg.bak" 2>/dev/null || true
  
  # Create the restart flag
  echo "API_RESTART" > /home/pok/restart_reason.flag
  
  # Remove the PID file if it exists
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi
  
  # Allow monitor process to continue (don't exit the container)
  echo "[INFO] Requesting server restart..."
  echo "true" > "/home/pok/.first_launch_restart_requested"
  
  # Now restart the server using restart_server.sh
  if [ -x "/home/pok/scripts/restart_server.sh" ]; then
    echo "[INFO] Running restart script with immediate parameter..."
    /home/pok/scripts/restart_server.sh immediate
  else
    echo "[WARNING] restart_server.sh not found or not executable"
    # Fallback to direct server launch
    nohup /home/pok/scripts/init.sh --from-restart > /home/pok/logs/restart_console.log 2>&1 &
  fi
  
  # Sleep to give restart time to initialize
  sleep 30
  
  echo "[SUCCESS] First-launch recovery completed. Server should restart automatically."
  echo "[SUCCESS] The server should be much faster and more stable after this restart."
  return 0
}

# Function to format interval text for display
format_interval_text() {
  local seconds=$1
  local interval_text=""
  
  if [ "$seconds" -ge 3600 ]; then
    local hrs=$((seconds / 3600))
    interval_text="$hrs hour"
    [ "$hrs" -gt 1 ] && interval_text="${interval_text}s"
  else
    local mins=$((seconds / 60))
    interval_text="$mins minute"
    [ "$mins" -gt 1 ] && interval_text="${interval_text}s"
  fi
  
  echo "$interval_text"
}

# Wait for the initial startup before monitoring
sleep $INITIAL_STARTUP_DELAY

# Clean up any legacy locks from previous system usage
if declare -f cleanup_legacy_locks >/dev/null 2>&1; then
  cleanup_legacy_locks "monitor"
else
  echo "[WARNING] cleanup_legacy_locks function not found in common.sh"
fi

# Show monitor startup message
if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
  display_monitor_status "🔍 Update monitor started (interval value: ${CHECK_FOR_UPDATE_INTERVAL})" "INFO" "true"
  display_interval_info
  display_monitor_status "🕒 Update window: ${UPDATE_WINDOW_MINIMUM_TIME} to ${UPDATE_WINDOW_MAXIMUM_TIME}"
  display_monitor_status "⏱️ Restart notice period: ${RESTART_NOTICE_MINUTES:-30} minutes"
fi

# Monitoring loop
while true; do
  # Check for restart timeout (nuclear option for stuck restarts)
  check_restart_timeout
  
  # Check if there's an active shutdown in progress
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "[INFO] Server shutdown/restart in progress, waiting before continuing monitoring..."
    sleep 30
    continue
  fi
  
  # Check for monitor stop flag - exit if we're being asked to stop
  if [ -f "/home/pok/stop_monitor.flag" ]; then
    display_monitor_status "Container restart/shutdown requested. Monitor stopping." "INFO" "true"
    echo "[INFO] Monitor stop flag detected - exiting monitoring loop"
    # Remove the flag so it doesn't affect next container start
    rm -f "/home/pok/stop_monitor.flag"
    exit 0
  fi

  # Check for failed restart attempts - if restart flag exists but server isn't running
  if [ -f "/home/pok/restart_reason.flag" ] && ! is_process_running; then
    current_time=$(TZ="${TZ}" date "+%Y-%m-%d %H:%M:%S")
    echo "[$current_time] [WARNING] Detected a restart flag with server not running - forced container kill needed" | tee -a "$RECOVERY_LOG"
    display_monitor_status "⚠️ Restart detected but server not running - forcing container kill" "WARNING" "true"
    
    # Ensure stop flag is created
    echo "true" > /home/pok/stop_monitor.flag
    
    # Execute the most aggressive kill methods immediately
    echo "[$current_time] [WARNING] Executing emergency container kill sequence" | tee -a "$RECOVERY_LOG"
    
    # Force sync to ensure all data is written
    sync
    
    # Kill everything with maximum prejudice
    killall -9 -u pok || true
    kill -9 -1 || true
    kill -9 1 || true
    kill -ABRT $$ || true
    
    # If we somehow get here, try a second approach
    exec kill -SEGV $$ || exit 1
  fi

  # Check for stale update flags (older than 6 hours) 
  # This prevents server from being stuck in "updating" mode if an update was interrupted
  if [ -f "$lock_file" ]; then
    # Use the enhanced lock checking mechanism
    lock_status=$(check_lock_status)
    status_code=$?
    
    if [ $status_code -eq 1 ]; then
      # Lock seems stale, try to clear it
      echo "[WARNING] Stale update lock detected. Details:"
      echo "$lock_status"
      echo "[INFO] Attempting to clear stale update flag..."
      
      if check_stale_update_flag 6; then
        # Stale flag was detected and cleared, continue with normal monitoring
        echo "[SUCCESS] Stale update flag was cleared. Continuing with normal monitoring."
      else
        # Flag might not be stale enough yet for automatic clearing
        echo "[INFO] Update flag not cleared automatically. It may still be valid or not old enough."
        echo "[INFO] If you believe this is stuck, manually clear it with: ./POK-manager.sh -clearupdateflag <instance_name>"
      fi
    elif [ $status_code -eq 0 ]; then
      # Lock is valid
      echo "[INFO] Update/Installation in progress. Please wait for it to complete..."
      echo "[INFO] Update details: "
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
    echo "[INFO] First-launch restart in progress, monitoring..."
    
    # Check if server is now running after the restart
    if is_process_running; then
      echo "[SUCCESS] Server is now running after first-launch restart. Recovery was successful."
      touch "/home/pok/.first_launch_restart_completed"
      rm -f "/home/pok/.first_launch_restart_requested"
    fi
    
    # Don't do other checks while in this recovery mode
    sleep 30
    continue
  fi
  
  if [ "${UPDATE_SERVER}" = "TRUE" ]; then
    # Check for updates at the interval specified by CHECK_FOR_UPDATE_INTERVAL
    current_time=$(TZ="${TZ}" date +%s)
    last_update_check_time=${last_update_check_time:-0}
    
    # Get update interval in seconds (no display output)
    update_check_interval_seconds=$(convert_interval_to_seconds)
    
    # Ensure we have a valid number
    if ! [[ $update_check_interval_seconds =~ ^[0-9]+$ ]]; then
      display_monitor_status "⚠️ Invalid interval value, using default of 1 hour" "WARNING"
      update_check_interval_seconds=3600
    fi

    # Put constraints around the update check interval to prevent it from running outside of desired time windows
    # Use TZ environment variable to ensure timezone-aware time conversion
    update_window_lower_bound=$(TZ="${TZ}" date -d "${UPDATE_WINDOW_MINIMUM_TIME}" +%s)
    update_window_upper_bound=$(TZ="${TZ}" date -d "${UPDATE_WINDOW_MAXIMUM_TIME}" +%s)

    # Display next check time if verbose logging is enabled
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
      # Calculate when the next check will occur
      next_check_time=$((last_update_check_time + update_check_interval_seconds))
      
      # Format for display using container timezone
      next_check_readable=$(TZ="${TZ}" date -d "@$next_check_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
      if [ $? -ne 0 ]; then
        # If date conversion failed, provide at least some information
        display_monitor_status "⚠️ Next check: Error calculating time" "WARNING" "true"
      else
        # Calculate minutes until next check
        time_until_next_check=$(( (next_check_time - current_time) / 60 ))
        
        # Get formatted interval text using the function
        interval_text=$(format_interval_text "$update_check_interval_seconds")
        
        # Display with appropriate wording
        if [ "$time_until_next_check" -le 0 ]; then
          display_monitor_status "📡 Update check due now (checking every $interval_text)" "INFO" "true"
        else
          if [ "$time_until_next_check" -eq 1 ]; then
            display_monitor_status "⏰ Next check: $next_check_readable (in $time_until_next_check minute, every $interval_text)" "INFO" "true"
          else
            display_monitor_status "⏰ Next check: $next_check_readable (in $time_until_next_check minutes, every $interval_text)" "INFO" "true"
          fi
        fi
      fi
      
      # Display update window information using container timezone
      current_time_readable=$(TZ="${TZ}" date -d "@$current_time" "+%H:%M:%S" 2>/dev/null)
      min_time_readable=$(TZ="${TZ}" date -d "@$update_window_lower_bound" "+%H:%M:%S" 2>/dev/null)
      max_time_readable=$(TZ="${TZ}" date -d "@$update_window_upper_bound" "+%H:%M:%S" 2>/dev/null)
      
      # Make sure we have valid values for all variables
      if [ -n "$current_time" ] && [ -n "$update_window_lower_bound" ] && [ -n "$update_window_upper_bound" ]; then
        # Safe comparison with proper variable validation
        if [ "$current_time" -ge "$update_window_lower_bound" ] && [ "$current_time" -le "$update_window_upper_bound" ]; then
          display_monitor_status "🕒 Current time $current_time_readable is WITHIN update window ($min_time_readable - $max_time_readable)"
        else
          display_monitor_status "🕒 Current time $current_time_readable is OUTSIDE update window ($min_time_readable - $max_time_readable)" "WARNING"
        fi
      else
        display_monitor_status "⚠️ Unable to validate update window times" "WARNING"
      fi
    fi

    # Safe comparison with proper variable validation
    if [ -n "$current_time" ] && [ -n "$last_update_check_time" ] && [ -n "$update_check_interval_seconds" ] && \
       [ -n "$update_window_lower_bound" ] && [ -n "$update_window_upper_bound" ] && \
       [ "$((current_time - last_update_check_time))" -gt "$update_check_interval_seconds" ] && \
       [ "$current_time" -ge "$update_window_lower_bound" ] && [ "$current_time" -le "$update_window_upper_bound" ]; then
      # Make sure any stale shutdown flags are cleared before update check
      if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
        display_monitor_status "Removing stale shutdown complete flag before update check..." "WARNING"
        rm -f "$SHUTDOWN_COMPLETE_FLAG"
      fi
      
      # Use enhanced update checking that includes dirty flag support
      display_monitor_status "🔎 CHECKING FOR UPDATES using enhanced system (SteamCMD + dirty flags)..." "INFO" "true"
      
      # Check for dirty flag first (other instance updated shared files)
      if has_dirty_flag; then
        display_monitor_status "🔄 DIRTY FLAG DETECTED! Another instance updated server files - restart required" "WARNING" "true"
        
        # Set restart mode flag for proper messaging during restart
        export API_CONTAINER_RESTART="TRUE"
        
        # Start the update server script to handle the dirty flag restart
        display_monitor_status "🔄 Launching update_server.sh to handle dirty flag restart"
        # Ensure RESTART_NOTICE_MINUTES is exported before calling update_server.sh
        export RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-30}"
        /home/pok/scripts/update_server.sh
        
        # This will handle the restart with appropriate notification
      else
        # Check for actual updates using POK_Update_Monitor.sh
        # Capture the output of POK_Update_Monitor.sh for display if enabled
        if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
          # Run the command and capture both output and status in a safer way
          update_output=$(/home/pok/scripts/POK_Update_Monitor.sh 2>&1)
          update_status=$?
          
          # Display the output with each line properly formatted - handle the output carefully
          if [ -n "$update_output" ]; then
            # Use a safer method to process the output line by line
            while IFS= read -r line; do
              # Skip empty lines
              if [ -n "$line" ]; then
                display_monitor_status "$line"
              fi
            done <<< "$update_output"
          fi
        else
          # Run silently when display is disabled
          /home/pok/scripts/POK_Update_Monitor.sh >/dev/null 2>&1
          update_status=$?
        fi
        
        if [ $update_status -eq 0 ]; then
          display_monitor_status "✅ UPDATE DETECTED! Starting update process" "SUCCESS" "true"
          # Set restart mode flag for proper messaging during restart
          export API_CONTAINER_RESTART="TRUE"
          
          # Start the update server script to handle the update process
          display_monitor_status "🔄 Launching update_server.sh to handle the update process"
          # Ensure RESTART_NOTICE_MINUTES is exported before calling update_server.sh
          export RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-30}"
          /home/pok/scripts/update_server.sh
        else
          display_monitor_status "✅ Server is up to date - no update needed" "SUCCESS" "true"
        fi
      fi
      last_update_check_time=$current_time
    fi
  fi
  # Check if the no_restart flag is present before checking the server running state
  if [ -f "$NO_RESTART_FLAG" ]; then
    echo "[INFO] Shutdown flag is present, skipping server status check and potential restart..."
    sleep 30 # Adjust sleep as needed
    continue # Skip the rest of this loop iteration, avoiding the server running state check and restart
  fi

  # Add status message with display conditions
  if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
    if ! is_process_running false && ! is_server_updating; then
      display_monitor_status "⚠️ SERVER NOT RUNNING - will attempt recovery" "WARNING"
    fi
  fi
  
  # Restart the server if it's not running and not currently updating
  if ! is_process_running && ! is_server_updating; then
    display_monitor_status "⚠️ Detected server is not running, killing container for Docker restart..." "WARNING" "true"
    
    # Use the enhanced recovery function instead of simple restart
    recover_server
    
    # This should never be reached as recover_server now kills the container
    # But just in case, sleep to avoid rapid restart attempts
    sleep 60
  else
    # Server is running normally, just do regular short sleep
    sleep 30 # Short sleep to prevent high CPU usage
  fi
done