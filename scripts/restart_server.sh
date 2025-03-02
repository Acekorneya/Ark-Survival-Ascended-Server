#!/bin/bash
source /home/pok/scripts/common.sh
source /home/pok/scripts/shutdown_server.sh

RESTART_MODE="$1" # Immediate or countdown
RESTART_NOTICE_MINUTES="${RESTART_NOTICE_MINUTES:-5}" # Default to 5 minutes for countdown

# Function to ensure the Wine environment is clean before a restart
cleanup_wine_environment() {
  echo "Cleaning up Wine/Proton environment before restart..."
  
  # Kill any stray processes that might interfere with restart
  pkill -f "Xvfb" >/dev/null 2>&1 || true
  pkill -f "wineserver" >/dev/null 2>&1 || true
  pkill -f "wine" >/dev/null 2>&1 || true
  
  # Give processes time to terminate
  sleep 3
  
  # Force kill any remaining processes if necessary
  pkill -9 -f "Xvfb" >/dev/null 2>&1 || true
  pkill -9 -f "wineserver" >/dev/null 2>&1 || true
  pkill -9 -f "wine" >/dev/null 2>&1 || true
  
  # Clean up any X11 sockets
  if [ -d "/tmp/.X11-unix" ]; then
    echo "Cleaning up X11 sockets..."
    rm -rf /tmp/.X11-unix/* 2>/dev/null || true
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
  fi
  
  # Ensure Wine prefix is in a clean state (optional - can be destructive)
  if [ "${API}" = "TRUE" ]; then
    echo "Ensuring Wine prefix is in clean state for AsaApi..."
    rm -f "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Temp/*" 2>/dev/null || true
  fi
  
  echo "Environment cleanup completed."
}

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
  
  # Additional environment cleanup for API=TRUE mode
  if [ "${API}" = "TRUE" ]; then
    cleanup_wine_environment
  fi
  
  echo "Proceeding to restart server..."
  
  # Attempt to use screen if available, otherwise fall back to basic method
  SCREEN_AVAILABLE=false
  if command -v screen >/dev/null 2>&1; then
    SCREEN_AVAILABLE=true
  else
    # Try to install screen but don't fail if it doesn't work
    echo "Attempting to install screen for better log visibility (optional)..."
    apt-get update -qq && apt-get install -y screen >/dev/null 2>&1
    # Check if installation succeeded
    if command -v screen >/dev/null 2>&1; then
      SCREEN_AVAILABLE=true
      echo "✅ Screen installed successfully!"
    else
      echo "⚠️ Screen installation failed. Will use fallback method instead."
    fi
  fi
  
  # Launch the server differently based on whether screen is available
  if [ "$SCREEN_AVAILABLE" = true ]; then
    # Launch using screen to maintain log visibility
    echo "Starting server in screen session..."
    screen -dmS ark_server bash -c "/home/pok/scripts/init.sh; exec bash"
    echo "Server restart initiated. View logs with: screen -r ark_server"
  else
    # Fallback method - use nohup to run in background while ensuring init.sh runs fully
    echo "Starting server with fallback method (nohup)..."
    nohup /home/pok/scripts/init.sh > /home/pok/logs/restart_console.log 2>&1 &
    echo "Server restart initiated. View logs with: tail -f /home/pok/logs/restart_console.log"
    echo "For detailed server logs once started: tail -f /home/pok/logs/server_console.log"
  fi
}

if [ "$RESTART_MODE" == "immediate" ]; then
  echo "Attempting immediate restart..."
  shutdown_and_restart
else
  echo "Scheduled restart with a countdown of $RESTART_NOTICE_MINUTES minutes..."
  initiate_restart "$RESTART_NOTICE_MINUTES"
  # Ensure PID file is removed after countdown to avoid any potential issue during launch
  rm -f "$PID_FILE"
  echo "PID file removed if it existed."
  
  # Run the actual restart after countdown completes
  if [ "${API}" = "TRUE" ]; then
    cleanup_wine_environment
  fi
  
  echo "Proceeding to restart server after countdown..."
  
  # Use screen to detach the server process while still preserving logs
  if ! command -v screen >/dev/null 2>&1; then
    echo "Installing screen for proper server restart..."
    apt-get update -qq && apt-get install -y screen >/dev/null 2>&1
  fi
  
  # Launch using screen to maintain log visibility
  screen -dmS ark_server bash -c "/home/pok/scripts/init.sh; exec bash"
  
  echo "Server restart initiated. Use 'screen -r ark_server' to view live server output."
fi