#!/bin/bash

# RCON connection details
RCON_HOST="localhost"
RCON_PORT=${RCON_PORT}  # Default RCON port if not set in docker-compose
RCON_PASSWORD=${SERVER_ADMIN_PASSWORD}  # Server admin password used as RCON password

# Check if RCON_PORT and RCON_PASSWORD are set
if [ -z "$RCON_PORT" ] || [ -z "$RCON_PASSWORD" ]; then
    echo "RCON_PORT and SERVER_ADMIN_PASSWORD must be set."
    exit 1
fi


# Function to send RCON command
send_rcon_command() {
    rcon-cli --host $RCON_HOST --port $RCON_PORT --password $RCON_PASSWORD "$1"
}

# Function for shutdown sequence
initiate_restart() {
    local duration_in_minutes

    if [ -z "$1" ]; then
        while true; do
            echo -n "Enter countdown duration in minutes (or type 'cancel' to return to main menu): "
            read input

            if [[ "$input" =~ ^[0-9]+$ ]]; then
                duration_in_minutes=$input
                break
            elif [[ "$input" == "cancel" ]]; then
                echo "Restart cancelled. Returning to main menu."
                return
            else
                echo "Invalid input. Please enter a number or 'cancel'."
            fi
        done
    else
        if ! [[ "$1" =~ ^[0-9]+$ ]]; then
            echo "Invalid duration: $1. Must be a number."
            return
        fi
        duration_in_minutes=$1
    fi

    local total_seconds=$((duration_in_minutes * 60))
    local seconds_remaining=$total_seconds

    while [ $seconds_remaining -gt 0 ]; do
        local minutes_remaining=$((seconds_remaining / 60))

        if [ $seconds_remaining -le 10 ]; then
            # Notify every second for the last 10 seconds
            send_rcon_command "ServerChat Server restarting in $seconds_remaining second(s)"
        elif [ $((seconds_remaining % 300)) -eq 0 ] || [ $seconds_remaining -eq $total_seconds ]; then
            # Notify at 5 minute intervals
            send_rcon_command "ServerChat Server restarting in $minutes_remaining minute(s)"
        fi

        sleep 1
        ((seconds_remaining--))
    done

    send_rcon_command "saveworld"
    echo "World saved. Restarting the server..."
    send_rcon_command "DoExit"
}

# Handle automated restart or custom command if arguments are provided
if [ "$1" == "-restart" ] && [ -n "$2" ]; then
    echo "Automated restart initiated with a $2 minute countdown."
    initiate_restart $2
    exit 0
elif [ "$1" == "-custom" ] && [ -n "$2" ]; then
    echo "Executing custom RCON command: $2"
    send_rcon_command "$2"
    exit 0
fi

# Interactive mode
echo "Connected to ARK Server RCON at $RCON_HOST:$RCON_PORT"
echo "Type 'exit' to leave RCON interface."

# Display available commands
echo "Available Commands:"
echo "  saveworld - Save the game world"
echo "  restart - Initiate a server restart with a countdown"
echo "  chat - Send a message to the server"
echo "  custom - Send a custom RCON command"
echo "  exit - Exit the RCON interface"
echo ""

# Main interface loop
while true; do
    echo -n "RCON> "
    read command

    case $command in
        saveworld)
            send_rcon_command "saveworld"
            echo "World save command issued."
            ;;
        restart)
            initiate_restart
            ;;
        chat)
            echo -n "Enter your message: "
            read message
            send_rcon_command "ServerChat $message"
            echo "Message sent to the server."
            ;;
        custom)
            echo -n "Enter custom RCON command: "
            read custom_command
            send_rcon_command "$custom_command"
            ;;
        exit)
            break
            ;;
        *)
            echo "Unknown command. Please try again."
            ;;
    esac
done

echo "Exiting RCON interface."