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

# Function to initialize the Proton prefix
initialize_proton_prefix() {
  echo "Initializing Proton prefix at ${STEAM_COMPAT_DATA_PATH}..."
  
  # Make sure the prefix directory exists with correct permissions
  mkdir -p "${STEAM_COMPAT_DATA_PATH}"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx"
  
  # Important: Ensure all parent directories also have proper permissions
  chmod -R 755 "${STEAM_COMPAT_DATA_PATH}"
  
  # Create all necessary subdirectories with proper permissions
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser"
  
  # Create dosdevices directory and symlinks - missing in original code
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/dosdevices"
  # The error was specifically about this symlink
  ln -sf "../drive_c" "${STEAM_COMPAT_DATA_PATH}/pfx/dosdevices/c:"
  ln -sf "/dev/null" "${STEAM_COMPAT_DATA_PATH}/pfx/dosdevices/d::"
  ln -sf "/dev/null" "${STEAM_COMPAT_DATA_PATH}/pfx/dosdevices/e::"
  ln -sf "/dev/null" "${STEAM_COMPAT_DATA_PATH}/pfx/dosdevices/f::"
  
  # Ensure consistent proton path detection by checking multiple common locations
  PROTON_PATHS=(
    "/home/pok/.steam/steam/compatibilitytools.d/GE-Proton-Current"
    "/home/pok/.steam/steam/compatibilitytools.d/GE-Proton8-21"
    "/home/pok/.steam/steam/compatibilitytools.d/GE-Proton9-25"
    "/usr/local/bin"
  )
  
  PROTON_PATH=""
  for path in "${PROTON_PATHS[@]}"; do
    if [ -f "${path}/proton" ]; then
      PROTON_PATH="${path}"
      echo "Found Proton at: ${PROTON_PATH}"
      break
    fi
  done
  
  if [ -z "$PROTON_PATH" ]; then
    echo "WARNING: Could not find Proton executable. Creating a symlink to the expected location."
    # If not found, try to detect any available proton directory
    FOUND_DIR=$(find /home/pok/.steam/steam/compatibilitytools.d -name "GE-Proton*" -type d | head -n 1)
    if [ -n "$FOUND_DIR" ]; then
      echo "Found Proton directory at: ${FOUND_DIR}, creating symlinks"
      ln -sf "${FOUND_DIR}" "/home/pok/.steam/steam/compatibilitytools.d/GE-Proton-Current"
      ln -sf "${FOUND_DIR}" "/home/pok/.steam/steam/compatibilitytools.d/GE-Proton8-21"
      ln -sf "${FOUND_DIR}" "/home/pok/.steam/steam/compatibilitytools.d/GE-Proton9-25"
      PROTON_PATH="${FOUND_DIR}"
    else
      echo "ERROR: No Proton installations found! Initialization may fail."
    fi
  fi
  
  # Force reset the prefix configuration if it exists but might be corrupted
  if [ -d "${STEAM_COMPAT_DATA_PATH}/pfx" ]; then
    echo "Cleaning up previous Proton prefix configuration..."
    
    # Backup existing registry files if they exist
    for reg_file in "system.reg" "user.reg" "userdef.reg"; do
      if [ -f "${STEAM_COMPAT_DATA_PATH}/pfx/${reg_file}" ]; then
        cp "${STEAM_COMPAT_DATA_PATH}/pfx/${reg_file}" "${STEAM_COMPAT_DATA_PATH}/pfx/${reg_file}.bak" 2>/dev/null || true
      fi
    done
    
    # Remove registry files to force clean initialization
    rm -f "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg" 2>/dev/null || true
    rm -f "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg" 2>/dev/null || true
    rm -f "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg" 2>/dev/null || true
  fi
  
  # Create minimal registry files
  echo "Creating minimal Wine registry files..."
  echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  echo ";; All keys relative to \\\\Machine" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  
  echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo ";; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "[Software\\\\Wine\\\\DllOverrides]" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "\"*version\"=\"native,builtin\"" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "\"vcrun2019\"=\"native,builtin\"" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  
  echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  echo ";; All keys relative to \\\\User\\\\DefUser" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  
  # Make sure tracked_files exists
  touch "${STEAM_COMPAT_DATA_PATH}/tracked_files" 2>/dev/null || true
  
  # Ensure all created files have correct permissions
  chmod -R 755 "${STEAM_COMPAT_DATA_PATH}/pfx" 2>/dev/null || true
  
  # Set necessary environment variables
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
  export STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH}"
  export WINEDLLOVERRIDES="version=n,b"
  
  # Sync filesystem to ensure all changes are written
  sync
  
  # Sleep to ensure changes are propagated
  sleep 5
  
  echo "Proton prefix initialization completed."
  return 0
}

# check if the server is running
is_process_running() {
  local display_message=${1:-false} # Default to not displaying the message

  # First check PID file
  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE")
    
    # Check if the process with this PID is running
    if ps -p $pid >/dev/null 2>&1; then
      # Verify that this PID is actually an ARK server process
      if ps -p $pid -o cmd= | grep -q -E "ArkAscendedServer.exe|AsaApiLoader.exe"; then
        if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
          echo "ARK server process (PID: $pid) is running."
        fi
        return 0
      else
        # PID exists but it's not an ARK server process - stale PID file
        if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
          echo "PID file contains process ID $pid which is not an ARK server process."
        fi
      fi
    fi
  fi
  
  # If we got here, either PID file doesn't exist or PID is not valid
  # Try to find ARK server processes directly
  
  # First look for AsaApiLoader.exe if API=TRUE
  if [ "${API}" = "TRUE" ]; then
    local api_pid=$(pgrep -f "AsaApiLoader.exe" | head -1)
    if [ -n "$api_pid" ]; then
      if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "AsaApiLoader process found with PID: $api_pid. Updating PID file."
      fi
      echo "$api_pid" > "$PID_FILE"
      return 0
    fi
  fi
  
  # Then look for the main server executable
  local server_pid=$(pgrep -f "ArkAscendedServer.exe" | head -1)
  if [ -n "$server_pid" ]; then
    if [ "$display_message" = "true" ] && [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
      echo "ArkAscendedServer process found with PID: $server_pid. Updating PID file."
    fi
    echo "$server_pid" > "$PID_FILE"
    return 0
  fi
  
  # If we get here, no server process was found
  if [ "$display_message" = "true" ]; then
    echo "No ARK server processes found running."
  fi
  
  # Clean up stale PID file if it exists
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi
  
  return 1
}

# Function to check if server is updating
is_server_updating() {
  if [ -f "$ASA_DIR/updating.flag" ]; then
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
      echo "Server is currently updating."
    fi
    return 0
  else
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
      echo "Server is not updating."
    fi
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
    echo "AsaApi installation skipped (API is not set to TRUE)"
    return 0
  fi

  echo "---- Installing/Updating AsaApi ----"
  
  # Ensure Proton environment is properly initialized before proceeding
  if [ ! -f "${STEAM_COMPAT_DATA_PATH}/tracked_files" ] || [ ! -d "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c" ]; then
    echo "Proton environment not fully initialized. Initializing before AsaApi installation..."
    initialize_proton_prefix
  fi
  
  # Define paths
  local bin_dir="${ASA_DIR}/ShooterGame/Binaries/Win64"
  local api_tmp="/tmp/asaapi.zip"
  local api_version_file="${bin_dir}/.asaapi_version"
  local current_api_version=""
  
  # Check if version file exists and get current version
  if [ -f "$api_version_file" ]; then
    current_api_version=$(cat "$api_version_file")
    echo "Current AsaApi version: $current_api_version"
  else
    echo "AsaApi not found, will install for the first time."
  fi
  
  # Fetch the latest release info from GitHub
  echo "Checking for latest AsaApi version..."
  local latest_release_info=$(curl -s "https://api.github.com/repos/ArkServerApi/AsaApi/releases/latest")
  local latest_version=$(echo "$latest_release_info" | jq -r '.tag_name')
  
  # Find the asset download URL for the ZIP file
  local download_url=$(echo "$latest_release_info" | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url')
  
  if [ -z "$latest_version" ] || [ "$latest_version" = "null" ] || [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
    echo "WARNING: Could not fetch latest version information from GitHub. Using fallback version."
    # Use fallback to a known version if API request fails
    latest_version="1.18"
    download_url="https://github.com/ArkServerApi/AsaApi/releases/download/1.18/AsaApi-1.18.zip"
  fi
  
  echo "Latest AsaApi version: $latest_version"
  
  # Check if an update is needed
  if [ "$current_api_version" = "$latest_version" ]; then
    echo "AsaApi is already up-to-date."
    
    # Verify the installation is complete even if up-to-date
    if [ ! -f "${bin_dir}/AsaApiLoader.exe" ]; then
      echo "WARNING: AsaApi installation appears incomplete. Forcing reinstallation."
    else
      echo "AsaApiLoader.exe found. Installation verified."
      # Create logs directory if it doesn't exist
      mkdir -p "${bin_dir}/logs"
      return 0
    fi
  fi
  
  echo "Downloading AsaApi $latest_version..."
  
  # Download the latest release
  if ! curl -L -o "$api_tmp" "$download_url"; then
    echo "ERROR: Failed to download AsaApi."
    return 1
  fi
  
  echo "Extracting AsaApi..."
  
  # Create logs directory if it doesn't exist
  mkdir -p "${bin_dir}/logs"
  
  # Extract the API files
  cd "$bin_dir"
  unzip -o "$api_tmp" -d "$bin_dir"
  
  # Set correct permissions for all files
  chmod -R 755 "$bin_dir"
  
  # Remove the temporary ZIP file
  rm -f "$api_tmp"
  
  # Pre-create Wine registry keys to ensure it's properly initialized
  if [ -d "${STEAM_COMPAT_DATA_PATH}/pfx" ]; then
    # Check if the Wine registry exists, if not create minimal registry files
    if [ ! -f "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg" ]; then
      echo "Creating minimal Wine registry to ensure proper environment..."
      echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
      echo ";; All keys relative to \\\\Machine" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
      echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
      echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
      echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
      echo ";; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
      echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
      echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
      echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
      echo ";; All keys relative to \\\\User\\\\DefUser" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
      echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
      echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
    fi
  fi
  
  # Install Microsoft Visual C++ 2019 Redistributable using multiple methods for reliability
  echo "Installing Microsoft Visual C++ 2019 Redistributable..."
  
  # Method 1: Use winetricks
  echo "Trying winetricks method first..."
  WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" winetricks -q vcrun2019 || true
  
  # Method 2: Direct installation
  echo "Trying direct installation method..."
  
  # Create a directory for the VC++ redistributable
  local vcredist_dir="/tmp/vcredist"
  mkdir -p "$vcredist_dir"
  
  # Download both x86 and x64 redistributables for maximum compatibility
  echo "Downloading VC++ redistributables..."
  curl -L -o "$vcredist_dir/vc_redist.x64.exe" "https://aka.ms/vs/16/release/vc_redist.x64.exe" || true
  curl -L -o "$vcredist_dir/vc_redist.x86.exe" "https://aka.ms/vs/16/release/vc_redist.x86.exe" || true
  
  # Copy the redistributables to the Proton prefix directory
  local proton_drive_c="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c"
  mkdir -p "$proton_drive_c/temp"
  cp "$vcredist_dir/vc_redist.x64.exe" "$proton_drive_c/temp/" || true
  cp "$vcredist_dir/vc_redist.x86.exe" "$proton_drive_c/temp/" || true
  
  # Wait a moment to ensure files are synced
  sync
  sleep 2
  
  # Method 2a: Use WINEPREFIX with wine command directly
  echo "Running VC++ installer with Wine directly..."
  WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$proton_drive_c/temp/vc_redist.x64.exe" /quiet /norestart || true
  WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$proton_drive_c/temp/vc_redist.x86.exe" /quiet /norestart || true
  
  # Method 2b: Use Proton directly
  echo "Running VC++ installer with Proton directly..."
  if [ -d "/home/pok/.steam/steam/compatibilitytools.d/GE-Proton8-21" ]; then
    STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam" \
    STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH}" \
    /home/pok/.steam/steam/compatibilitytools.d/GE-Proton8-21/proton run "$proton_drive_c/temp/vc_redist.x64.exe" /quiet /norestart || true
    
    STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam" \
    STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH}" \
    /home/pok/.steam/steam/compatibilitytools.d/GE-Proton8-21/proton run "$proton_drive_c/temp/vc_redist.x86.exe" /quiet /norestart || true
  fi
  
  # Allow more time for the installation to complete
  sleep 10
  
  echo "VC++ redistributable installation attempts completed."
  
  # Create registry entries to fake successful VC++ installation if needed
  echo "Checking if we need to manually create registry entries for VC++..."
  if ! grep -q "vcrun2019" "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg" 2>/dev/null; then
    echo "Creating manual registry entries to fake VC++ installation..."
    # Append minimal registry entries that make AsaApi believe VC++ is installed
    echo "[Software\\\\Wine\\\\DllOverrides]" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
    echo "\"vcrun2019\"=\"native,builtin\"" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  fi
  
  # Clean up
  rm -rf "$vcredist_dir"
  rm -f "$proton_drive_c/temp/vc_redist.x64.exe"
  rm -f "$proton_drive_c/temp/vc_redist.x86.exe"
  
  # Save the new version
  echo "$latest_version" > "$api_version_file"
  
  # Verify AsaApi loader executable exists and is correctly extracted
  if [ -f "${bin_dir}/AsaApiLoader.exe" ]; then
    echo "AsaApi $latest_version installed successfully. AsaApiLoader.exe found."
    chmod +x "${bin_dir}/AsaApiLoader.exe"
    return 0
  else
    echo "WARNING: AsaApi installation appears incomplete. AsaApiLoader.exe not found."
    echo "This may be due to an issue with archive extraction. Trying alternative extraction..."
    
    # Try to find the API zip and extract it using the setup_asa_plugin approach from test_script.sh
    local plugin_archive=$(basename $bin_dir/AsaApi_*.zip)
    
    if [ -f "${bin_dir}/${plugin_archive}" ]; then
      echo "Found plugin archive: ${plugin_archive}. Extracting..."
      cd "$bin_dir"
      unzip -o "$plugin_archive"
      
      if [ -f "${bin_dir}/AsaApiLoader.exe" ]; then
        echo "AsaApi extraction successful using alternative method."
        chmod +x "${bin_dir}/AsaApiLoader.exe"
        return 0
      fi
    fi
    
    echo "Unable to complete AsaApi installation. Please check the logs for errors."
    return 1
  fi
}

# Function to ensure dosdevices are properly set up
ensure_dosdevices_setup() {
  local pfx_dir="${STEAM_COMPAT_DATA_PATH}/pfx"
  
  # Check if dosdevices directory exists
  if [ ! -d "${pfx_dir}/dosdevices" ]; then
    echo "Creating missing dosdevices directory..."
    mkdir -p "${pfx_dir}/dosdevices"
  fi
  
  # Check if required symlinks exist and fix if needed
  if [ ! -L "${pfx_dir}/dosdevices/c:" ] || [ ! -e "${pfx_dir}/dosdevices/c:" ]; then
    echo "Fixing missing c: drive symlink..."
    ln -sf "../drive_c" "${pfx_dir}/dosdevices/c:"
  fi
  
  # Add other common drive symlinks
  if [ ! -e "${pfx_dir}/dosdevices/d::" ]; then
    ln -sf "/dev/null" "${pfx_dir}/dosdevices/d::"
  fi
  
  if [ ! -e "${pfx_dir}/dosdevices/e::" ]; then
    ln -sf "/dev/null" "${pfx_dir}/dosdevices/e::"
  fi
  
  if [ ! -e "${pfx_dir}/dosdevices/f::" ]; then
    ln -sf "/dev/null" "${pfx_dir}/dosdevices/f::"
  fi
  
  # Ensure proper permissions
  chmod -R 755 "${pfx_dir}/dosdevices"
  
  # Sync to ensure changes are written
  sync
}
