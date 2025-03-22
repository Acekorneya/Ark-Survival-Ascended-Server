#!/bin/bash

# Source common variables, functions, and the rcon_commands.sh script
source /home/pok/scripts/common.sh
source /home/pok/scripts/rcon_commands.sh

# Define shutdown flag file location
SHUTDOWN_COMPLETE_FLAG="/home/pok/shutdown_complete.flag"

# Function to check if save is complete
save_complete_check() {
  local log_file="$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
  if tail -n 10 "$log_file" | grep -q "World Save Complete"; then
    echo "Save operation completed."
    return 0
  else
    return 1
  fi
}

# Function to check if server has stopped properly
server_stopped_check() {
  local log_file="$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
  if tail -n 20 "$log_file" | grep -q "Server stopped"; then
    echo "Server stopped properly."
    return 0
  else
    return 1
  fi
}

# Function for safe container shutdown - used by POK-manager.sh -stop -all
# Ensures world is saved before container is stopped
safe_container_stop() {
  # First check if actual server process exists using pgrep
  if pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 || pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
    echo "---- Safe container stop initiated ----"
    echo "Performing world save before container stop..."
    
    # Try to check if RCON is responsive before sending commands
    local rcon_test_output
    rcon_test_output=$(timeout 5 ${RCON_PATH} -a ${RCON_HOST}:${RCON_PORT} -p "${RCON_PASSWORD}" "info" 2>&1)
    local rcon_status=$?
    
    if [ $rcon_status -eq 0 ] && ! echo "$rcon_test_output" | grep -q "Failed to connect"; then
      # RCON is responsive, proceed with normal shutdown
      # Send a save command and notify players
      send_rcon_command "ServerChat Server is being stopped! Saving world data..."
      send_rcon_command "saveworld"
      
      echo "Waiting for save completion..."
      sleep 5
      
      # Wait for save to complete with a reasonable timeout
      local save_wait=0
      local max_save_wait=60  # 1 minute max wait for save
      
      while ! save_complete_check && [ $save_wait -lt $max_save_wait ]; do
        sleep 5
        save_wait=$((save_wait + 5))
        echo "Still waiting for world save to complete... ($save_wait seconds elapsed)"
      done
      
      if [ $save_wait -lt $max_save_wait ]; then
        echo "✅ World save completed successfully."
      else
        echo "⚠️ World save timed out, but proceeding with safe shutdown."
      fi
      
      # Attempt to gracefully shut down the server
      echo "Sending shutdown command to server..."
      send_rcon_command "DoExit"
    else
      echo "⚠️ RCON connection failed - server might be unresponsive. Using direct process termination."
    fi
    
    # Create the shutdown complete flag to signal that it's safe to stop the container
    touch "$SHUTDOWN_COMPLETE_FLAG"
    
    sleep 10
    
    # Wait for "Server stopped" message in logs with a timeout
    local stop_wait=0
    local max_stop_wait=30  # 30 seconds max wait for stop
    
    while ! server_stopped_check && [ $stop_wait -lt $max_stop_wait ]; do
      sleep 5
      stop_wait=$((stop_wait + 5))
      echo "Waiting for server to fully stop... ($stop_wait seconds elapsed)"
    done
    
    echo "---- Safe container stop completed ----"
    echo "Container can now be safely stopped without data loss."
  else
    echo "Server is not running, no need to save world before stopping container."
    touch "$SHUTDOWN_COMPLETE_FLAG"  # Signal that it's safe to proceed
  fi
  
  return 0
}

# Function to handle graceful shutdown
shutdown_handler() {
  local with_restart=${1:-false}
  
  if is_process_running; then
    echo "---- Server shutdown initiated ----"
    # Send a server chat message to notify players of the imminent shutdown
    
    if [ "$with_restart" = "true" ]; then
      send_rcon_command "ServerChat Server shutdown initiated for restart. Saving the world..."
    else
      send_rcon_command "ServerChat Immediate server shutdown initiated. Saving the world..."
    fi

    echo "Saving the world..."
    send_rcon_command "saveworld"

    echo "Waiting a few seconds before checking for save completion..."
    sleep 5

    echo "Waiting for save to complete..."
    while ! save_complete_check; do
      sleep 5
    done

    echo "World saved. Shutting down the server..."

    # Attempt to gracefully stop the server using RCON command if available
    send_rcon_command "DoExit"

    # Wait a moment to allow the server to shut down gracefully
    sleep 10

    # Wait for "Server stopped" message in logs with a timeout
    local wait_time=0
    local max_wait_time=60
    echo "Waiting for server to fully stop..."
    while ! server_stopped_check && [ $wait_time -lt $max_wait_time ]; do
      sleep 5
      wait_time=$((wait_time + 5))
      echo "Still waiting for server to stop... ($wait_time seconds elapsed)"
    done

    # Create the shutdown complete flag file to signal to POK-manager.sh that
    # the shutdown sequence is complete and it's safe to stop the container
    touch "$SHUTDOWN_COMPLETE_FLAG"

    # If the server hasn't stopped, force kill the process
    if is_process_running; then
      local pid=$(cat "$PID_FILE")
      echo "Force stopping server process (PID: $pid)..."
      kill -9 $pid
    fi
    
    # Clean up any Wine/Proton processes to free resources
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    
    # Perform additional cleanup to free disk space
    echo "Cleaning up temporary files to free disk space..."
    # Clean SteamCMD temporary files
    rm -rf /opt/steamcmd/Steam/logs/* 2>/dev/null || true
    # Clean Wine/Proton temporary files
    rm -rf "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Temp"/* 2>/dev/null || true
    # Clean temporary files in /tmp
    rm -f /tmp/*.log 2>/dev/null || true
    rm -f /tmp/ark_* 2>/dev/null || true
    rm -f /tmp/launch_output.log 2>/dev/null || true
    
    echo "---- Server shutdown complete ----"
  else
    echo "Server appears to be not running, no shutdown action taken."
    # Create the flag anyway to ensure POK-manager.sh can proceed
    touch "$SHUTDOWN_COMPLETE_FLAG"
  fi
}

# Function for scheduled shutdown with countdown
initiate_shutdown() {
  local duration_in_minutes

  if [ -z "$1" ]; then
    # When called directly (not from rcon_interface.sh), we need to prompt for input
    # Only do this when run interactively, not from scripts
    if [ -t 0 ]; then  # Check if stdin is a terminal
      while true; do
        echo -n "Enter countdown duration in minutes (or type 'cancel' to return to main menu): "
        read input

        if [[ "$input" =~ ^[0-9]+$ ]]; then
          duration_in_minutes=$input
          break
        elif [[ "$input" == "cancel" ]]; then
          echo "Shutdown cancelled. Returning to main menu."
          return 1
        else
          echo "Invalid input. Please enter a number or 'cancel'."
        fi
      done
    else
      # Non-interactive mode with missing parameter - return error
      echo "Error: Shutdown command requires a duration in minutes."
      echo "Example usage: -shutdown 5   (This will schedule a shutdown in 5 minutes)"
      return 1
    fi
  else
    # Validate the parameter is a positive number
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid duration: $1. Must be a positive number."
      echo "Example usage: -shutdown 5   (This will schedule a shutdown in 5 minutes)" 
      return 1
    fi
    duration_in_minutes=$1
  fi

  # Check if we're using the enhanced display from rcon_interface.sh
  if [ -f "/tmp/enhanced_shutdown_display" ]; then
    # Skip the countdown display since it's already being handled by rcon_interface.sh
    # Just execute the shutdown logic
    
    # Send a final notification
    if [ "${API_CONTAINER_RESTART}" = "TRUE" ]; then
      send_rcon_command "ServerChat Server is restarting NOW! Saving world data..."
    else
      send_rcon_command "ServerChat Server is shutting down NOW! Saving world data..."
    fi
    
    # Save the world
    echo "Saving world data..."
    send_rcon_command "saveworld"
    
    # Wait for the save to complete
    echo "Waiting for save completion..."
    local save_wait=0
    local save_wait_max=60
    
    while [ $save_wait -lt $save_wait_max ] && ! save_complete_check; do
      sleep 2
      save_wait=$((save_wait + 2))
    done
    
    # Execute the shutdown
    echo "Sending shutdown command to server..."
    send_rcon_command "DoExit"
    
    # Wait for the server to stop
    echo "Waiting for server to exit..."
    local stop_wait=0
    local max_stop_wait=60
    
    while [ $stop_wait -lt $max_stop_wait ] && ! server_stopped_check; do
      sleep 2
      stop_wait=$((stop_wait + 2))
    done
    
    # Create the shutdown complete flag
    touch "$SHUTDOWN_COMPLETE_FLAG"
    
    # Return early - we're done with the shutdown
    return 0
  fi

  # Original countdown display logic - only used when not being called from rcon_interface.sh
  local total_seconds=$((duration_in_minutes * 60))
  local seconds_remaining=$total_seconds
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spinner_idx=0
  local status_color="\033[1;36m" # Cyan for status
  local time_color="\033[1;33m" # Yellow for time
  local reset_color="\033[0m"
  local success_color="\033[1;32m" # Green for success messages
  local warning_color="\033[1;33m" # Yellow for warnings
  local action_color="\033[1;35m" # Magenta for action status

  # Clear any existing shutdown flag to start fresh
  rm -f "$SHUTDOWN_COMPLETE_FLAG"

  # For API container restart, use a modified message
  local shutdown_message="Server shutting down in"
  local op_text="Shutting down"
  if [ "${API_CONTAINER_RESTART}" = "TRUE" ]; then
    shutdown_message="Server restarting in"
    op_text="Restarting"
    echo -e "${status_color}Server restart in progress...${reset_color}"
  else
    echo -e "${status_color}Server shutdown in progress...${reset_color}"
  fi
  
  echo "Press Ctrl+C to exit this display (process will continue in background)"
  
  # First notification always happens at the start
  if [ "${SKIP_INITIAL_NOTIFICATION}" != "TRUE" ]; then
    send_rcon_command "ServerChat $shutdown_message $duration_in_minutes minute(s)"
  fi
  
  # Track when we last sent a notification to avoid duplicates
  local last_notification_time=$seconds_remaining
  local last_notification_point=""
  
  # Main countdown loop
  while [ $seconds_remaining -gt 0 ]; do
    local minutes_remaining=$((seconds_remaining / 60))
    local seconds_in_minute=$((seconds_remaining % 60))
    
    # Check if this is a notification point
    local send_notification=false
    local notification_message=""
    local current_point=""
    
    # 5-minute intervals for both visual highlights and notifications
    if [ $minutes_remaining -ge 5 ] && [ $seconds_in_minute -eq 0 ] && [ $((minutes_remaining % 5)) -eq 0 ]; then
      current_point="${minutes_remaining}m"
      if [ $seconds_remaining -lt $last_notification_time ]; then
        notification_message="$minutes_remaining minutes"
        send_notification=true
      fi
    # 3-minute mark
    elif [ $minutes_remaining -eq 3 ] && [ $seconds_in_minute -eq 0 ]; then
      current_point="3m"
      if [ $seconds_remaining -lt $last_notification_time ]; then
        notification_message="3 minutes"
        send_notification=true
      fi
    # 1-minute mark
    elif [ $minutes_remaining -eq 1 ] && [ $seconds_in_minute -eq 0 ]; then
      current_point="1m"
      if [ $seconds_remaining -lt $last_notification_time ]; then
        notification_message="1 minute"
        send_notification=true
      fi
    # 30-second mark
    elif [ $minutes_remaining -eq 0 ] && [ $seconds_in_minute -eq 30 ]; then
      current_point="30s"
      if [ $seconds_remaining -lt $last_notification_time ]; then
        notification_message="30 seconds"
        send_notification=true
      fi
    # Final 10 seconds
    elif [ $minutes_remaining -eq 0 ] && [ $seconds_in_minute -le 10 ] && [ $seconds_in_minute -gt 0 ]; then
      current_point="${seconds_in_minute}s"
      notification_message="$seconds_in_minute second(s)"
      send_notification=true
    fi
    
    # Send the notification if needed
    if [ "$send_notification" = "true" ]; then
      send_rcon_command "ServerChat $shutdown_message $notification_message"
      last_notification_time=$seconds_remaining
      echo -e "\r${success_color}✓${reset_color} Server notification sent: ${time_color}${current_point}${reset_color} remaining          "
      echo ""  # Add a newline for readability
    fi
    
    # If we hit a notification point that's different from the last one, log it
    if [ -n "$current_point" ] && [ "$current_point" != "$last_notification_point" ] && [ "$send_notification" = "false" ]; then
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
    printf "\r${status_color}%s${reset_color} ${action_color}%s:${reset_color} ${time_color}ETA: %-8s${reset_color}" "$current_spinner" "$op_text" "$eta_display"
    
    sleep 1
    ((seconds_remaining--))
  done

  # Show completion message
  echo -e "\r${success_color}✓${reset_color} ${action_color}${op_text}:${reset_color} ${time_color}Countdown complete!${reset_color}                 "
  
  # Final message and save world
  echo -e "\n${status_color}Starting server shutdown process...${reset_color}"
  
  # Begin the shutdown with more detailed progress information
  echo "Sending final notification to all players..."
  if [ "${API_CONTAINER_RESTART}" = "TRUE" ]; then
    send_rcon_command "ServerChat Server is restarting NOW! Saving world data..."
  else
    send_rcon_command "ServerChat Server is shutting down NOW! Saving world data..."
  fi
  
  # Wait for shutdown with phase-based status display
  local phase="saving"
  echo -e "${status_color}Beginning world save...${reset_color}"
  send_rcon_command "saveworld"
  
  # Show a spinner while waiting for save
  local save_wait=0
  local save_wait_max=120  # 2 minutes max waiting for save
  local save_complete=false
  
  while [ $save_wait -lt $save_wait_max ]; do
    current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    # Update the progress based on the phase
    if [ $save_wait -le 30 ]; then
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 1/3:${reset_color} Saving world data... " "$current_spinner"
    elif [ $save_wait -le 60 ] && [ "$phase" = "saving" ]; then
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 1/3:${reset_color} World save in progress... " "$current_spinner"
    fi
    
    # Check if save is complete
    if save_complete_check; then
      save_complete=true
      echo -e "\r${success_color}✓${reset_color} World save completed successfully!                         "
      echo ""  # Add a newline for readability
      phase="shutdown"
      break
    fi
    
    sleep 1
    ((save_wait++))
  done
  
  if [ "$save_complete" = "false" ]; then
    echo -e "\r${warning_color}⚠️ World save timeout - proceeding with shutdown anyway${reset_color}"
    echo ""  # Add a newline for readability
    phase="shutdown"
  fi
  
  echo "Sending server shutdown command..."
  send_rcon_command "DoExit"
  
  # Wait for "Server stopped" message with a visual spinner
  echo -e "${status_color}Waiting for server processes to terminate...${reset_color}"
  
  local wait_time=0
  local max_wait_time=60
  local server_stopped=false
  
  while [ $wait_time -lt $max_wait_time ]; do
    current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    if [ $wait_time -le 30 ]; then
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 2/3:${reset_color} Server shutdown in progress... " "$current_spinner"
    else
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 2/3:${reset_color} Waiting for processes to exit... " "$current_spinner"
    fi
    
    if server_stopped_check; then
      server_stopped=true
      echo -e "\r${success_color}✓${reset_color} Server shutdown confirmed in logs                          "
      echo ""  # Add a newline for readability
      phase="cleanup"
      break
    fi
    
    sleep 2
    wait_time=$((wait_time + 2))
  done
  
  if [ "$server_stopped" = "false" ]; then
    echo -e "\r${warning_color}⚠️ Server shutdown timeout - checking process state${reset_color}"
    echo ""  # Add a newline for readability
    phase="cleanup"
  fi
  
  # Create shutdown complete flag to signal POK-manager.sh
  touch "$SHUTDOWN_COMPLETE_FLAG"
  
  # Final cleanup phase
  echo -e "${status_color}Performing final cleanup...${reset_color}"
  
  if [ -f "$PID_FILE" ]; then
    echo "Removing server PID file..."
    rm -f "$PID_FILE"
  fi
  
  # Final process cleanup
  wait_time=0
  local max_final_wait=30
  local cleanup_done=false
  
  while is_process_running && [ $wait_time -lt $max_final_wait ]; do
    current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    printf "\r${status_color}%s${reset_color} ${action_color}Phase 3/3:${reset_color} Cleaning up processes... " "$current_spinner"
    
    sleep 2
    wait_time=$((wait_time + 2))
  done
  
  if is_process_running; then
    echo -e "\r${warning_color}⚠️ Some processes still running - forcing termination${reset_color}"
    
    # Force kill any remaining server processes
    echo "Force stopping remaining server processes..."
    local pid=$(ps aux | grep -E "AsaApiLoader.exe|ArkAscendedServer.exe" | grep -v grep | awk '{print $2}' | head -1)
    if [ -n "$pid" ]; then
      kill -9 $pid
      sleep 2
    fi
  else
    echo -e "\r${success_color}✓${reset_color} All server processes terminated successfully           "
  fi
  
  # Final status message for user
  echo ""
  if [ "${API_CONTAINER_RESTART}" = "TRUE" ]; then
    echo -e "${success_color}✓ SERVER RESTART SEQUENCE COMPLETED${reset_color}"
    echo -e "${status_color}Ready for container restart${reset_color}"
  else
    echo -e "${success_color}✓ SERVER SHUTDOWN COMPLETED${reset_color}"
  fi
}

# Check if this script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Check for command line arguments
  if [[ "$1" == "restart" ]]; then
    shutdown_handler true
  elif [[ "$1" == "container-stop" ]]; then
    safe_container_stop
  else
    shutdown_handler false
  fi
fi
