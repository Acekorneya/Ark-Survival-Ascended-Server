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

echo "Connected to ARK Server RCON at $RCON_HOST:$RCON_PORT"
echo "Type 'exit' to leave RCON interface."

# Function to send RCON command
send_rcon_command() {
    rcon-cli --host $RCON_HOST --port $RCON_PORT --password $RCON_PASSWORD "$1"
}

# Function for shutdown sequence
# Function for shutdown sequence
initiate_restart() {
    echo -n "Enter countdown duration in minutes: "
    read duration_in_minutes
    duration_in_minutes=${duration_in_minutes:-5}  # Default to 5 minutes if not specified

    # Convert minutes to seconds for countdown
    local duration=$((duration_in_minutes * 60))

    # Start with a minute countdown
    local remaining=$duration
    while [ $remaining -gt 0 ]; do
        local minutes=$((remaining / 60))
        local seconds=$((remaining % 60))
        send_rcon_command "ServerChat Server Restarting in ${minutes} minute(s) and ${seconds} second(s)"

        sleep 60  # Wait for 1 minute before next notification
        let remaining-=60
    done

    send_rcon_command "saveworld"
    echo "World saved. Restarting the server..."

    send_rcon_command "DoExit"
    echo "Server is Restarting. Please wait for a few moments"
}

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