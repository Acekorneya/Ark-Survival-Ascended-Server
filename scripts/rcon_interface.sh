#!/bin/bash

# Source RCON command definitions and common functions
source /home/pok/scripts/rcon_commands.sh
source /home/pok/scripts/common.sh

# Function to display usage
usage() {
  echo "Usage: $0 [command] [options]"
  echo "Available commands:"
  echo "  -saveworld                - Save the game world."
  echo "  -restart <minutes>        - Schedule a server restart with countdown."
  echo "  -shutdown <minutes>       - Schedule a server shutdown with countdown."
  echo "  -chat <message>           - Send a chat message to the server."
  echo "  -custom <RCON command>    - Send a custom RCON command."
  echo "  -status                   - Display server status."
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
    initiate_restart "$1"
    ;;
  -shutdown)
    if [ -z "$1" ]; then
      echo "Error: Restart command requires a duration in minutes."
      exit 1
    fi
    initiate_shutdown "$1"
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
