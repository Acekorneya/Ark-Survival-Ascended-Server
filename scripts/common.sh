#!/bin/bash

# Define ARK server and Proton environment variables
USERNAME=anonymous
APPID=2430930
ASA_DIR="/home/pok/arkserver"
PERSISTENT_ACF_FILE="$ASA_DIR/appmanifest_$APPID.acf"
STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/${APPID}"
STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
EOS_FILE="$ASA_DIR/eos_cred_file"
PID_FILE="/home/pok/${INSTANCE_NAME}_ark_server.pid"
# RCON connection details
RCON_HOST="localhost"
RCON_PORT=${RCON_PORT} # Default RCON port if not set in docker compose
RCON_PASSWORD=${SERVER_ADMIN_PASSWORD} # Server admin password used as RCON password
export STEAM_COMPAT_DATA_PATH=${STEAM_COMPAT_DATA_PATH}
export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAM_COMPAT_CLIENT_INSTALL_PATH}

# check if the server is running
is_process_running() {
  local display_message=${1:-false} # Default to not displaying the message

  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE")
    if ps -p $pid >/dev/null 2>&1; then
      if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "ARK server process (PID: $pid) is running."
      fi
      return 0
    else
      echo "Server process (PID: $pid) is not running."
      return 1
    fi
  else
    echo "PID file not found."
    return 1
  fi
}

# Function to check if server is updating
is_server_updating() {
  if [ -f "$ASA_DIR/updating.flag" ]; then
    return 0
  else
    return 1
  fi
}

# Function to clean and format MOD_IDS
clean_format_mod_ids() {
  if [ -n "$MOD_IDS" ]; then
    MOD_IDS=$(echo "$MOD_IDS" | tr -d '"' | tr -d "'" | tr -d ' ')
  fi
}

# Function to validate SERVER_PASSWORD
validate_server_password() {
  if [ -n "$SERVER_PASSWORD" ] && ! [[ "$SERVER_PASSWORD" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "ERROR: The server password must contain only numbers or characters."
    exit 1
  fi
}

# Function to get the build ID from the appmanifest.acf file
get_build_id_from_acf() {
  if [[ -f "$PERSISTENT_ACF_FILE" ]]; then
    local build_id=$(grep -E "^\s+\"buildid\"\s+" "$PERSISTENT_ACF_FILE" | grep -o '[[:digit:]]*')
    echo "$build_id"
  else
    echo "error: appmanifest.acf file not found"
  fi
}

# Function to get the current build ID from SteamCMD API
get_current_build_id() {
  local build_id=$(curl -sX GET "https://api.steamcmd.net/v1/info/$APPID" | jq -r ".data.\"$APPID\".depots.branches.public.buildid")
  echo "$build_id"
}
# Execute initialization functions
clean_format_mod_ids
validate_server_password
