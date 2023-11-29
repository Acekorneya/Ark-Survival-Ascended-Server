#!/bin/bash

PID_FILE="/usr/games/ark_server.pid"
LAUNCH_SCRIPT="/usr/games/scripts/launch_ASA.sh"
INITIAL_STARTUP_DELAY=120  # Delay in seconds before starting the monitoring

# RCON configuration
RCON_HOST="localhost"
RCON_PORT=${RCON_PORT}
RCON_PASSWORD=${SERVER_ADMIN_PASSWORD}
RESTART_NOTICE_MINUTES=${RESTART_NOTICE_MINUTES:-30}  # Default to 30 minutes if not set

# Send RCON command
send_rcon_command() {
    rcon-cli --host $RCON_HOST --port $RCON_PORT --password $RCON_PASSWORD "$1"
}

# Notify players with improved countdown logic
notify_players_for_restart() {
    local minutes_remaining=$RESTART_NOTICE_MINUTES
    while [ $minutes_remaining -gt 0 ]; do
        if [ $minutes_remaining -le 1 ]; then
            # When only 1 minute or less is remaining, start the final countdown
            break
        else
            # Send notification at 5-minute intervals
            if [ $((minutes_remaining % 5)) -eq 0 ] || [ $minutes_remaining -eq $RESTART_NOTICE_MINUTES ]; then
                send_rcon_command "ServerChat Server restarting in $minutes_remaining minute(s) for updates."
            fi
            sleep 60
            ((minutes_remaining--))
        fi
    done

    # Final 60 seconds countdown, sending a notification every second
    local seconds_remaining=60
    while [ $seconds_remaining -gt 0 ]; do
        if [ $seconds_remaining -le 10 ]; then
            # Notify every second for the last 10 seconds
            send_rcon_command "ServerChat Server restarting in $seconds_remaining second(s) for updates."
        fi
        sleep 1
        ((seconds_remaining--))
    done

    send_rcon_command "saveworld"
}

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

# Restart the ARK server
restart_server() {
    echo "Gracefully shutting down the ARK server..."
    send_rcon_command "DoExit"

    # Wait for a bit to ensure the server has completely shut down
    sleep 30

    echo "Starting the ARK server..."
    bash "$LAUNCH_SCRIPT"
}

# Wait for the initial startup before monitoring
sleep $INITIAL_STARTUP_DELAY

# Monitoring loop
while true; do
    # Check if the server is currently updating (based on the presence of the updating.flag file)
    if [ -f "/usr/games/updating.flag" ]; then
        echo "Update/Installation in progress, waiting for it to complete..."
        sleep 60
        continue  # Skip the rest of this loop iteration
    fi

    if [ "${UPDATE_SERVER}" = "TRUE" ]; then
        # Check for updates at the interval specified by CHECK_FOR_UPDATE_INTERVAL
        current_time=$(date +%s)
        last_update_check_time=${last_update_check_time:-0}
        update_check_interval_seconds=$((CHECK_FOR_UPDATE_INTERVAL * 3600))

        if (( current_time - last_update_check_time > update_check_interval_seconds )); then
            if /usr/games/scripts/POK_Update_Monitor.sh; then
                notify_players_for_restart
                restart_server
            fi
            last_update_check_time=$current_time
        fi
    fi

    # Restart the server if it's not running and not currently updating
    if ! is_process_running && ! is_server_updating; then
        restart_server
    fi

    sleep 60  # Short sleep to prevent high CPU usage
done
