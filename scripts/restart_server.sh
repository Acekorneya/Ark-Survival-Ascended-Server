#!/bin/bash
#
# In-container coordinated restart flow with countdown handling.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/shutdown_server.sh"

RESTART_MODE=""
RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-5}" # Default to 5 minutes for countdown
EXIT_ON_API_RESTART="${EXIT_ON_API_RESTART:-TRUE}" # Default to TRUE - controls container exit behavior
SHUTDOWN_COMPLETE_FLAG="/home/pok/shutdown_complete.flag"
SHOW_ANIMATED_COUNTDOWN="${SHOW_ANIMATED_COUNTDOWN:-FALSE}" # Can be set to TRUE by POK-manager.sh
UPDATE_RESTART="${UPDATE_RESTART:-FALSE}" # Set to TRUE when called after an update

initialize_restart_context() {
  RESTART_MODE="${1:-}"
  RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-5}"
  EXIT_ON_API_RESTART="${EXIT_ON_API_RESTART:-TRUE}"
  SHOW_ANIMATED_COUNTDOWN="${SHOW_ANIMATED_COUNTDOWN:-FALSE}"
  UPDATE_RESTART="${UPDATE_RESTART:-FALSE}"

  if [ -f "/home/pok/restart_reason.flag" ] && [ "$(cat /home/pok/restart_reason.flag)" = "UPDATE_RESTART" ]; then
    UPDATE_RESTART="TRUE"
    rm -f "/home/pok/restart_reason.flag"
    echo "🔄 Server restarting after update..."
  fi
}

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
    echo -e "${warning_color}Shutdown remains unverified; restart will not continue.${reset_color}"
    return 1
  fi
}

# Function to thoroughly clean up environment before restart
cleanup_environment() {
  echo "Performing thorough environment cleanup before restart..."

  if shutdown_server_process_running && [ ! -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    echo "Error: Refusing process cleanup before both save stages are verified." >&2
    return 1
  fi
  
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

  if shutdown_server_process_running && ! safe_container_stop; then
    echo "[ERROR] Container restart aborted because both saves were not verified." >&2
    return 1
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
  echo "[INFO] Server is safely shut down. Signaling PID 1 for a clean container restart..."
  sync
  sleep 1
  kill -TERM 1
  return 0
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

main() {
  prepare_runtime_env
  initialize_restart_context "$1"

  if [ "$RESTART_MODE" == "immediate" ]; then
    echo "Attempting immediate restart..."

    if is_process_running; then
      echo "Server is running. Initiating shutdown before restart..."
      shutdown_handler false || return 1
    else
      echo "Server is already down. Proceeding with restart..."
    fi

    cleanup_environment || return 1
    echo "Triggering container restart for immediate server restart..."
    exit_container_for_restart "IMMEDIATE_RESTART"
  else
    echo "Scheduled restart with a countdown of $RESTART_NOTICE_MINUTES minutes..."

    if [ "$UPDATE_RESTART" = "TRUE" ]; then
      echo "🔄 Restart requested after update - handling with update-specific protocol"
      echo "Server is restarting after update..."
      cleanup_environment || return 1
      exit_container_for_restart "UPDATE_RESTART_COMPLETED"
    elif [ "${API}" = "TRUE" ] && [ "${EXIT_ON_API_RESTART}" = "TRUE" ]; then
      echo "API mode with container restart strategy detected"
      echo "Will fully complete shutdown sequence before container restart"
      export API_CONTAINER_RESTART="TRUE"

      if [ "$SHOW_ANIMATED_COUNTDOWN" = "TRUE" ]; then
        initiate_shutdown "$RESTART_NOTICE_MINUTES" &
        SHUTDOWN_PID=$!
        display_animated_countdown "$RESTART_NOTICE_MINUTES"
        wait $SHUTDOWN_PID 2>/dev/null || return 1
      else
        initiate_shutdown "$RESTART_NOTICE_MINUTES" || return 1
      fi

      if wait_for_shutdown_completion; then
        cleanup_environment || return 1
        exit_container_for_restart "UPDATE_RESTART_COMPLETED"
      else
        echo "ERROR: Shutdown did not complete safely. Container restart aborted." >&2
        return 1
      fi
    else
      if [ "$SHOW_ANIMATED_COUNTDOWN" = "TRUE" ]; then
        export API_CONTAINER_RESTART="TRUE"
        initiate_shutdown "$RESTART_NOTICE_MINUTES" &
        SHUTDOWN_PID=$!
        display_animated_countdown "$RESTART_NOTICE_MINUTES"
        wait $SHUTDOWN_PID 2>/dev/null || return 1
      else
        export API_CONTAINER_RESTART="TRUE"
        initiate_shutdown "$RESTART_NOTICE_MINUTES" || return 1
      fi

      wait_for_shutdown_completion || return 1
      cleanup_environment || return 1
      restart_server_direct
    fi
  fi

  if [ "${SKIP_INITIAL_NOTIFICATION}" != "TRUE" ]; then
    send_rcon_command "ServerChat Server restarting in $RESTART_NOTICE_MINUTES minute(s)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
