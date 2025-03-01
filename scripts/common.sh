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
RCON_PORT=${RCON_PORT} # Default RCON port if not set in docker-compose
RCON_PASSWORD=${SERVER_ADMIN_PASSWORD} # Server admin password used as RCON password
RCON_PATH="/usr/local/bin/rcon-cli" # Path to the RCON executable (installed in Dockerfile)
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

# Function to detect and clear stale update flags
# This helps prevent issues if update process was interrupted
check_stale_update_flag() {
  local flag_file="$ASA_DIR/updating.flag"
  local max_age_hours=${1:-6} # Default to 6 hours for stale flag
  
  if [ -f "$flag_file" ]; then
    # Get current time and file modification time in seconds since epoch
    local current_time=$(date +%s)
    local file_mod_time=$(stat -c %Y "$flag_file")
    local age_seconds=$((current_time - file_mod_time))
    local age_hours=$((age_seconds / 3600))
    
    # If the flag file is older than the threshold, consider it stale
    if [ $age_hours -ge $max_age_hours ]; then
      echo "WARNING: Detected stale updating.flag file (last modified $age_hours hours ago)"
      echo "This usually happens when an update process was interrupted."
      echo "Removing stale flag to allow server to start."
      rm -f "$flag_file"
      return 0 # Flag was stale and removed
    else
      echo "Update flag exists and is recent ($age_hours hours old). Assuming update is in progress."
      return 1 # Flag exists and is not stale
    fi
  fi
  
  return 2 # No flag found
}

# Function to manually clear update flag
clear_update_flag() {
  local flag_file="$ASA_DIR/updating.flag"
  
  if [ -f "$flag_file" ]; then
    echo "Removing updating.flag file..."
    rm -f "$flag_file"
    echo "Flag file removed successfully."
    return 0
  else
    echo "No updating.flag file found. Nothing to remove."
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
