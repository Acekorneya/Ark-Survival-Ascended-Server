#!/bin/bash
source /home/pok/scripts/common.sh
source /home/pok/scripts/rcon_commands.sh
source /home/pok/scripts/shutdown_server.sh

# Trap SIGTERM and call shutdown_handler when received
trap shutdown_handler SIGTERM

update_game_user_settings() {
  local ini_file="$ASA_DIR/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini"

  # Check if the file exists
  if [ -f "$ini_file" ]; then
    # Prepare MOTD by escaping newline characters
    local escaped_motd=$(echo "$MOTD" | sed 's/\\n/\\\\n/g')

    # Update or add SERVER_PASSWORD in the ini file
    if [ -n "$SERVER_PASSWORD" ]; then
      if grep -q "^ServerPassword=" "$ini_file"; then
        sed -i "s/^ServerPassword=.*/ServerPassword=$SERVER_PASSWORD/" "$ini_file"
      else
        echo "ServerPassword=$SERVER_PASSWORD" >> "$ini_file"
      fi
    else
      # Remove the password line if SERVER_PASSWORD is not set
      sed -i '/^ServerPassword=/d' "$ini_file"
    fi

    # Remove existing [MessageOfTheDay] section
    sed -i '/^\[MessageOfTheDay\]/,/^$/d' "$ini_file"

    # Handle MOTD based on ENABLE_MOTD value
    if [ "$ENABLE_MOTD" = "TRUE" ]; then
      # Add the new Message of the Day
      echo -e "\n[MessageOfTheDay]\nMessage=$escaped_motd\nDuration=$MOTD_DURATION" >> "$ini_file"
    fi
  else
    echo "GameUserSettings.ini not found."
  fi
}

# Determine the map path based on environment variable
determine_map_path() {
  case "$MAP_NAME" in
  "TheIsland")
    MAP_PATH="TheIsland_WP"
    ;;
  "ScorchedEarth")
    MAP_PATH="ScorchedEarth_WP" 
    ;;
  *)
    # Check if the custom MAP_NAME already ends with '_WP'
    if [[ "$MAP_NAME" == *"_WP" ]]; then
      MAP_PATH="$MAP_NAME"
    else
      MAP_PATH="${MAP_NAME}_WP"
    fi
    echo "Using map: $MAP_PATH"
    ;;
  esac
}

# Find the last "Log file open" entry and return the line number
find_new_log_entries() {
  LOG_FILE="$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
  LAST_ENTRY_LINE=$(grep -n "Log file open" "$LOG_FILE" | tail -1 | cut -d: -f1)
  echo $((LAST_ENTRY_LINE + 1)) # Return the line number after the last "Log file open"
}


start_server() {
  # Fix for Docker Compose exec / Docker exec parsing inconsistencies
  STEAM_COMPAT_DATA_PATH=$(eval echo "$STEAM_COMPAT_DATA_PATH")

  # Check if the log file exists and rename it to archive
  local old_log_file="$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
  if [ -f "$old_log_file" ]; then
    local timestamp=$(date +%F-%T)
    mv "$old_log_file" "${old_log_file}_$timestamp.log"
  fi

  # Initialize server arguments
  local mods_arg=""
  local battleye_arg=""
  local rcon_args=""
  local custom_args=""
  local server_password_arg=""
  local session_name_arg="SessionName=\"${SESSION_NAME}\""

  # Check if MOD_IDS is set and not empty
  if [ -n "$MOD_IDS" ]; then
    mods_arg="-mods=${MOD_IDS}"
  fi
  
  # Initialize the passive mods argument
  local passive_mods_arg=""
  if [ -n "$PASSIVE_MODS" ]; then
    passive_mods_arg="-passivemods=${PASSIVE_MODS}"
  fi
  
  # Set BattlEye flag based on environment variable
  if [ "$BATTLEEYE" = "TRUE" ]; then
    battleye_arg="-UseBattlEye"
  elif [ "$BATTLEEYE" = "FALSE" ]; then
    battleye_arg="-NoBattlEye"
  fi
  
  # Set RCON arguments based on RCON_ENABLED environment variable
  if [ "$RCON_ENABLED" = "TRUE" ]; then
    rcon_args="?RCONEnabled=True?RCONPort=${RCON_PORT}"
  elif [ "$RCON_ENABLED" = "FALSE" ]; then
    rcon_args="?RCONEnabled=False"
  fi

  if [ -n "$CUSTOM_SERVER_ARGS" ]; then
    custom_args="$CUSTOM_SERVER_ARGS"
  fi

  if [ -n "$SERVER_PASSWORD" ]; then
    server_password_arg="?ServerPassword=${SERVER_PASSWORD}"
  fi

  # Construct the full server start command
  local server_command="proton run /home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe $MAP_PATH?listen?$session_name_arg?${rcon_args}${server_password_arg}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD} -Port=${ASA_PORT} -WinLiveMaxPlayers=${MAX_PLAYERS} -clusterid=${CLUSTER_ID} -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs -NotifyAdminCommandsInChat $custom_args $mods_arg $battleye_arg $passive_mods_arg"

  # Start the server using Proton-GE
  echo "Starting server with Proton-GE..."
  bash -c "$server_command" &

  SERVER_PID=$!
  echo "Server process started with PID: $SERVER_PID"

  # Immediate write to PID file
  echo $SERVER_PID > $PID_FILE
  echo "PID $SERVER_PID written to $PID_FILE"

  # Check for the existence of the ShooterGame.log file before tailing
  while [ ! -f "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log" ]; do
    echo "Waiting for ShooterGame.log to be created..."
    sleep 2
  done

  # Now that the file exists, start tailing it to the console
  echo "ShooterGame.log exists, starting to tail."
  tail -f "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log" &
  TAIL_PID=$!
  echo "Tailing ShooterGame.log with PID: $TAIL_PID"

  # Wait for the server to fully start, monitoring the log file
  echo "Waiting for server to start..."
  while true; do
    if [ -f "$LOG_FILE" ] && grep -q "Server started" "$LOG_FILE"; then
      echo "Server started successfully. PID: $SERVER_PID"
      break
    fi
    sleep 10
  done

  # Wait for the server process to exit
  wait $SERVER_PID
  echo "Server stopped."
  # Kill the tail process when the server stops
  kill $TAIL_PID
  echo "Stopped tailing ShooterGame.log."
}


# Main function
main() {
  determine_map_path
  update_game_user_settings
  start_server
}

# Start the main execution
main
