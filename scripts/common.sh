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

# Timezone utility functions
verify_timezone() {
  local tz_name="$1"
  
  if [ -z "$tz_name" ]; then
    return 1
  fi
  
  # Check if timezone file exists in the timezone database
  if [ -f "/usr/share/zoneinfo/$tz_name" ]; then
    return 0
  else
    return 1
  fi
}

get_current_timezone() {
  # First check user-space timezone file created by init.sh
  if [ -f "/home/pok/.timezone/current" ]; then
    cat /home/pok/.timezone/current 2>/dev/null | tr -d '\n'
    return 0
  fi
  
  # Try to get timezone from TZ environment variable
  if [ -n "$TZ" ]; then
    echo "$TZ"
    return 0
  fi
  
  # Try to get timezone from /etc/timezone
  if [ -f "/etc/timezone" ] && [ -r "/etc/timezone" ]; then
    cat /etc/timezone 2>/dev/null | tr -d '\n'
    return 0
  fi
  
  # Fallback to checking the symlink
  if [ -L "/etc/localtime" ]; then
    readlink /etc/localtime | sed 's|^.*/zoneinfo/||'
    return 0
  fi
  
  # Default fallback
  echo "UTC"
  return 1
}

format_timezone_time() {
  local format="${1:-%Y-%m-%d %H:%M:%S %Z}"
  date +"$format"
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

# Function to rotate log files and prevent disk space issues
rotate_log_files() {
  local max_logs=${1:-5}  # Default to keeping 5 most recent logs
  local log_dir="${2:-${ASA_DIR}/ShooterGame/Saved/Logs}"
  local pattern="${3:-*.log}"
  local exclude="${4:-}"
  
  if [ ! -d "$log_dir" ]; then
    echo "Log directory $log_dir does not exist. Skipping rotation."
    return 1
  fi
  
  echo "Rotating logs in $log_dir (keeping $max_logs most recent files)"
  
  if [ -n "$exclude" ]; then
    # With exclusion pattern
    find "$log_dir" -name "$pattern" -type f -not -name "$exclude" | sort -r | tail -n +$((max_logs + 1)) | xargs rm -f 2>/dev/null || true
  else
    # Without exclusion
    find "$log_dir" -name "$pattern" -type f | sort -r | tail -n +$((max_logs + 1)) | xargs rm -f 2>/dev/null || true
  fi
  
  return 0
}

# Function to clean temporary files to save disk space
clean_temp_files() {
  echo "Cleaning temporary files to free disk space..."
  
  # Clean up Wine/Proton temporary files
  if [ -d "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Temp" ]; then
    rm -rf "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Temp"/* 2>/dev/null || true
  fi
  
  # Clean up SteamCMD temporary files
  if [ -d "/opt/steamcmd/Steam/logs" ]; then
    rm -rf /opt/steamcmd/Steam/logs/* 2>/dev/null || true
  fi
  
  if [ -d "/opt/steamcmd/Steam/appcache/httpcache" ]; then
    rm -rf /opt/steamcmd/Steam/appcache/httpcache/* 2>/dev/null || true
  fi
  
  # Clean up temporary files in /tmp
  rm -f /tmp/*.log 2>/dev/null || true
  rm -f /tmp/ark_* 2>/dev/null || true
  rm -f /tmp/launch_output.log 2>/dev/null || true
  rm -f /tmp/asaapi_logs_pipe_* 2>/dev/null || true
  rm -f /tmp/SteamCMD_* 2>/dev/null || true
  
  # Clean up stale lock files
  rm -f /tmp/.X[0-9]*-lock 2>/dev/null || true
  
  echo "Temporary file cleanup completed"
}

# Function to validate SERVER_PASSWORD
validate_server_password() {
  if [ -n "$SERVER_PASSWORD" ] && ! [[ "$SERVER_PASSWORD" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "ERROR: The server password must contain only numbers or characters."
    exit 1
  fi
}

# Function to get the build ID from the appmanifest.acf file with enhanced reliability
get_build_id_from_acf() {
  # Check if file exists and is readable
  if [[ ! -f "$PERSISTENT_ACF_FILE" ]]; then
    echo "error: appmanifest.acf file not found"
    return 1
  fi
  
  # Check if file is not empty and readable
  if [[ ! -r "$PERSISTENT_ACF_FILE" ]] || [[ ! -s "$PERSISTENT_ACF_FILE" ]]; then
    echo "error: appmanifest.acf file not readable or empty"
    return 1
  fi
  
  # Try to extract build ID with error handling
  local build_id=$(grep -E "^\s+\"buildid\"\s+" "$PERSISTENT_ACF_FILE" 2>/dev/null | grep -o '[[:digit:]]*' | head -1)
  
  # Validate the extracted build ID
  if [[ -z "$build_id" ]]; then
    echo "error: could not extract build ID from acf file"
    return 1
  fi
  
  # Ensure it's numeric only
  if ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
    echo "error: invalid build ID format in acf file: $build_id"
    return 1
  fi
  
  echo "$build_id"
  return 0
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

# Function to get the current build ID from SteamCMD only (no API fallback)
get_current_build_id() {
  # Only print debug message if VERBOSE_DEBUG is enabled
  if [ "${VERBOSE_DEBUG}" = "TRUE" ]; then
    echo "[DEBUG] Retrieving build ID directly from SteamCMD (not using API)..."
  fi
  
  local steamcmd_output=$(/opt/steamcmd/steamcmd.sh +login anonymous +app_info_print ${APPID} +quit 2>/dev/null)
  
  # More precise extraction to avoid multiple matches
  # 1. Find the "branches" section
  # 2. Extract only the "public" branch section
  # 3. Look for buildid within that specific section
  # 4. Take only the first match and trim whitespace
  local build_id=$(echo "$steamcmd_output" | 
                  grep -A 150 "\"branches\"" | 
                  grep -A 50 "\"public\"" | 
                  grep -m 1 -oP "\"buildid\"\s*\"*\K[0-9]+" | 
                  head -n 1 | 
                  tr -d '[:space:]')
  
  if [ -z "$build_id" ]; then
    echo "error: could not retrieve build ID from SteamCMD. Please check SteamCMD connection."
    return 1
  fi
  
  # Final sanity check - ensure it only contains digits
  if ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
    echo "error: invalid build ID format: '$build_id'"
    return 1
  fi
  
  echo "$build_id"
}

# Function to acquire the update lock with enhanced retry logic and PID validation
acquire_update_lock() {
  local lock_file="$ASA_DIR/updating.flag"
  local max_attempts=10
  local attempt=1
  local retry_delay=5
  
  # Add random startup delay to prevent simultaneous lock attempts (1-10 seconds)
  local random_delay=$(( (RANDOM % 10) + 1 ))
  echo "[INFO] Adding random startup delay of $random_delay seconds to prevent race conditions..."
  sleep $random_delay
  
  echo "[INFO] Attempting to acquire update lock..."
  
  while [ $attempt -le $max_attempts ]; do
    # Check if lock file exists
    if [ -f "$lock_file" ]; then
      # Enhanced stale lock detection with PID validation
      local file_age=$((($(date +%s) - $(stat -c %Y "$lock_file")) / 3600))
      local lock_content=$(cat "$lock_file" 2>/dev/null || echo "")
      local lock_pid=$(echo "$lock_content" | grep -o "PID: [0-9]*" | cut -d' ' -f2)
      
      # Check if lock is stale based on multiple criteria
      local is_stale=false
      
      # Criterion 1: File is older than 2 hours
      if [ $file_age -ge 2 ]; then
        echo "[WARNING] Lock file is ${file_age} hours old (stale threshold: 2 hours)"
        is_stale=true
      fi
      
      # Criterion 2: PID in lock file is not running
      if [ -n "$lock_pid" ]; then
        if ! kill -0 "$lock_pid" 2>/dev/null; then
          echo "[WARNING] Process PID $lock_pid from lock file is no longer running"
          is_stale=true
        else
          echo "[INFO] Lock held by running process PID $lock_pid"
        fi
      fi
      
      # Criterion 3: Lock file is older than 30 minutes and no PID found
      if [ -z "$lock_pid" ] && [ $file_age -ge 1 ]; then
        echo "[WARNING] Lock file has no PID info and is ${file_age} hours old"
        is_stale=true
      fi
      
      if [ "$is_stale" = "true" ]; then
        echo "[INFO] Removing stale lock file..."
        echo "[INFO] Previous lock content: $lock_content"
        rm -f "$lock_file"
        # Try again immediately after removing stale lock
        continue
      else
        echo "[WARNING] Update lock is held by another process (attempt $attempt/$max_attempts)..."
        echo "[INFO] Lock details: $lock_content"
        sleep $retry_delay
        attempt=$((attempt + 1))
        continue
      fi
    fi
    
    # Atomic lock creation using flock with file descriptor
    local lock_fd
    exec {lock_fd}>"$lock_file" || {
      echo "[WARNING] Failed to open lock file for writing (attempt $attempt/$max_attempts)..."
      sleep $retry_delay
      attempt=$((attempt + 1))
      continue
    }
    
    # Try to get exclusive lock with timeout
    if flock -n $lock_fd; then
      # Successfully acquired lock, write comprehensive tracking information
      {
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Lock acquired by instance: ${INSTANCE_NAME:-unknown} (PID: $$)"
        echo "Container ID: ${HOSTNAME:-unknown}"
        echo "Update initiated at: $(date)"
        echo "Lock file created by: acquire_update_lock function"
        echo "Lock sequence: $attempt"
      } >&$lock_fd
      
      # Don't close the file descriptor - keep lock held
      echo "[SUCCESS] Update lock acquired successfully with flock"
      echo "[INFO] Lock file created with PID $$ for instance ${INSTANCE_NAME:-unknown}"
      
      # Store the file descriptor globally so cleanup can close it
      export UPDATE_LOCK_FD=$lock_fd
      
      # Verify we actually got the lock by checking if we can read our own content
      local verify_content=$(cat "$lock_file" 2>/dev/null | grep "PID: $$" || echo "")
      if [ -n "$verify_content" ]; then
        echo "[SUCCESS] Lock verification successful - we are the lock holder"
        return 0
      else
        echo "[ERROR] Lock verification failed - another process may have the lock"
        flock -u $lock_fd 2>/dev/null || true
        exec {lock_fd}>&- 2>/dev/null || true
        rm -f "$lock_file" 2>/dev/null || true
      fi
    else
      echo "[WARNING] Failed to acquire flock (attempt $attempt/$max_attempts)..."
      exec {lock_fd}>&- 2>/dev/null || true
      sleep $retry_delay
      attempt=$((attempt + 1))
      continue
    fi
  done
  
  echo "[ERROR] Failed to acquire update lock after $max_attempts attempts."
  return 1
}

# Function to properly release the update lock
release_update_lock() {
  local lock_file="$ASA_DIR/updating.flag"
  
  echo "[INFO] Releasing update lock..."
  
  # Release the flock if we have the file descriptor
  if [ -n "$UPDATE_LOCK_FD" ]; then
    echo "[INFO] Releasing flock and closing file descriptor $UPDATE_LOCK_FD"
    flock -u $UPDATE_LOCK_FD 2>/dev/null || true
    exec {UPDATE_LOCK_FD}>&- 2>/dev/null || true
    unset UPDATE_LOCK_FD
  fi
  
  # Remove the lock file
  if [ -f "$lock_file" ]; then
    echo "[INFO] Removing lock file: $lock_file"
    rm -f "$lock_file"
  fi
  
  echo "[SUCCESS] Update lock released successfully"
}

# Function to wait for update lock to be released
wait_for_update_lock() {
  local lock_file="$ASA_DIR/updating.flag"
  local max_wait_time=3600  # 1 hour maximum wait time
  local wait_time=0
  local check_interval=30  # Check every 30 seconds
  local stale_threshold=7200  # 2 hours in seconds
  
  echo "[INFO] Waiting for update lock to be released..."
  
  while [ -f "$lock_file" ] && [ $wait_time -lt $max_wait_time ]; do
    # Check if lock is stale (older than 2 hours)
    local file_age=$(($(date +%s) - $(stat -c %Y "$lock_file")))
    
    if [ $file_age -ge $stale_threshold ]; then
      echo "[WARNING] Found stale lock file ($(($file_age / 3600)) hours old), removing it..."
      rm -f "$lock_file"
      break
    fi
    
    # Show status message every 5 minutes
    if [ $((wait_time % 300)) -eq 0 ]; then
      echo "[INFO] Still waiting for update lock to be released... ($(($wait_time / 60)) minutes elapsed)"
      
      # Show information about the lock holder
      if [ -f "$lock_file" ]; then
        echo "[INFO] Lock holder information:"
        cat "$lock_file"
      fi
    fi
    
    sleep $check_interval
    wait_time=$((wait_time + check_interval))
  done
  
  if [ $wait_time -ge $max_wait_time ]; then
    echo "[WARNING] Timeout waiting for update lock to be released after $(($max_wait_time / 60)) minutes."
    
    # If timeout occurs, check if lock is very old, and if so, force remove it
    if [ -f "$lock_file" ]; then
      local file_age=$(($(date +%s) - $(stat -c %Y "$lock_file")))
      if [ $file_age -ge $stale_threshold ]; then
        echo "[WARNING] Force removing stale lock file ($(($file_age / 3600)) hours old)..."
        rm -f "$lock_file"
        return 0
      fi
    fi
    
    return 1
  fi
  
  echo "[INFO] Update lock has been released, can proceed."
  return 0
}

# Function to remove stale lock file
remove_stale_lock() {
  local lock_file="$ASA_DIR/updating.flag"
  
  if [ ! -f "$lock_file" ]; then
    return 0
  fi
  
  local file_age=$(( ($(date +%s) - $(stat -c %Y "$lock_file")) / 3600 ))
  if [ $file_age -ge 2 ]; then
    echo "[WARNING] Removing stale lock file (${file_age} hours old)..."
    rm -f "$lock_file"
    return 0
  fi
  
  return 1
}

# Function to create instance-specific dirty flag (for multi-instance coordination)
# Note: DIRTY_RESTART_NOTICE_MINUTES can be set in docker-compose.yaml to override default 5-minute notice for dirty restarts
create_dirty_flag() {
  local instance_name="${INSTANCE_NAME:-default}"
  local dirty_flag_dir="$ASA_DIR/instance_flags"
  local dirty_flag_file="$dirty_flag_dir/${instance_name}.dirty"
  
  # Create directory if it doesn't exist
  mkdir -p "$dirty_flag_dir"
  
  # Create the dirty flag with timestamp and reason
  {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Instance $instance_name marked dirty"
    echo "Reason: Server files updated by another instance"
    echo "Created by: $(hostname)"
    echo "Requires restart: true"
  } > "$dirty_flag_file"
  
  echo "[INFO] Created dirty flag for instance $instance_name at $dirty_flag_file"
}

# Function to check if instance has a dirty flag
has_dirty_flag() {
  local instance_name="${INSTANCE_NAME:-default}"
  local dirty_flag_dir="$ASA_DIR/instance_flags"
  local dirty_flag_file="$dirty_flag_dir/${instance_name}.dirty"
  
  [ -f "$dirty_flag_file" ]
}

# Function to clear instance dirty flag
clear_dirty_flag() {
  local instance_name="${INSTANCE_NAME:-default}"
  local dirty_flag_dir="$ASA_DIR/instance_flags"
  local dirty_flag_file="$dirty_flag_dir/${instance_name}.dirty"
  
  if [ -f "$dirty_flag_file" ]; then
    echo "[INFO] Clearing dirty flag for instance $instance_name"
    rm -f "$dirty_flag_file"
    return 0
  fi
  
  return 1
}

# Function to mark all other instances as dirty when server files are updated
mark_other_instances_dirty() {
  local updating_instance="${INSTANCE_NAME:-default}"
  local dirty_flag_dir="$ASA_DIR/instance_flags"
  local docker_compose_file="/home/pok/docker-compose.yaml"
  
  echo "[INFO] Marking other instances as dirty after server files update..."
  
  # Create directory if it doesn't exist
  mkdir -p "$dirty_flag_dir"
  
  # Try to extract instance names from docker-compose.yaml if it exists
  if [ -f "$docker_compose_file" ]; then
    # Look for service names that might be ARK instances
    local instance_names=$(grep -E "^\s+[a-zA-Z0-9_-]+:" "$docker_compose_file" | sed 's/://g' | sed 's/^[[:space:]]*//' | grep -v "version\|services\|volumes\|networks")
    
    while IFS= read -r instance_name; do
      # Skip empty lines and the instance that's doing the update
      if [ -n "$instance_name" ] && [ "$instance_name" != "$updating_instance" ]; then
        local dirty_flag_file="$dirty_flag_dir/${instance_name}.dirty"
        {
          echo "$(date +"%Y-%m-%d %H:%M:%S") - Instance $instance_name marked dirty"
          echo "Reason: Server files updated by instance $updating_instance"
          echo "Updated by: $(hostname)"
          echo "Requires restart: true"
          echo "Update completed at: $(date)"
        } > "$dirty_flag_file"
        echo "[INFO] Marked instance '$instance_name' as dirty"
      fi
    done <<< "$instance_names"
  else
    # Fallback: create dirty flags for common instance names
    local common_instances="ark-server ark-server-1 ark-server-2 ark-server-3 default"
    for instance_name in $common_instances; do
      if [ "$instance_name" != "$updating_instance" ]; then
        local dirty_flag_file="$dirty_flag_dir/${instance_name}.dirty"
        {
          echo "$(date +"%Y-%m-%d %H:%M:%S") - Instance $instance_name marked dirty"
          echo "Reason: Server files updated by instance $updating_instance"
          echo "Updated by: $(hostname)"
          echo "Requires restart: true"
          echo "Update completed at: $(date)"
        } > "$dirty_flag_file"
        echo "[INFO] Marked instance '$instance_name' as dirty (fallback method)"
      fi
    done
  fi
  
  echo "[INFO] Finished marking other instances as dirty"
}

# Enhanced function to check if server needs update (includes dirty flag check)
server_needs_update_or_restart() {
  # First check if this instance has a dirty flag (marked by another instance)
  if has_dirty_flag; then
    echo "[INFO] Instance has dirty flag - restart required due to server files update by another instance"
    return 0  # Needs restart
  fi
  
  # Then do the normal build ID comparison
  local current_build_id=$(get_current_build_id)
  local saved_build_id=$(get_build_id_from_acf)
  
  # Validate build IDs
  if [ -z "$current_build_id" ] || [[ "$current_build_id" == error* ]] || ! [[ "$current_build_id" =~ ^[0-9]+$ ]]; then
    echo "[WARNING] Could not get valid current build ID: '$current_build_id'"
    return 1
  fi
  
  if ! [[ "$saved_build_id" =~ ^[0-9]+$ ]]; then
    echo "[WARNING] Saved build ID has invalid format: '$saved_build_id'. Will attempt update."
    return 0  # Force update
  fi
  
  # Strip whitespace
  current_build_id=$(echo "$current_build_id" | tr -d '[:space:]')
  saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')
  
  # Compare build IDs
  if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
    echo "[INFO] Update needed: Current build $current_build_id differs from installed $saved_build_id"
    return 0  # Update needed
  else
    echo "[INFO] Server is up to date with build ID: $current_build_id"
    return 1  # No update needed
  fi
}

# Function to clean up legacy and stale lock files from previous system usage
cleanup_legacy_locks() {
  local context="${1:-startup}"  # startup, monitor, or aggressive
  echo "[INFO] Cleaning up legacy and stale locks (context: $context)..."
  
  local lock_file="$ASA_DIR/updating.flag"
  local dirty_flag_dir="$ASA_DIR/instance_flags"
  local current_time=$(date +%s)
  local stale_threshold=7200  # 2 hours in seconds
  local dirty_threshold
  
  # Set different thresholds based on context
  case "$context" in
    "startup")
      dirty_threshold=21600  # 6 hours - preserve fresh flags, clean legacy ones
      ;;
    "monitor")
      dirty_threshold=1800   # 30 minutes - active maintenance
      ;;
    "aggressive")
      dirty_threshold=0      # Clean all flags regardless of age
      ;;
    *)
      dirty_threshold=3600   # 1 hour - default fallback
      ;;
  esac
  
  # Clean up main update lock if it's stale
  if [ -f "$lock_file" ]; then
    local file_age=$((current_time - $(stat -c %Y "$lock_file")))
    local lock_content=$(cat "$lock_file" 2>/dev/null || echo "")
    local lock_pid=$(echo "$lock_content" | grep -o "PID: [0-9]*" | cut -d' ' -f2)
    
    local should_remove=false
    
    # Remove if older than 2 hours
    if [ $file_age -ge $stale_threshold ]; then
      echo "[INFO] Removing stale lock file ($(($file_age / 3600)) hours old)"
      should_remove=true
    fi
    
    # Remove if PID is dead
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      echo "[INFO] Removing lock file with dead PID $lock_pid"
      should_remove=true
    fi
    
    # Remove if no PID and older than 30 minutes
    if [ -z "$lock_pid" ] && [ $file_age -ge 1800 ]; then
      echo "[INFO] Removing lock file with no PID info ($(($file_age / 60)) minutes old)"
      should_remove=true
    fi
    
    if [ "$should_remove" = "true" ]; then
      echo "[INFO] Previous lock content: $lock_content"
      rm -f "$lock_file"
    fi
  fi
  
  # Clean up dirty flags based on context and age
  if [ -d "$dirty_flag_dir" ]; then
    local threshold_desc
    case "$context" in
      "startup") threshold_desc="6 hours (preserves fresh flags)" ;;
      "monitor") threshold_desc="30 minutes (active maintenance)" ;;
      "aggressive") threshold_desc="all ages (aggressive cleanup)" ;;
      *) threshold_desc="1 hour (default)" ;;
    esac
    
    echo "[INFO] Cleaning up dirty flags older than $threshold_desc from: $dirty_flag_dir"
    
    # List what we're about to clean
    local flag_count=$(find "$dirty_flag_dir" -name "*.dirty" -type f 2>/dev/null | wc -l)
    if [ "$flag_count" -gt 0 ]; then
      echo "[INFO] Found $flag_count dirty flags to evaluate:"
      
      local cleaned_count=0
      local preserved_count=0
      
      # Process each flag individually
      for dirty_file in "$dirty_flag_dir"/*.dirty; do
        if [ -f "$dirty_file" ]; then
          local dirty_age=$((current_time - $(stat -c %Y "$dirty_file")))
          local age_days=$((dirty_age / 86400))
          local age_hours=$(((dirty_age % 86400) / 3600))
          local age_minutes=$(((dirty_age % 3600) / 60))
          
          if [ "$context" = "aggressive" ] || [ $dirty_age -ge $dirty_threshold ]; then
            echo "[INFO] Removing $(basename "$dirty_file") (age: ${age_days}d ${age_hours}h ${age_minutes}m)"
            rm -f "$dirty_file"
            cleaned_count=$((cleaned_count + 1))
          else
            echo "[INFO] Preserving $(basename "$dirty_file") (age: ${age_days}d ${age_hours}h ${age_minutes}m - under threshold)"
            preserved_count=$((preserved_count + 1))
          fi
        fi
      done
      
      echo "[SUCCESS] Cleaned up $cleaned_count dirty flags, preserved $preserved_count fresh flags"
    else
      echo "[INFO] No dirty flags found to clean up"
    fi
  else
    echo "[INFO] Dirty flag directory $dirty_flag_dir does not exist"
  fi
  
  # Clean up any orphaned temporary files
  rm -f /tmp/ark_update_lock_* 2>/dev/null || true
  rm -f /tmp/updating_* 2>/dev/null || true
  
  echo "[INFO] Legacy cleanup completed"
}

# Convenience function for aggressive cleanup (removes all flags regardless of age)
cleanup_all_flags() {
  echo "[INFO] Performing aggressive cleanup of all flags..."
  cleanup_legacy_locks "aggressive"
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
  
  # New first-launch message
  local first_install=false
  if [ ! -f "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
    first_install=true
    echo ""
    echo "⚠️ FIRST-TIME SETUP DETECTED: AsaApi installation may take 5-10 minutes"
    echo "📋 This is normal and will only happen on first launch"
    echo "🔄 If the first launch fails, the system will automatically restart"
    echo "   and complete the setup on the second attempt"
    echo ""
  fi
  
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
  if [ "$first_install" = "true" ]; then
    echo ""
    echo "⏳ Installing Microsoft Visual C++ 2019 Redistributable (this may take a while)..."
    echo "⚠️ This is the longest part of first-time setup and normal to see many Wine warnings"
    echo ""
    
    # Display a text-based progress indicator
    (
      local spin=('.' '..' '...')
      local i=0
      local start_time=$(date +%s)
      
      echo -n "Setting up Visual C++ environment "
      
      while true; do
        printf "\b%s" "${spin[i]}"
        i=$(( (i+1) % 3 ))
        sleep 0.3
        
        # Display elapsed time every 10 seconds
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
          printf "\r                                                         "
          printf "\rSetting up Visual C++ environment %s (${elapsed}s elapsed)" "${spin[i]}"
        fi
        
        # Break if installation is done (check for a marker file)
        if [ -f "/tmp/vc_install_complete" ]; then
          printf "\r                                                         "
          printf "\r✅ Visual C++ setup completed after ${elapsed} seconds!      \n"
          rm -f "/tmp/vc_install_complete"
          break
        fi
        
        # Give up after 5 minutes to prevent infinite loop
        if [ $elapsed -gt 300 ]; then
          printf "\r                                                         "
          printf "\r⚠️ Visual C++ setup timed out after ${elapsed} seconds, continuing anyway\n"
          break
        fi
      done
    ) &
    PROGRESS_PID=$!
  fi
  
  # Method 1: Use winetricks
  if [ "$first_install" = "true" ]; then
    echo ">> Trying winetricks method first..."
  fi
  WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" winetricks -q vcrun2019 || true
  
  # Method 2: Direct installation
  if [ "$first_install" = "true" ]; then
    echo ">> Trying direct installation method..."
  fi
  
  # Create a directory for the VC++ redistributable
  local vcredist_dir="/tmp/vcredist"
  mkdir -p "$vcredist_dir"
  
  # Download both x86 and x64 redistributables for maximum compatibility
  if [ "$first_install" = "true" ]; then
    echo ">> Downloading VC++ redistributables..."
  fi
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
  if [ "$first_install" = "true" ]; then
    echo ">> Running VC++ installer with Wine directly..."
  fi
  WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$proton_drive_c/temp/vc_redist.x64.exe" /quiet /norestart || true
  WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$proton_drive_c/temp/vc_redist.x86.exe" /quiet /norestart || true
  
  # Method 2b: Use Proton directly
  if [ "$first_install" = "true" ]; then
    echo ">> Running VC++ installer with Proton directly..."
  fi
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
  
  # Create a marker file to signal the progress display to stop
  touch "/tmp/vc_install_complete"
  
  # Wait for the progress display to finish
  if [ "$first_install" = "true" ] && [ -n "$PROGRESS_PID" ]; then
    wait $PROGRESS_PID 2>/dev/null || true
  fi
  
  if [ "$first_install" = "true" ]; then
    echo "VC++ redistributable installation attempts completed."
  fi
  
  # Create registry entries to fake successful VC++ installation if needed
  if [ "$first_install" = "true" ]; then
    echo "Checking if we need to manually create registry entries for VC++..."
  fi
  if ! grep -q "vcrun2019" "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg" 2>/dev/null; then
    if [ "$first_install" = "true" ]; then
      echo "Creating manual registry entries to fake VC++ installation..."
    fi
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
    
    if [ "$first_install" = "true" ]; then
      echo ""
      echo "✅ FIRST-TIME SETUP COMPLETE: AsaApi installation successful!"
      echo "🚀 Server should start much faster on subsequent launches"
      echo ""
    fi
    
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
    
    if [ "$first_install" = "true" ]; then
      echo ""
      echo "⚠️ Unable to complete AsaApi installation on first attempt."
      echo "🔄 This is expected behavior - system will restart automatically"
      echo "   and installation will complete on second launch."
      echo ""
    else
      echo "Unable to complete AsaApi installation. Please check the logs for errors."
    fi
    
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
