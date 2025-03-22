#!/bin/bash
source /home/pok/scripts/common.sh
source /home/pok/scripts/shutdown_server.sh

RESTART_MODE="$1" # Immediate or countdown
RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-5}" # Default to 5 minutes for countdown
EXIT_ON_API_RESTART="${EXIT_ON_API_RESTART:-TRUE}" # Default to TRUE - controls container exit behavior
SHUTDOWN_COMPLETE_FLAG="/home/pok/shutdown_complete.flag"
SHOW_ANIMATED_COUNTDOWN="${SHOW_ANIMATED_COUNTDOWN:-FALSE}" # Can be set to TRUE by POK-manager.sh
UPDATE_RESTART="${UPDATE_RESTART:-FALSE}" # Set to TRUE when called after an update

# Check if we're being called after an update
if [ -f "/home/pok/restart_reason.flag" ] && [ "$(cat /home/pok/restart_reason.flag)" = "UPDATE_RESTART" ]; then
  UPDATE_RESTART="TRUE"
  rm -f "/home/pok/restart_reason.flag"
  echo "🔄 Server restarting after update..."
fi

# Function to display animated countdown - same as in rcon_interface.sh
display_animated_countdown() {
  local duration=$1
  local total_seconds=$((duration * 60))
  local seconds_remaining=$total_seconds
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spinner_idx=0
  local status_color="\033[1;36m" # Cyan for status
  local time_color="\033[1;33m" # Yellow for time
  local reset_color="\033[0m"
  local success_color="\033[1;32m" # Green for success messages
  local warning_color="\033[1;33m" # Yellow for warnings
  local action_color="\033[1;35m" # Magenta for action status
  
  echo -e "${status_color}Server restart in progress...${reset_color}"
  echo "Press Ctrl+C to exit this display (restart will continue in background)"
  
  # Clear any existing shutdown flag to start fresh
  rm -f "$SHUTDOWN_COMPLETE_FLAG"
  
  # Initialize notification tracking
  local last_notification_point=""
  
  # Main countdown loop
  while [ $seconds_remaining -gt 0 ]; do
    local minutes_remaining=$((seconds_remaining / 60))
    local seconds_in_minute=$((seconds_remaining % 60))
    
    # Check if this is a notification point
    local current_point=""
    
    # 5-minute intervals
    if [ $minutes_remaining -ge 5 ] && [ $seconds_in_minute -eq 0 ] && [ $((minutes_remaining % 5)) -eq 0 ]; then
      current_point="${minutes_remaining}m"
    # 3-minute mark
    elif [ $minutes_remaining -eq 3 ] && [ $seconds_in_minute -eq 0 ]; then
      current_point="3m"
    # 1-minute mark
    elif [ $minutes_remaining -eq 1 ] && [ $seconds_in_minute -eq 0 ]; then
      current_point="1m"
    # 30-second mark
    elif [ $minutes_remaining -eq 0 ] && [ $seconds_in_minute -eq 30 ]; then
      current_point="30s"
    # Final 10 seconds
    elif [ $minutes_remaining -eq 0 ] && [ $seconds_in_minute -le 10 ] && [ $seconds_in_minute -gt 0 ]; then
      current_point="${seconds_in_minute}s"
    fi
    
    # If we hit a notification point and it's different from the last one, log it
    if [ -n "$current_point" ] && [ "$current_point" != "$last_notification_point" ]; then
      echo -e "\r${success_color}✓${reset_color} Server notification sent: ${time_color}${current_point}${reset_color} remaining          "
      last_notification_point="$current_point"
      # Log notification but don't break the line
      echo ""
    fi
    
    # Update the spinner
    local current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    # Format time as "Xm Ys"
    local eta_display="${minutes_remaining}m ${seconds_in_minute}s"
    
    # Clear line and show single-line ETA with spinner
    printf "\r${status_color}%s${reset_color} ${action_color}Restarting:${reset_color} ${time_color}ETA: %-8s${reset_color}" "$current_spinner" "$eta_display"
    
    sleep 1
    ((seconds_remaining--))
    
    # Check if the shutdown has already completed
    if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
      echo -e "\r${success_color}✓${reset_color} Server restart initiated early!                       "
      return
    fi
  done
  
  # Show completion message
  echo -e "\r${success_color}✓${reset_color} ${action_color}Restarting:${reset_color} ${time_color}Countdown complete!${reset_color}                 "
  
  # Immediate detailed feedback after countdown completes
  echo -e "\n${status_color}Starting server shutdown phase...${reset_color}"
  
  # Wait for shutdown flag to appear with cleaner status messages
  local wait_count=0
  local max_wait=120  # 2 minutes max wait time
  local phase="saving"  # Track current phase
  
  while [ ! -f "$SHUTDOWN_COMPLETE_FLAG" ] && [ $wait_count -lt $max_wait ]; do
    sleep 1
    ((wait_count++))
    current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    # Determine phase message based on time elapsed
    if [ $wait_count -le 30 ]; then
      if [ "$phase" != "saving" ]; then
        phase="saving"
        echo ""  # Add space before new phase
      fi
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 1/3:${reset_color} Saving world data... " "$current_spinner"
    elif [ $wait_count -le 60 ]; then
      if [ "$phase" != "exiting" ]; then
        phase="exiting"
        echo ""  # Add space before new phase
        echo -e "${success_color}✓${reset_color} World data save complete"
      fi
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 2/3:${reset_color} Waiting for server processes... " "$current_spinner"
    else
      if [ "$phase" != "cleanup" ]; then
        phase="cleanup"
        echo ""  # Add space before new phase
        echo -e "${success_color}✓${reset_color} Server processes stopped"
      fi
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 3/3:${reset_color} Cleaning up environment... " "$current_spinner"
    fi
    
    # Check server process status every 15 seconds
    if [ $((wait_count % 15)) -eq 0 ]; then
      if ! is_process_running; then
        if [ "$phase" = "exiting" ]; then
          echo ""  # Add space before new status
          echo -e "${success_color}✓${reset_color} Server processes have exited"
          phase="process_exited" # Prevent duplicate messages
        fi
      fi
    fi
  done
  
  # Final status after waiting
  echo ""  # Add a final newline
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo -e "${success_color}✓ Server shutdown phase completed!${reset_color}"
    echo -e "${status_color}Initiating server restart phase...${reset_color}"
  else
    echo -e "${warning_color}⚠️ Timeout during shutdown phase${reset_color}"
    echo -e "${status_color}Proceeding with restart attempt...${reset_color}"
    # Create the flag anyway to continue with restart
    touch "$SHUTDOWN_COMPLETE_FLAG"
  fi
}

# Function to thoroughly clean up environment before restart
cleanup_environment() {
  echo "Performing thorough environment cleanup before restart..."
  
  # Remove any stale PID files
  if [ -f "$PID_FILE" ]; then
    echo "Removing stale PID file..."
    rm -f "$PID_FILE"
  fi
  
  # Remove shutdown flag if it exists
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "Removing shutdown complete flag..."
    rm -f "$SHUTDOWN_COMPLETE_FLAG"
  fi
  
  # Kill any Wine/Proton processes
  if pgrep -f "wine" >/dev/null 2>&1 || pgrep -f "wineserver" >/dev/null 2>&1; then
    echo "Cleaning up Wine/Proton processes..."
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    sleep 2
  fi
  
  # Clean up X11 sockets
  if [ -d "/tmp/.X11-unix" ]; then
    echo "Cleaning up X11 sockets..."
    rm -rf /tmp/.X11-unix/* 2>/dev/null || true
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
  fi
  
  # If API=TRUE, reset the Wine prefix state
  if [ "${API}" = "TRUE" ]; then
    echo "Resetting Proton/Wine environment for API mode..."
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
    export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
    export WINEDLLOVERRIDES="version=n,b"
  fi
  
  # Clean up temporary files to save disk space
  echo "Cleaning up temporary files to save disk space..."
  # Clean SteamCMD temporary files and logs
  rm -rf /opt/steamcmd/Steam/logs/* 2>/dev/null || true
  rm -rf /opt/steamcmd/Steam/appcache/httpcache/* 2>/dev/null || true
  
  # Clean Wine/Proton temporary files
  rm -rf "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Temp"/* 2>/dev/null || true
  
  # Clean temporary files in /tmp
  rm -f /tmp/*.log 2>/dev/null || true
  rm -f /tmp/ark_* 2>/dev/null || true
  rm -f /tmp/launch_output.log 2>/dev/null || true
  rm -f /tmp/asaapi_logs_pipe_* 2>/dev/null || true
  
  # Rotate log files to prevent accumulation
  if [ -d "${ASA_DIR}/ShooterGame/Saved/Logs" ]; then
    echo "Rotating server logs..."
    # Keep only the most recent 5 log files, remove the rest
    find "${ASA_DIR}/ShooterGame/Saved/Logs" -name "*.log" -type f -not -name "ShooterGame.log" | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi
  
  # Rotate AsaApi log files
  if [ -d "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" ]; then
    echo "Rotating AsaApi logs..."
    find "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" -name "*.log" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi
  
  echo "Environment cleanup completed."
}

# Function to exit the container with a restart signal
exit_container_for_restart() {
  local restart_reason="${1:-NORMAL_RESTART}"
  
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
  
  # Create a flag file to indicate a clean exit for restart
  echo "$(date) - Container exiting for automatic restart by orchestration system" > /home/pok/container_restart.log
  
  # Create a flag file that will be detected on container restart
  echo "$restart_reason" > /home/pok/restart_reason.flag
  
  echo "🔄 Container will now exit for restart via Docker"
  echo "⚠️ Docker will automatically restart the container"
  
  # Create a special flag to tell the monitor to stop as well
  echo "true" > /home/pok/stop_monitor.flag
  
  # Simplified container exit approach - no extensive cleanup needed
  echo "[INFO] Server is shut down. Killing container to trigger Docker restart..."
  
  # Force kill the container process with SIGKILL
  echo "[INFO] Force killing ALL container processes for restart..."
  
  # Flush disk writes
  sync 
  sleep 1
  
  # Super aggressive container kill approach:
  
  # 1. Kill all processes owned by our user
  echo "[INFO] Killing all user processes with SIGKILL..."
  killall -9 -u pok || true
  
  # 2. Kill all processes in our process group
  echo "[INFO] Killing all processes in process group with SIGKILL..."
  kill -9 -1 || true
  
  # 3. Force kill init process (tini)
  echo "[INFO] Directly killing PID 1 (tini) with SIGKILL..."
  kill -9 1 || true
  
  # 4. As absolute last resort, crash our own process with ABORT signal
  echo "[INFO] Last resort: Sending SIGABRT to our own process to force container crash..."
  kill -ABRT $$ || true
  
  # If we somehow get here, exit with failure code
  exit 1
}

# Function to restart the server after cleanup
restart_server_direct() {
  # Always use container restart strategy for all modes
  echo "Using container restart strategy for clean, consistent server restarts"
  
  # Exit the container to trigger restart by orchestration system
  exit_container_for_restart
  # This function will not return as it exits the container
}

# Function to wait for shutdown flag
wait_for_shutdown_completion() {
  local max_wait_time=600  # 10 minutes timeout
  local wait_time=0
  local check_interval=5
  
  echo "Waiting for server shutdown to complete..."
  
  while [ ! -f "$SHUTDOWN_COMPLETE_FLAG" ] && [ $wait_time -lt $max_wait_time ]; do
    sleep $check_interval
    wait_time=$((wait_time + check_interval))
    
    if [ $((wait_time % 30)) -eq 0 ]; then
      echo "Still waiting for shutdown to complete... ($wait_time seconds elapsed)"
    fi
  done
  
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "✓ Shutdown complete signal received."
    return 0
  else
    echo "⚠ Timed out waiting for shutdown signal after $max_wait_time seconds."
    return 1
  fi
}

if [ "$RESTART_MODE" == "immediate" ]; then
  echo "Attempting immediate restart..."
  
  # If server is running, shut it down first
  if is_process_running; then
    echo "Server is running. Initiating shutdown before restart..."
    shutdown_handler false
    
    # Wait for server to fully shut down
    echo "Waiting for server to fully shut down..."
    local wait_time=0
    while is_process_running && [ $wait_time -lt 60 ]; do
      sleep 5
      wait_time=$((wait_time + 5))
      echo "Still waiting for shutdown... ($wait_time seconds elapsed)"
    done
    
    # Force kill if still running after 60 seconds
    if is_process_running; then
      echo "Server still running after 60 seconds. Forcing shutdown..."
      local pid=$(ps aux | grep -E "AsaApiLoader.exe|ArkAscendedServer.exe" | grep -v grep | awk '{print $2}' | head -1)
      if [ -n "$pid" ]; then
        kill -9 $pid
        sleep 2
      fi
    fi
  else
    echo "Server is already down. Proceeding with restart..."
  fi
  
  # Clean up environment thoroughly
  cleanup_environment
  
  # Exit container to restart
  echo "Triggering container restart for immediate server restart..."
  exit_container_for_restart "IMMEDIATE_RESTART"
else
  echo "Scheduled restart with a countdown of $RESTART_NOTICE_MINUTES minutes..."

  # For update restarts, use a special handling approach
  if [ "$UPDATE_RESTART" = "TRUE" ]; then
    echo "🔄 Restart requested after update - handling with update-specific protocol"
    
    # For update restarts, we don't need to notify again as update_server.sh already did countdown
    echo "Server is restarting after update..."
    
    # Clean up environment thoroughly
    cleanup_environment
    
    # Exit container to trigger restart for a clean update
    exit_container_for_restart "UPDATE_RESTART_COMPLETED"
  # For API mode with EXIT_ON_API_RESTART=TRUE, handle shutdown and container restart differently
  elif [ "${API}" = "TRUE" ] && [ "${EXIT_ON_API_RESTART}" = "TRUE" ]; then
    echo "API mode with container restart strategy detected"
    echo "Will fully complete shutdown sequence before container restart"
    
    # Use the API restart flag to change behavior of shutdown sequence
    # This ensures all RCON commands complete before container restart
    export API_CONTAINER_RESTART="TRUE"
    
    # Start the shutdown process in background if we're showing the animated countdown
    if [ "$SHOW_ANIMATED_COUNTDOWN" = "TRUE" ]; then
      initiate_shutdown "$RESTART_NOTICE_MINUTES" &
      SHUTDOWN_PID=$!
      
      # Show animated countdown
      display_animated_countdown "$RESTART_NOTICE_MINUTES"
      
      # Wait for the background process to finish
      wait $SHUTDOWN_PID 2>/dev/null || true
    else
      # Otherwise, just run the shutdown directly
      initiate_shutdown "$RESTART_NOTICE_MINUTES"
    fi
    
    # Wait for shutdown flag to confirm completion
    if wait_for_shutdown_completion; then
      # After shutdown completes, clean up and exit to trigger container restart
      cleanup_environment
      exit_container_for_restart "UPDATE_RESTART_COMPLETED"
    else
      echo "WARNING: Shutdown did not complete properly. Forcing container restart anyway."
      cleanup_environment
      exit_container_for_restart "UPDATE_RESTART_FAILED"
    fi
  else
    # For non-API mode or if EXIT_ON_API_RESTART=FALSE, use standard restart
    # Start the shutdown process in background if we're showing the animated countdown
    if [ "$SHOW_ANIMATED_COUNTDOWN" = "TRUE" ]; then
      # Set restart context for proper messages
      export API_CONTAINER_RESTART="TRUE"
      
      # Run shutdown in background
      initiate_shutdown "$RESTART_NOTICE_MINUTES" &
      SHUTDOWN_PID=$!
      
      # Show animated countdown
      display_animated_countdown "$RESTART_NOTICE_MINUTES"
      
      # Wait for background process to finish
      wait $SHUTDOWN_PID 2>/dev/null || true
    else
      # Otherwise, set the context and run shutdown directly
      export API_CONTAINER_RESTART="TRUE"
      initiate_shutdown "$RESTART_NOTICE_MINUTES"
    fi
    
    # Wait for shutdown flag to confirm completion
    wait_for_shutdown_completion
    
    # Clean up environment thoroughly
    cleanup_environment
    
    # Restart server
    restart_server_direct
  fi
fi

# First send a notification about the restart
if [ "${SKIP_INITIAL_NOTIFICATION}" != "TRUE" ]; then
  send_rcon_command "ServerChat Server restarting in $RESTART_NOTICE_MINUTES minute(s)"
fi