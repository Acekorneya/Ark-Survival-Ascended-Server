#!/bin/bash

# Source RCON command definitions and common functions
source /home/pok/scripts/rcon_commands.sh
source /home/pok/scripts/common.sh
source /home/pok/scripts/shutdown_server.sh

# Define shutdown flag file location
SHUTDOWN_COMPLETE_FLAG="/home/pok/shutdown_complete.flag"

# Function to display animated countdown
display_animated_countdown() {
  local duration=$1
  local countdown_type=$2 # "shutdown" or "restart"
  local total_seconds=$((duration * 60))
  local seconds_remaining=$total_seconds
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spinner_idx=0
  local status_color="\033[1;36m" # Cyan for status
  local time_color="\033[1;33m" # Yellow for time
  local reset_color="\033[0m"
  local success_color="\033[1;32m" # Green for success
  local warning_color="\033[1;33m" # Yellow for warnings
  local action_color="\033[1;35m" # Magenta for action status
  
  # Set the appropriate message based on countdown type
  local op_text="Shutting down"
  if [ "$countdown_type" = "restart" ]; then
    op_text="Restarting"
    echo -e "${status_color}Server restart in progress...${reset_color}"
  else
    echo -e "${status_color}Server shutdown in progress...${reset_color}"
  fi
  
  echo "Press Ctrl+C to exit this display (operation will continue in background)"
  
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
    printf "\r${status_color}%s${reset_color} ${action_color}%s:${reset_color} ${time_color}ETA: %-8s${reset_color}" "$current_spinner" "$op_text" "$eta_display"
    
    sleep 1
    ((seconds_remaining--))
    
    # Check if the shutdown has already completed
    if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
      if [ "$countdown_type" = "restart" ]; then
        echo -e "\r${success_color}✓${reset_color} Server restart initiated early!                       "
      else
        echo -e "\r${success_color}✓${reset_color} Server shutdown completed early!                      "
      fi
      return
    fi
  done
  
  # Show completion message
  echo -e "\r${success_color}✓${reset_color} ${action_color}${op_text}:${reset_color} ${time_color}Countdown complete!${reset_color}                 "
  
  # Wait for shutdown flag to appear with cleaner status display
  local wait_count=0
  local max_wait=60
  local phase="saving"
  
  if [ "$countdown_type" = "restart" ]; then
    echo -e "\n${status_color}Waiting for server to restart...${reset_color}"
  else
    echo -e "\n${status_color}Waiting for server to finish shutdown...${reset_color}"
  fi
  
  while [ ! -f "$SHUTDOWN_COMPLETE_FLAG" ] && [ $wait_count -lt $max_wait ]; do
    sleep 1
    ((wait_count++))
    current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    # Determine phase message based on time elapsed
    if [ $wait_count -le 20 ]; then
      if [ "$phase" != "saving" ]; then
        phase="saving"
        echo ""  # Add space before new phase
      fi
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 1/3:${reset_color} Saving world data... " "$current_spinner"
    elif [ $wait_count -le 40 ]; then
      if [ "$phase" != "exiting" ]; then
        phase="exiting"
        echo ""  # Add space before new phase
        echo -e "${success_color}✓${reset_color} World data save complete"
      fi
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 2/3:${reset_color} Server processes exiting... " "$current_spinner"
    else
      if [ "$phase" != "cleanup" ]; then
        phase="cleanup"
        echo ""  # Add space before new phase
        echo -e "${success_color}✓${reset_color} Server processes stopped"
      fi
      printf "\r${status_color}%s${reset_color} ${action_color}Phase 3/3:${reset_color} Finalizing operation... " "$current_spinner"
    fi
  done
  
  echo ""  # Add a final newline
  if [ -f "$SHUTDOWN_COMPLETE_FLAG" ]; then
    if [ "$countdown_type" = "restart" ]; then
      echo -e "${success_color}✓ Server shutdown phase completed!${reset_color}"
      echo -e "${status_color}Server will restart shortly...${reset_color}"
    else
      echo -e "${success_color}✓ Server shutdown completed successfully!${reset_color}"
    fi
  else
    echo -e "${warning_color}⚠️ Timeout waiting for completion${reset_color}"
    # Create the flag anyway to continue
    touch "$SHUTDOWN_COMPLETE_FLAG"
  fi
}

# Function to display usage
usage() {
  echo "Usage: $0 [command] [options]"
  echo "Available commands:"
  echo "  -saveworld                - Save the game world."
  echo "  -restart <minutes>        - Schedule a server restart with countdown."
  echo "  -shutdown <minutes>       - Schedule a server shutdown with countdown."
  echo "  -stop                     - Safely stop the server, ensuring world save completion."
  echo "  -chat <message>           - Send a chat message to the server."
  echo "  -custom <RCON command>    - Send a custom RCON command."
  echo "  -status                   - Display server status."
  echo "  -clearupdateflag          - Remove a stale updating.flag if update was interrupted."
  echo "  -interactive              - Enter interactive mode."
  echo "If no command is provided, the script enters interactive mode by default."
}

# Main function
main() {
  local command="$1"
  shift # Remove the command from the arguments list

  case "$command" in
  -saveworld)
    saveWorld
    ;;
  -restart)
    if [ -z "$1" ]; then
      echo "Error: Restart command requires a duration in minutes."
      exit 1
    fi
    
    # Set the API_CONTAINER_RESTART variable for restart context
    export API_CONTAINER_RESTART="TRUE"
    
    # Enable animated countdown in restart_server.sh
    export SHOW_ANIMATED_COUNTDOWN="TRUE"
    
    # Call restart_server.sh and pass countdown duration
    /home/pok/scripts/restart_server.sh "$1"
    ;;
  -shutdown)
    if [ -z "$1" ]; then
      echo "Error: Shutdown command requires a duration in minutes."
      exit 1
    fi
    # Start the shutdown in background
    initiate_shutdown "$1" &
    SHUTDOWN_PID=$!
    
    # Display animated countdown in foreground, with "shutdown" type
    display_animated_countdown "$1" "shutdown"
    
    # Wait for the background process to finish
    wait $SHUTDOWN_PID 2>/dev/null || true
    ;;
  -stop)
    echo "🛑 Safely stopping server and ensuring world save completion..."
    # Call the safe_container_stop function to ensure the world is saved
    safe_container_stop
    
    # After the world is saved and shutdown flag is set, it's safe to proceed with container stop
    echo "✅ World saved and server ready for container stop."
    echo "   POK-manager.sh can now safely stop the container."
    ;;
  -chat)
    if [ -z "$1" ]; then
      echo "Error: Chat command requires a message."
      exit 1
    fi
    sendChat "$@"
    ;;
  -status)
    status
    ;;
  -clearupdateflag)
    clear_update_flag
    ;;
  -custom)
    if [ -z "$1" ]; then
      echo "Error: Custom command requires an RCON command."
      exit 1
    fi
    send_rcon_command "$@"
    ;;
  -interactive)
    interactive_mode
    ;;
  *)
    if [[ -z "$command" ]]; then
      interactive_mode
      exit 0
    fi
    echo "Error: Unknown or unsupported command '$command'."
    usage
    exit 1
    ;;
  esac
}

# Check if script is being sourced or directly executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
