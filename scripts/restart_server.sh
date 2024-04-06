#!/bin/bash
source /home/pok/scripts/common.sh
source /home/pok/scripts/shutdown_server.sh

RESTART_MODE="$1" # Immediate or countdown
RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-5}" # Default to 5 minutes for countdown

shutdown_and_restart() {
  if is_process_running; then
    echo "Initiating server shutdown..."
    shutdown_handler # Call the shutdown function directly instead of script

    # Wait for the server process to terminate
    echo "Waiting for the server to fully shutdown..."
    while is_process_running; do
      echo "Server process still running. Waiting..."
      sleep 5 
    done
    echo "Server has been shutdown."
  else
    echo "Server process not found. Proceeding to launch..."
  fi

  # Regardless of the server's previous state, remove the PID file to avoid conflicts and proceed with the launch
  rm -f "$PID_FILE"
  echo "PID file removed if it existed."
  
  echo "Proceeding to restart server..."
  /home/pok/scripts/init.sh
  echo "Server restart initiated."
}

# Check if the server is currently updating (based on the presence of the updating.flag file)
if [ -f "/home/pok/updating.flag" ]; then
  echo "Update in progress, waiting for it to complete before restarting..."
  while [ -f "/home/pok/updating.flag" ]; do
    sleep 10
  done
fi

if [ "$RESTART_MODE" == "immediate" ]; then
  echo "Attempting immediate restart..."
  shutdown_and_restart
else
  echo "Scheduled restart with a countdown of $RESTART_NOTICE_MINUTES minutes..."
  initiate_restart "$RESTART_NOTICE_MINUTES"
  # Ensure PID file is removed after countdown to avoid any potential issue during launch
  rm -f "$PID_FILE"
  echo "PID file removed if it existed."
fi