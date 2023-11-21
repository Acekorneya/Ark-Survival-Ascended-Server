#!/bin/bash

PID_FILE="/usr/games/ark_server.pid"
LAUNCH_SCRIPT="/usr/games/scripts/launch_ASA.sh"
INITIAL_STARTUP_DELAY=120  # Delay in seconds


# Function to check if the server process is running
is_process_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p $pid > /dev/null 2>&1; then
            if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
                echo "ARK server process (PID: $pid) is running."
            fi
            return 0
        else
            echo "ARK server process (PID: $pid) is not running."
            return 1
        fi
    else
        echo "PID file not found."
        return 1
    fi
}
# Function to check if server is updating
is_server_updating() {
    if [ -f "/usr/games/updating.flag" ]; then
        echo "Server is currently updating."
        return 0
    else
        return 1
    fi
}
# Function to restart the server
restart_server() {
    echo "Restarting the ARK server..."
    bash "$LAUNCH_SCRIPT"
}

# Wait for the initial startup before monitoring
sleep $INITIAL_STARTUP_DELAY

# Monitoring loop
while true; do
    if ! is_process_running && ! is_server_updating; then
        restart_server
    fi
    sleep 60
done
