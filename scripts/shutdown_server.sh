#!/bin/bash

# Source common variables, functions, and the rcon_commands.sh script
source /home/pok/scripts/common.sh
source /home/pok/scripts/rcon_commands.sh

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

# Function to handle graceful shutdown
shutdown_handler() {
  if is_process_running; then
    echo "---- Server shutdown initiated ----"
    # Send a server chat message to notify players of the imminent shutdown
    send_rcon_command "ServerChat Immediate server shutdown initiated. Saving the world..."

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

    # If the server hasn't stopped, force kill the process
    if is_process_running; then
      local pid=$(cat "$PID_FILE")
      echo "Force stopping server process (PID: $pid)..."
      kill -9 $pid
    fi

    echo "---- Server shutdown complete ----"
  else
    echo "Server appears to be not running, no shutdown action taken."
  fi
}

# Check if this script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  shutdown_handler
fi
