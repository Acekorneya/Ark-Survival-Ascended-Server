#!/bin/bash
source /home/pok/scripts/common.sh
source /home/pok/scripts/shutdown_server.sh

RESTART_MODE="$1" # Immediate or countdown
RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-5}" # Default to 5 minutes for countdown
EXIT_ON_API_RESTART="${EXIT_ON_API_RESTART:-TRUE}" # Default to TRUE - controls container exit behavior
SHUTDOWN_COMPLETE_FLAG="/home/pok/shutdown_complete.flag"
SHOW_ANIMATED_COUNTDOWN="${SHOW_ANIMATED_COUNTDOWN:-FALSE}" # Can be set to TRUE by POK-manager.sh

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
  
  echo "Environment cleanup completed."
}

# Function to exit the container with a restart signal
exit_container_for_restart() {
  # Create a flag file to indicate a clean exit for restart
  echo "$(date) - Container exiting for automatic restart by orchestration system" > /home/pok/container_restart.log
  
  # Create a flag file that will be detected on container restart
  echo "API_RESTART" > /home/pok/restart_reason.flag
  
  echo "🔄 API mode with restart requested - Container will now exit with code 0"
  echo "⚠️ Container orchestration should restart the container automatically"
  echo "📝 If container does not restart automatically, please restart it manually"
  
  # Allow some time for logs to be written
  sleep 3
  
  # Exit the container with success code (0) which should trigger restart by orchestration
  exit 0
}

# Function to restart the server after cleanup
restart_server_direct() {
  # For API mode, implement the exit strategy if enabled
  if [ "${API}" = "TRUE" ] && [ "${EXIT_ON_API_RESTART}" = "TRUE" ]; then
    echo "API mode detected with EXIT_ON_API_RESTART=TRUE"
    echo "Using container restart strategy for more reliable API mode restarts"
    
    # Exit the container to trigger restart by orchestration system
    exit_container_for_restart
    # This function will not return as it exits the container
  fi
  
  echo "Starting server after cleanup..."
  
  # Critical: For API mode, don't start Xvfb here - let init.sh handle it
  # This avoids conflicts where multiple scripts try to manage Xvfb
  if [ "${API}" = "TRUE" ]; then
    # Just set the display variable, but don't start Xvfb
    export DISPLAY=:0.0
    echo "API mode: Setting DISPLAY=:0.0 for init.sh to use"
    
    # Kill any existing Xvfb processes to ensure clean state for init.sh
    if pgrep -f "Xvfb" >/dev/null 2>&1; then
      echo "Cleaning up existing Xvfb processes before init.sh starts..."
      pkill -9 -f "Xvfb" >/dev/null 2>&1 || true
      sleep 3
    fi
  fi
  
  # Make sure the logs directory exists
  mkdir -p /home/pok/logs
  
  # Export critical environment variables
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
  export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
  export WINEDLLOVERRIDES="version=n,b"
  
  # Create a flag file to indicate restart is in progress
  touch /tmp/restart_in_progress
  
  # For API mode, use direct execution with the restart flag
  if [ "${API}" = "TRUE" ]; then
    echo "Executing init.sh (API mode) with restart flag..."
    nohup /home/pok/scripts/init.sh --from-restart > /home/pok/logs/restart_console.log 2>&1 &
    INIT_PID=$!
    echo "Started init.sh with PID: $INIT_PID"
  else
    echo "Executing init.sh to restart the server..."
    nohup /home/pok/scripts/init.sh --from-restart > /home/pok/logs/restart_console.log 2>&1 &
  fi
  
  echo "Server restart initiated. View logs with: tail -f /home/pok/logs/restart_console.log"
  
  # Add a slight delay to allow init.sh to start
  sleep 5
  
  # Check if init.sh started successfully 
  if [ "${API}" = "TRUE" ]; then
    # For API mode, verify Xvfb started
    if pgrep -f "Xvfb" >/dev/null 2>&1; then
      echo "Xvfb process detected - init.sh appears to be running correctly"
    else
      echo "WARNING: No Xvfb process detected yet. init.sh might still be starting up."
      echo "Restarting Xvfb manually to ensure proper environment..."
      Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
      sleep 2
    fi
  fi
  
  # Start displaying logs in background - this is especially important for restarts
  (
    echo "Setting up log display after restart..."
    # Wait a bit for the server to create logs
    sleep 30
    
    # Define log paths
    local game_log="${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
    local api_log="${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    local max_wait=60
    
    # Check for logs and start displaying them
    if [ "${API}" = "TRUE" ]; then
      # For API mode, show both API and game logs if available
      echo "Checking for API logs after restart..."
      if [ -d "$api_log" ] && [ "$(ls -A $api_log 2>/dev/null | grep -i .log)" ]; then
        local newest_api_log=$(ls -t $api_log/*.log 2>/dev/null | head -1)
        if [ -n "$newest_api_log" ]; then
          echo "Found API log: $(basename $newest_api_log)"
          echo "Tailing API log in background..."
          tail -f "$newest_api_log" &
        fi
      fi
    fi
    
    # Always try to show the main game logs
    echo "Checking for ShooterGame logs after restart..."
    local elapsed=0
    local check_interval=5
    
    while [ $elapsed -lt $max_wait ]; do
      if [ -f "$game_log" ]; then
        echo "Found ShooterGame log at: $game_log"
        echo "Tailing ShooterGame log to console..."
        tail -f "$game_log" &
        break
      fi
      
      # Also check for the symlink we created
      if [ -f "/home/pok/shooter_game.log" ]; then
        echo "Found ShooterGame log via symlink"
        echo "Tailing ShooterGame log to console..."
        tail -f "/home/pok/shooter_game.log" &
        break
      fi
      
      sleep $check_interval
      elapsed=$((elapsed + check_interval))
      echo "Still waiting for ShooterGame log... ($elapsed seconds)"
    done
    
    if [ $elapsed -ge $max_wait ]; then
      echo "WARNING: ShooterGame logs not found after $max_wait seconds"
      echo "To view logs later, check: $game_log"
    fi
  ) &
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
  
  # Restart server
  restart_server_direct
else
  echo "Scheduled restart with a countdown of $RESTART_NOTICE_MINUTES minutes..."

  # For API mode with EXIT_ON_API_RESTART=TRUE, handle shutdown and container restart differently
  if [ "${API}" = "TRUE" ] && [ "${EXIT_ON_API_RESTART}" = "TRUE" ]; then
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
      exit_container_for_restart
    else
      echo "WARNING: Shutdown did not complete properly. Forcing container restart anyway."
      cleanup_environment
      exit_container_for_restart
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