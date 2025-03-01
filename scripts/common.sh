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

# Check the lock status with enhanced details about the lock holder
check_lock_status() {
  local lock_file="$ASA_DIR/updating.flag"
  
  if [ -f "$lock_file" ]; then
    echo "Lock file exists:"
    echo "-----------------"
    cat "$lock_file"
    echo "-----------------"
    
    # Check if the lock file contains a PID
    local lock_pid=$(grep -o "PID: [0-9]*" "$lock_file" | cut -d' ' -f2)
    
    if [ -n "$lock_pid" ]; then
      # Check if the process is still running
      if kill -0 "$lock_pid" 2>/dev/null; then
        echo "Process with PID $lock_pid is still running"
        return 0  # Lock is valid
      else
        echo "Process with PID $lock_pid is no longer running"
        echo "This may be a stale lock"
        return 1  # Lock seems stale
      fi
    else
      echo "No PID information found in lock file"
      # Use file age to determine if lock might be stale
      local file_age=$((($(date +%s) - $(stat -c %Y "$lock_file")) / 60))
      echo "Lock file age: $file_age minutes"
      
      if [ $file_age -gt 30 ]; then
        echo "Lock file is older than 30 minutes and might be stale"
        return 1  # Lock seems stale
      else
        echo "Lock file is recent (less than 30 minutes old)"
        return 0  # Assume lock is still valid
      fi
    fi
  else
    echo "No lock file exists"
    return 2  # No lock file
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

# Function to install ArkServerAPI
install_ark_server_api() {
  if [ "${API}" != "TRUE" ]; then
    echo "ArkServerAPI installation skipped (API is not set to TRUE)"
    return 0
  fi

  echo "---- Installing/Updating ArkServerAPI ----"
  
  # Define paths
  local api_dir="${ASA_DIR}/ShooterGame/Binaries/Win64/ArkApi"
  local bin_dir="${ASA_DIR}/ShooterGame/Binaries/Win64"
  local api_tmp="/tmp/arkserverapi.zip"
  local api_version_file="${api_dir}/.api_version"
  local current_api_version=""
  
  # Check if version file exists and get current version
  if [ -f "$api_version_file" ]; then
    current_api_version=$(cat "$api_version_file")
    echo "Current ArkServerAPI version: $current_api_version"
  else
    echo "ArkServerAPI not found, will install for the first time."
    # Create API directory if it doesn't exist
    mkdir -p "$api_dir"
  fi
  
  # Fetch the latest release info from GitHub
  echo "Checking for latest ArkServerAPI version..."
  local latest_release_info=$(curl -s "https://api.github.com/repos/ServersHub/Framework-ArkServerApi/releases/latest")
  local latest_version=$(echo "$latest_release_info" | jq -r '.tag_name')
  local download_url=$(echo "$latest_release_info" | jq -r '.assets[0].browser_download_url')
  
  if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
    echo "ERROR: Failed to fetch latest version information from GitHub."
    return 1
  fi
  
  echo "Latest ArkServerAPI version: $latest_version"
  
  # Check if an update is needed
  if [ "$current_api_version" = "$latest_version" ]; then
    echo "ArkServerAPI is already up-to-date."
    return 0
  fi
  
  echo "Downloading ArkServerAPI $latest_version..."
  
  # Download the latest release
  if ! curl -L -o "$api_tmp" "$download_url"; then
    echo "ERROR: Failed to download ArkServerAPI."
    return 1
  fi
  
  echo "Extracting ArkServerAPI..."
  
  # Backup existing config if it exists
  if [ -d "$api_dir/Plugins" ]; then
    echo "Backing up existing plugins configuration..."
    local backup_dir="${api_dir}_backup_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Find and copy only .json files to preserve configurations
    find "$api_dir/Plugins" -name "*.json" -exec cp --parents {} "$backup_dir" \;
    echo "Plugin configurations backed up to $backup_dir"
  fi
  
  # Extract the API files (preserving existing configuration files)
  unzip -o "$api_tmp" -d "$bin_dir"
  
  # Restore backed up configurations if we have them
  if [ -d "$backup_dir" ]; then
    echo "Restoring plugin configurations..."
    cp -rf "$backup_dir"/* "$api_dir"/ 2>/dev/null || true
    echo "Plugin configurations restored."
  fi
  
  # Remove the temporary ZIP file
  rm -f "$api_tmp"
  
  # Save the new version
  echo "$latest_version" > "$api_version_file"
  
  # Set correct permissions
  chmod -R 755 "$bin_dir/ArkApi"
  
  echo "ArkServerAPI $latest_version installed successfully."
  return 0
}
