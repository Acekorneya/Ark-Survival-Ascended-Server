#!/bin/bash

source /home/pok/scripts/common.sh

# Clean up any legacy locks and dirty flags from previous system usage
echo "🧹 Cleaning up legacy locks and dirty flags..."
if declare -f cleanup_legacy_locks >/dev/null 2>&1; then
  cleanup_legacy_locks "startup"
else
  echo "[WARNING] cleanup_legacy_locks function not found in common.sh"
fi

# Add random startup delay if enabled
if [ "${RANDOM_STARTUP_DELAY}" = "TRUE" ]; then
  DELAY=$((RANDOM % 10 + 1))
  echo "🕐 Random startup delay enabled. Waiting ${DELAY} seconds before proceeding..."
  sleep ${DELAY}
fi

# Check if the server needs an update before starting
check_and_update_before_launch() {
  echo "🔍 Checking for updates before server launch using SteamCMD..."
  
  # Check for and remove stale locks first
  remove_stale_lock
  
  # Get current build ID using the function in common.sh (now SteamCMD only)
  echo "📡 Getting latest build ID from SteamCMD..."
  local current_build_id=$(get_current_build_id)
  
  if [ -z "$current_build_id" ] || [[ "$current_build_id" == error* ]]; then
    echo "⚠️ Could not get current build ID from SteamCMD. Will retry up to 3 times..."
    
    # Retry logic for getting build ID
    for retry in {1..3}; do
      echo "🔄 Retry $retry/3 getting build ID from SteamCMD..."
      sleep 5
      current_build_id=$(get_current_build_id)
      if [ -n "$current_build_id" ] && [[ ! "$current_build_id" == error* ]]; then
        echo "✅ Successfully got build ID on retry $retry: $current_build_id"
        break
      fi
      
      if [ $retry -eq 3 ] && ([ -z "$current_build_id" ] || [[ "$current_build_id" == error* ]]); then
        echo "❌ Failed to get current build ID from SteamCMD after 3 retries. Will proceed with server launch but may need manual update."
        return 0
      fi
    done
  fi
  
  # Validate that the current build ID is numeric only
  if ! [[ "$current_build_id" =~ ^[0-9]+$ ]]; then
    echo "⚠️ SteamCMD returned invalid build ID format: '$current_build_id'. Proceeding with launch."
    return 0
  fi
  
  # Get saved build ID from ACF file
  local saved_build_id=$(get_build_id_from_acf)
  
  # Validate that the saved build ID is numeric only
  if ! [[ "$saved_build_id" =~ ^[0-9]+$ ]]; then
    echo "⚠️ Saved build ID has invalid format: '$saved_build_id'. Will attempt update."
    saved_build_id=""  # Force update by invalidating the saved ID
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 🔵 SteamCMD Current Build ID: $current_build_id"
  echo "📊 🟢 Server Installed Build ID: $saved_build_id"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Diagnostic comparison for debugging
  if [ "${VERBOSE_DEBUG}" = "TRUE" ]; then
    echo "🔬 Debug comparison: "
    echo "   - Current: '${current_build_id}' (length: ${#current_build_id})"
    echo "   - Saved: '${saved_build_id}' (length: ${#saved_build_id})"
    if [ "$current_build_id" = "$saved_build_id" ]; then
      echo "   - String comparison result: MATCH"
    else
      echo "   - String comparison result: DIFFERENT"
    fi
  fi
  
  # Compare build IDs - ensure both are stripped of any whitespace
  current_build_id=$(echo "$current_build_id" | tr -d '[:space:]')
  saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')
  
  if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
    echo "🔄 UPDATE REQUIRED: SteamCMD has newer build ($current_build_id) than installed ($saved_build_id)"
    
    # Create updating flag to prevent other instances from updating simultaneously
    if ! acquire_update_lock; then
      echo "⚠️ Another instance is currently updating. Waiting for update to complete..."
      
      # Wait for the update to complete instead of proceeding with current version
      if wait_for_update_lock; then
        echo "✅ Update completed by another instance. Checking installed version..."
        
        # Verify the update was successful by checking the build ID again
        saved_build_id=$(get_build_id_from_acf)
        saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')
        if [ "$saved_build_id" = "$current_build_id" ]; then
          echo "✅ Server is now on the latest build ID: $current_build_id"
          return 0
        else
          echo "⚠️ Server is still not on the latest build ID after waiting for update."
          echo "   Will attempt to update again..."
          # Recursive call to try updating again
          check_and_update_before_launch
          return $?
        fi
      else
        echo "⚠️ Timed out waiting for update. Will attempt to acquire lock and update..."
        # Try to remove any stale locks that might be preventing progress
        remove_stale_lock
        # Try again to acquire the lock
        if ! acquire_update_lock; then
          echo "❌ Still unable to acquire update lock. This is a critical error."
          echo "   Server will exit to avoid running outdated version."
          exit 1
        fi
        # If we get here, we acquired the lock and can proceed with the update
      fi
    fi
    
    echo "📥 Starting update process through SteamCMD..."
    local update_success=false
    local max_retries=3
    
    for retry in $(seq 1 $max_retries); do
      echo "🔄 Update attempt $retry/$max_retries..."
      /opt/steamcmd/steamcmd.sh +force_install_dir "$ASA_DIR" +login anonymous +app_update "$APPID" +quit
      update_result=$?
      
      # Check if update was successful
      if [[ $update_result -eq 0 && -f "$ASA_DIR/steamapps/appmanifest_$APPID.acf" ]]; then
        cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
        echo "✅ Server updated successfully to SteamCMD build ID: $current_build_id"
        update_success=true
        break
      else
        echo "⚠️ Server update attempt $retry failed with exit code: $update_result"
        sleep 5  # Wait before retry
      fi
    done
    
    # Remove the updating flag
    rm -f "$ASA_DIR/updating.flag"
    
    if [ "$update_success" = true ]; then
      echo "🚀 Proceeding with server launch..."
      return 0
    else
      echo "❌ Server update failed after $max_retries attempts. This is a critical error."
      echo "   Server will exit to avoid running outdated version."
      exit 1
    fi
  else
    echo "✅ Server is already on the latest SteamCMD build ID: $current_build_id. No update needed."
    return 0
  fi
}

# Add disk space cleanup function to remove non-essential data
cleanup_disk_space() {
  echo "🧹 Performing disk space cleanup..."
  
  # Clean up old logs (keep only the 5 most recent)
  if [ -d "${ASA_DIR}/ShooterGame/Saved/Logs" ]; then
    echo "  - Rotating server logs..."
    find "${ASA_DIR}/ShooterGame/Saved/Logs" -name "*.log" -type f -not -name "ShooterGame.log" | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi
  
  # Clean AsaApi logs (keep only the 5 most recent)
  if [ -d "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" ]; then
    echo "  - Rotating AsaApi logs..."
    find "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" -name "*.log" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi
  
  # Clean up any temp files in Wine prefix (these are recreated as needed)
  if [ -d "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Temp" ]; then
    echo "  - Cleaning Wine temporary files..."
    rm -rf "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Temp"/* 2>/dev/null || true
  fi
  
  # Clean up steamcmd temp files that might be left behind
  if [ -d "/opt/steamcmd/Steam/logs" ]; then
    echo "  - Cleaning SteamCMD logs..."
    rm -rf /opt/steamcmd/Steam/logs/* 2>/dev/null || true
  fi
  
  # Clean up container-specific temp files
  echo "  - Cleaning temporary files..."
  rm -f /tmp/*.log 2>/dev/null || true
  rm -f /tmp/ark_* 2>/dev/null || true
  rm -f /tmp/launch_output.log 2>/dev/null || true
  rm -f /tmp/asaapi_logs_pipe_* 2>/dev/null || true
  
  # Remove old PID files if present
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE" 2>/dev/null || true
  fi
  
  # Clean up any leftover Xvfb lock files
  rm -f /tmp/.X[0-9]*-lock 2>/dev/null || true
  
  echo "✅ Disk space cleanup completed"
}

# Check if we're restarting from a container restart
if [ -f "/home/pok/restart_reason.flag" ] && [ "$(cat /home/pok/restart_reason.flag)" = "API_RESTART" ]; then
  echo "🔄 Container restarted for API mode recovery"
  RESTART_MODE=true
  # Remove the flag file
  rm -f "/home/pok/restart_reason.flag"
  
  if [ "${API}" = "TRUE" ]; then
    echo "🖥️ API mode container recovery - setting up fresh environment..."
    # Force a complete environment reset
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
    export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
    export WINEDLLOVERRIDES="version=n,b"
    export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
    export DISPLAY=:0.0
    
    # Kill any leftover processes
    pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
    pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    pkill -9 -f "Xvfb" >/dev/null 2>&1 || true
    sleep 2
    
    # Clean up X11 sockets completely
    if [ -d "/tmp/.X11-unix" ]; then
      rm -rf /tmp/.X11-unix/* 2>/dev/null || true
      mkdir -p /tmp/.X11-unix
      chmod 1777 /tmp/.X11-unix
    fi
    
    # Remove PID file
    if [ -f "$PID_FILE" ]; then
      echo "- Removing stale PID file..."
      rm -f "$PID_FILE"
    fi
  fi
fi

# Check whether we're called from restart or directly
if [ "$1" = "--from-restart" ] || [ -f "/tmp/restart_in_progress" ]; then
  RESTART_MODE=true
  # If restart flag exists, remove it
  rm -f "/tmp/restart_in_progress" 2>/dev/null || true
  echo "🔄 Running in restart mode - using specialized environment setup..."
  
  # Clear dirty flag for this instance since we're restarting (loading fresh files)
  clear_dirty_flag || true  # Don't fail if there's no dirty flag
  
  # Force reset environment variables that are critical for API mode
  if [ "${API}" = "TRUE" ]; then
    echo "🖥️ Forcing Xvfb setup for API restart mode..."
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
    export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
    export WINEDLLOVERRIDES="version=n,b"
    export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
    export DISPLAY=:0.0
    
    # Kill any existing Xvfb processes to ensure clean state
    pkill -9 -f "Xvfb" >/dev/null 2>&1 || true
    sleep 2
    
    # Clean up X11 sockets completely
    if [ -d "/tmp/.X11-unix" ]; then
      rm -rf /tmp/.X11-unix/* 2>/dev/null || true
      mkdir -p /tmp/.X11-unix
      chmod 1777 /tmp/.X11-unix
    fi
    
    # Explicitly start Xvfb here for API mode restart
    Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
    XVFB_RESTART_PID=$!
    echo "- Started Xvfb with PID: $XVFB_RESTART_PID"
    sleep 2
    
    # Verify Xvfb is running
    if kill -0 $XVFB_RESTART_PID 2>/dev/null; then
      echo "- ✅ Virtual display is running on :0.0"
    else
      echo "- ⚠️ Primary virtual display failed. Trying backup display..."
      export DISPLAY=:1.0
      Xvfb :1 -screen 0 1024x768x16 2>/dev/null &
      XVFB_RESTART_PID=$!
      sleep 2
    fi
    
    # Ensure log directories are created for API mode
    echo "- Creating log directories to ensure visibility..."
    mkdir -p "${ASA_DIR}/ShooterGame/Saved/Logs"
    mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Saved/Logs"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    
    # Create a symlink to ShooterGame.log in more accessible location for monitoring
    if [ ! -L "/home/pok/shooter_game.log" ]; then
      ln -sf "${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log" "/home/pok/shooter_game.log" 2>/dev/null || true
    fi
  fi
fi

# Enhanced cleanup for API=TRUE to ensure clean server startup
if [ "${API}" = "TRUE" ]; then
  echo "🧹 API mode: Performing enhanced environment cleanup for a clean start..."
  
  # Kill any existing Wine/Proton processes
  if pgrep -f "wine" >/dev/null 2>&1 || pgrep -f "wineserver" >/dev/null 2>&1; then
    echo "   - Cleaning up Wine/Proton processes..."
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true
    sleep 2
  fi
  
  # Don't kill Xvfb if we're in restart mode - we just started it above
  if [ "$RESTART_MODE" != "true" ]; then
    # Kill any existing Xvfb processes
    if pgrep -f "Xvfb" >/dev/null 2>&1; then
      echo "   - Cleaning up Xvfb processes..."
      pkill -9 -f "Xvfb" >/dev/null 2>&1 || true
      sleep 2
    fi
    
    # Clean up X11 sockets
    if [ -d "/tmp/.X11-unix" ]; then
      echo "   - Cleaning up X11 sockets..."
      rm -rf /tmp/.X11-unix/* 2>/dev/null || true
      mkdir -p /tmp/.X11-unix
      chmod 1777 /tmp/.X11-unix
    fi
  else
    echo "   - Skipping Xvfb cleanup in restart mode (already handled)"
  fi
  
  # Remove PID file if it exists
  if [ -f "$PID_FILE" ]; then
    echo "   - Removing stale PID file..."
    rm -f "$PID_FILE"
  fi
  
  echo "✅ Environment cleanup completed."
fi

# Configure ulimit
ulimit -n 100000

echo ""
echo "🎮 ==== ARK SURVIVAL ASCENDED SERVER STARTING ==== 🎮"
echo ""

# Check for updates before launching the server (if UPDATE_SERVER is enabled)
if [ "${UPDATE_SERVER}" = "TRUE" ]; then
  check_and_update_before_launch
fi

# Handle log rotation on startup
echo "🔄 Checking for old log files to rotate..."
# Rotate ShooterGame.log if it exists
if [ -f "${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log" ]; then
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  echo "📄 Renaming existing ShooterGame.log to ShooterGame.log.${TIMESTAMP}"
  mv "${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log" "${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log.${TIMESTAMP}"
fi

# Rotate API logs if they exist
if [ -d "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" ] && [ "$(ls -A ${ASA_DIR}/ShooterGame/Binaries/Win64/logs/*.log 2>/dev/null)" ]; then
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  echo "📄 Renaming existing API log files..."
  for logfile in ${ASA_DIR}/ShooterGame/Binaries/Win64/logs/*.log; do
    if [ -f "$logfile" ]; then
      newname="${logfile}.${TIMESTAMP}"
      echo "   - Renaming $(basename "$logfile") to $(basename "$newname")"
      mv "$logfile" "$newname"
    fi
  done
fi

# Create directories if not already present
mkdir -p ${ASA_DIR}/Engine/Binaries/ThirdParty/Steamworks/Steamv153/Win64/

if [ "${BACKUP_DIR}" != "false" ] && [ -n "${BACKUP_DIR}" ]; then
  # Create backup directory if not already present
  mkdir -p ${BACKUP_DIR}
  # Also create Config subdirectory to prevent errors later
  mkdir -p ${BACKUP_DIR}/Config
  mkdir -p ${BACKUP_DIR}/SavedArks
fi

# Mount backup directory
if [ -d "${BACKUP_DIR}" ] && [ "${BACKUP_DIR}" != "false" ]; then
  echo "📂 Mounting backup directory from ${BACKUP_DIR}"
  # Ensure the Save & Config directories exist
  mkdir -p ${ASA_DIR}/ShooterGame/Saved/SavedArks
  mkdir -p ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer

  # Create symlinks for the backup
  if [ ! -L "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ] && [ -d "${BACKUP_DIR}/SavedArks/${MAP_NAME}" ]; then
    echo "↔️ Creating symbolic link for SavedArks/${MAP_NAME} from backup"
    rm -rf ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
    ln -sf ${BACKUP_DIR}/SavedArks/${MAP_NAME} ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
  elif [ ! -d "${BACKUP_DIR}/SavedArks/${MAP_NAME}" ] && [ -n "${MAP_NAME}" ]; then
    echo "📁 Creating backup directory for SavedArks/${MAP_NAME}"
    mkdir -p ${BACKUP_DIR}/SavedArks/${MAP_NAME}
    # If the local directory exists but is not a symlink, move its contents to the backup and create a symlink
    if [ -d "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ] && [ ! -L "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ]; then
      echo "↔️ Moving existing data to backup location"
      cp -aR ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}/* ${BACKUP_DIR}/SavedArks/${MAP_NAME}/ 2>/dev/null || true
      rm -rf ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
    fi
    ln -sf ${BACKUP_DIR}/SavedArks/${MAP_NAME} ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
  fi

  # Handle config files
  if [ ! -f "${BACKUP_DIR}/Config/Game.ini" ] && [ -f "${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini" ]; then
    echo "📄 Moving current Game.ini to backup location"
    cp -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini ${BACKUP_DIR}/Config/Game.ini
  fi

  if [ ! -f "${BACKUP_DIR}/Config/GameUserSettings.ini" ] && [ -f "${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" ]; then
    echo "📄 Moving current GameUserSettings.ini to backup location"
    cp -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini ${BACKUP_DIR}/Config/GameUserSettings.ini
  fi

  if [ -f "${BACKUP_DIR}/Config/Game.ini" ]; then
    echo "📄 Linking Game.ini from backup"
    rm -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini
    ln -sf ${BACKUP_DIR}/Config/Game.ini ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini
  fi

  if [ -f "${BACKUP_DIR}/Config/GameUserSettings.ini" ]; then
    echo "📄 Linking GameUserSettings.ini from backup"
    rm -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
    ln -sf ${BACKUP_DIR}/Config/GameUserSettings.ini ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
  fi
fi

# Enable container-aware Proton environment initialization
export CONTAINER_MODE="TRUE"

# Robust virtual display setup for headless operation
setup_virtual_display() {
  # If we're in restart mode and API=TRUE, we already set up Xvfb above, so skip this
  if [ "$RESTART_MODE" = "true" ] && [ "${API}" = "TRUE" ]; then
    echo "🖥️ Virtual display already set up in restart mode, skipping..."
    return 0
  fi
  
  echo "🖥️ Setting up virtual display for headless operation..."
  export DISPLAY=:0.0
  
  # Kill any existing Xvfb processes to ensure clean state
  pkill -9 -f "Xvfb" >/dev/null 2>&1 || true
  
  # Clean up X11 sockets
  if [ -d "/tmp/.X11-unix" ]; then
    rm -rf /tmp/.X11-unix/* 2>/dev/null || true
  fi
  
  # Create .X11-unix directory with proper permissions
  mkdir -p /tmp/.X11-unix 2>/dev/null || true
  chmod 1777 /tmp/.X11-unix 2>/dev/null || true
  
  # Check if Xvfb is installed
  if ! command -v Xvfb >/dev/null 2>&1; then
    echo "  ⚠️ Xvfb not found. Will attempt to install..."
    apt-get update -qq && apt-get install -y --no-install-recommends xvfb x11-xserver-utils xauth >/dev/null 2>&1
  fi
  
  # Start Xvfb with error output suppressed
  Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
  XVFB_PID=$!
  echo "  → Started Xvfb (virtual display) with PID: $XVFB_PID"
  
  # Give Xvfb time to start and verify it's running
  sleep 2
  
  # Verify Xvfb is running
  if kill -0 $XVFB_PID 2>/dev/null; then
    echo "  ✅ Virtual display is running"
  else
    echo "  ⚠️ Virtual display failed to start. Trying again..."
    
    # Try again with a different display number
    export DISPLAY=:1.0
    Xvfb :1 -screen 0 1024x768x16 2>/dev/null &
    XVFB_PID=$!
    sleep 2
    
    if kill -0 $XVFB_PID 2>/dev/null; then
      echo "  ✅ Virtual display is running on secondary display"
    else
      echo "  ⚠️ Virtual display setup failed (non-critical)"
    fi
  fi
  
  # Export essential display environment variables
  export WINEDLLOVERRIDES="*version=n,b;vcrun2019=n,b"
  export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
}

# Robust AsaApi initialization for container environment
verify_proton_environment() {
  echo "----Robust Proton Environment Verification for AsaApi----"
  
  # Ensure we have the correct directory structure
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser"
  
  # Step 1: Check and find available Proton versions
  echo "Searching for available Proton GE versions..."
  PROTON_BASE_DIR="/home/pok/.steam/steam/compatibilitytools.d"
  mkdir -p "$PROTON_BASE_DIR"
  
  # Create an array to store found Proton directories
  FOUND_PROTON_DIRS=()
  
  # First search in the standard location
  if [ -d "$PROTON_BASE_DIR" ]; then
    while IFS= read -r dir; do
      if [ -d "$dir" ] && [ -f "$dir/proton" ]; then
        FOUND_PROTON_DIRS+=("$dir")
        echo "Found Proton at: $dir"
      fi
    done < <(find "$PROTON_BASE_DIR" -maxdepth 1 -name "GE-Proton*" -type d)
  fi
  
  # Then check in /usr/local/bin
  if [ -f "/usr/local/bin/proton" ]; then
    FOUND_PROTON_DIRS+=("/usr/local/bin")
    echo "Found Proton at: /usr/local/bin"
  fi
  
  # Step 2: If no Proton directories found, check if the tarball is available
  if [ ${#FOUND_PROTON_DIRS[@]} -eq 0 ]; then
    echo "No Proton installations found in standard locations."
    
    # Try to find the tarball
    PROTON_TARBALL=$(find /tmp -name "GE-Proton*.tar.gz" -type f 2>/dev/null | head -n 1)
    
    if [ -n "$PROTON_TARBALL" ]; then
      echo "Found Proton tarball: $PROTON_TARBALL. Extracting..."
      mkdir -p "$PROTON_BASE_DIR/GE-Proton-Current"
      tar -xzf "$PROTON_TARBALL" -C "$PROTON_BASE_DIR"
      EXTRACTED_DIR=$(find "$PROTON_BASE_DIR" -maxdepth 1 -name "GE-Proton*" -type d | head -n 1)
      
      if [ -n "$EXTRACTED_DIR" ]; then
        echo "Extracted Proton to: $EXTRACTED_DIR"
        FOUND_PROTON_DIRS+=("$EXTRACTED_DIR")
      fi
    else
      echo "WARNING: No Proton tarball found. Will try to use the system Proton."
    fi
  fi
  
  # Step 3: Create symlinks for expected Proton versions
  if [ ${#FOUND_PROTON_DIRS[@]} -gt 0 ]; then
    # Use the first found Proton directory as the source for symlinks
    PROTON_SOURCE="${FOUND_PROTON_DIRS[0]}"
    echo "Using $PROTON_SOURCE as the primary Proton installation"
    
    # Create symlinks for various expected version names
    ln -sf "$PROTON_SOURCE" "$PROTON_BASE_DIR/GE-Proton-Current"
    ln -sf "$PROTON_SOURCE" "$PROTON_BASE_DIR/GE-Proton8-21"
    ln -sf "$PROTON_SOURCE" "$PROTON_BASE_DIR/GE-Proton9-25"
    
    echo "Created symlinks for compatibility with scripts"
  else
    echo "WARNING: No Proton installations found. Container may not function correctly."
    
    # Try to create a minimal proton script as a last resort
    if [ ! -d "$PROTON_BASE_DIR/GE-Proton-Current" ]; then
      echo "Creating minimal Proton directory structure as fallback..."
      mkdir -p "$PROTON_BASE_DIR/GE-Proton-Current"
      mkdir -p "$PROTON_BASE_DIR/GE-Proton-Current/dist/bin"
      
      # Create a minimal proton script
      echo '#!/bin/bash' > "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      echo 'export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"' >> "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      echo 'wine "$@"' >> "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      chmod +x "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      
      # Create symlinks
      ln -sf "$PROTON_BASE_DIR/GE-Proton-Current" "$PROTON_BASE_DIR/GE-Proton8-21"
      ln -sf "$PROTON_BASE_DIR/GE-Proton-Current" "$PROTON_BASE_DIR/GE-Proton9-25"
      
      echo "Created minimal Proton fallback"
    fi
  fi
  
  # Step 4: Force reset the Proton prefix to ensure clean environment
  echo "Force resetting Proton prefix for clean environment..."
  initialize_proton_prefix
  
  # Step 5: Set up directory permissions
  echo "Setting correct permissions for all directories..."
  chmod -R 755 "${STEAM_COMPAT_DATA_PATH}"
  chmod -R 755 "$PROTON_BASE_DIR"
  
  # Ensure synchronization
  sync
  # Add a delay to ensure all filesystem operations complete
  sleep 3
  
  # Step 6: Test Wine functionality
  echo "Testing Wine functionality..."
  if WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine --version >/dev/null 2>&1; then
    echo "Wine is functional in the environment."
  else
    echo "WARNING: Wine does not appear to be functioning correctly."
    # Try to set up Wine library paths
    export LD_LIBRARY_PATH="/usr/lib/wine:/usr/lib32/wine:$LD_LIBRARY_PATH"
  fi
  
  echo "Proton environment verification completed."
}

# Helper function to create minimal registry if other methods fail
create_minimal_registry() {
  echo "Creating minimal Wine registry structure..."
  
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
  
  # Create Visual C++ directory structure to make AsaApiLoader believe it's installed
  local vc_dir="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio"
  mkdir -p "$vc_dir"
  
  echo "Minimal registry and directory structure created."
}

# Set up virtual display
setup_virtual_display

echo ""
echo "🔍 Running environment checks..."
# Run comprehensive pre-launch environment check
chmod +x /home/pok/scripts/prelaunch_check.sh
/home/pok/scripts/prelaunch_check.sh
PRELAUNCH_CHECK_RESULT=$?

# Run disk space cleanup to ensure we're not accumulating unnecessary files
cleanup_disk_space

# Check if server files exist, install them if not
if [ $PRELAUNCH_CHECK_RESULT -ne 0 ] || [ ! -f "/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ]; then
  echo ""
  echo "🔍 First-time setup: ARK server files will now be downloaded..."
  echo "⏳ This may take some time depending on your internet connection speed (15-30+ minutes)"
  echo "☕ Feel free to grab a coffee while waiting - download progress will be displayed below"
  echo ""
  chmod +x /home/pok/scripts/install_server.sh
  /home/pok/scripts/install_server.sh
  
  # Verify installation was successful
  if [ ! -f "/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ]; then
    echo "❌ ERROR: Server installation failed! Please check logs for details."
    exit 1
  else
    echo "✅ Server files downloaded successfully!"
    echo "🚀 Proceeding with server startup..."
  fi
fi

# Set essential Proton/Wine environment variables regardless of API setting
# These need to be set for both API=TRUE and API=FALSE cases
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
export WINEDLLOVERRIDES="version=n,b"

# Initialize Proton environment regardless of API setting
verify_proton_environment

# Install/Update AsaApi if API=TRUE
if [ "${API}" = "TRUE" ]; then
  echo ""
  echo "🔌 Initializing AsaApi plugin system..."
  
  # Install the API with extra verification for container mode
  install_ark_server_api
  
  # Verify the installation
  if [ -f "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
    echo "  ✅ AsaApi installation confirmed"
    # Create logs directory if it doesn't exist
    mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Binaries/Win64"
    
    # Pre-test AsaApiLoader.exe with Wine to ensure it can be found and executed
    if WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" --help >/dev/null 2>&1; then
      echo "  ✅ AsaApiLoader.exe is executable"
    else
      echo "  ℹ️ AsaApiLoader.exe test execution returned expected result"
    fi
  else
    echo "  ⚠️ AsaApi loader not found after installation attempt"
  fi
fi

echo ""
echo "🚀 LAUNCHING ARK SERVER..."
echo ""

# Attempt to use screen if available, otherwise fall back to basic method
SCREEN_AVAILABLE=false
if command -v screen >/dev/null 2>&1; then
  SCREEN_AVAILABLE=true
else
  # Try to install screen but don't fail if it doesn't work
  echo "[INFO] Attempting to install screen for better log visibility (optional)..."
  { apt-get update -qq && apt-get install -y screen; } >/dev/null 2>&1
  # Check if installation succeeded
  if command -v screen >/dev/null 2>&1; then
    SCREEN_AVAILABLE=true
    echo "[SUCCESS] Screen installed successfully!"
  else
    echo "[INFO] Screen not available. Using fallback method instead."
  fi
fi

# Launch the server differently based on whether screen is available
if [ "$SCREEN_AVAILABLE" = true ]; then
  # Use screen for better log management and visibility
  echo "[INFO] Starting server in screen session..."
  screen -dmS ark_server bash -c "/home/pok/scripts/launch_ASA.sh 2>&1 | tee -a /home/pok/launch_output.log; exec bash"
  echo "[INFO] ARK server launched in screen session. View logs with: screen -r ark_server"
else
  # Fallback method - use nohup to run in background while still capturing logs
  echo "[INFO] Starting server with fallback method (nohup)..."
  mkdir -p /home/pok/logs
  nohup /home/pok/scripts/launch_ASA.sh > /home/pok/logs/server_console.log 2>&1 &
  SERVER_PID=$!
  echo "[INFO] ARK server launched with PID: $SERVER_PID"
  echo "[INFO] View logs with: tail -f /home/pok/logs/server_console.log"
  
  # Start a background process to tail the log file to console
  # This will show logs in the container's output while allowing the server to run in background
  (tail -f /home/pok/logs/server_console.log 2>/dev/null &)
fi

# Simple server startup notification without creating competing flags
{
  # Wait for basic server process detection without interfering with launch_ASA.sh startup flag creation
  timeout=120  # 2 minutes timeout - shorter to avoid conflicts
  elapsed=0
  last_status_time=0
  
  while [ $elapsed -lt $timeout ]; do
    # Simple check if server process is running without creating startup flags
    server_pid=$(ps aux | grep -v grep | grep -E "AsaApiLoader.exe|ArkAscendedServer.exe" | awk '{print $2}' | head -1)
    if [ -n "$server_pid" ]; then
      echo "[INFO] ARK Server process detected with PID: $server_pid"
      echo "[INFO] Server startup monitoring transferred to launch_ASA.sh"
      break
    else
      # Only display status message every 30 seconds to reduce log spam
      if [ $elapsed -eq 0 ] || [ $((elapsed - last_status_time)) -ge 30 ]; then
        echo "[INFO] SERVER STARTING: Waiting for process... (${elapsed}s elapsed)"
        last_status_time=$elapsed
      fi
    fi
    
    sleep 10
    elapsed=$((elapsed + 10))
  done
  
  # Final status check
  if [ $elapsed -ge $timeout ]; then
    echo "[INFO] Initial process detection timeout. launch_ASA.sh will handle detailed monitoring."
  fi
} &
MONITOR_PID=$!

# Simple restart monitoring without flag conflicts
{
  # Wait longer before starting restart monitoring to avoid conflicts with launch_ASA.sh
  echo "[INFO] Waiting for server startup to stabilize before beginning restart detection..."
  sleep 120  # Wait 2 minutes before starting restart monitoring
  
  # Keep checking if the server process is running
  while true; do
    # Check if server process is running
    if ! pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 && ! pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
      # Server process not found, check if this is a deliberate shutdown
      if [ -f "/home/pok/shutdown.flag" ]; then
        echo "[INFO] Detected shutdown flag. Not restarting server."
        break
      else
        # This might be a server-initiated restart, wait a moment to be sure
        echo "[WARNING] Server process not found. Waiting to confirm if this is a restart..."
        sleep 10
        
        # Check again to make sure the server is really gone
        if ! pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 && ! pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
          echo "[INFO] Detected server self-restart. Initiating simplified restart process..."
          
          # If in API mode and EXIT_ON_API_RESTART is enabled, trigger container restart
          if [ "${API}" = "TRUE" ] && [ "${EXIT_ON_API_RESTART:-TRUE}" = "TRUE" ]; then
            echo "[INFO] API mode detected - using container restart strategy for self-restart"
            
            # Create flag files for container restart detection
            echo "$(date) - Container exiting for automatic restart due to server self-restart" > /home/pok/container_restart.log
            echo "API_RESTART" > /home/pok/restart_reason.flag
            
            # Perform basic cleanup
            echo "[INFO] Cleaning up processes before container restart..."
            pkill -9 -f "wine" >/dev/null 2>&1 || true
            pkill -9 -f "wineserver" >/dev/null 2>&1 || true
            
            # Remove PID file if it exists
            if [ -f "$PID_FILE" ]; then
              echo "[INFO] Removing stale PID file..."
              rm -f "$PID_FILE"
            fi
            
            echo "[INFO] Exiting container for automatic restart..."
            sleep 3
            exit 0
          else
            # Perform basic cleanup - but don't handle Xvfb, let restart_server.sh do that
            echo "[INFO] Performing basic process cleanup..."
            
            # Kill any Wine/Proton processes
            if pgrep -f "wine" >/dev/null 2>&1 || pgrep -f "wineserver" >/dev/null 2>&1; then
              echo "[INFO] Cleaning up Wine/Proton processes..."
              pkill -9 -f "wine" >/dev/null 2>&1 || true
              pkill -9 -f "wineserver" >/dev/null 2>&1 || true
              sleep 2
            fi
            
            # Remove PID file if it exists
            if [ -f "$PID_FILE" ]; then
              echo "[INFO] Removing stale PID file..."
              rm -f "$PID_FILE"
            fi
            
            echo "[INFO] Process cleanup completed. Running restart_server.sh immediate..."
            
            # Use the restart_server.sh script with the restart flag
            /home/pok/scripts/restart_server.sh immediate
            
            echo "[INFO] Restart command issued. Exiting monitoring loop."
            break
          fi
        fi
      fi
    fi
    
    # Check every 30 seconds
    sleep 30
  done
} &
RESTART_MONITOR_PID=$!

# Launch the update monitor in background if API mode is not enabled
if [ "${UPDATE_SERVER}" = "TRUE" ] && [ "${API}" != "TRUE" ]; then
  echo "[INFO] Starting update monitor in background..."
  
  if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
    # When display is enabled, redirect output to both console and log file
    nohup /home/pok/scripts/monitor_ark_server.sh > >(tee -a /home/pok/logs/monitor.log) 2>&1 &
  else
    # When display is disabled, redirect output only to log file
    nohup /home/pok/scripts/monitor_ark_server.sh > /home/pok/logs/monitor.log 2>&1 &
  fi
  
  MONITOR_PID=$!
  echo "[INFO] Update monitor started with PID: $MONITOR_PID"
elif [ "${API}" = "TRUE" ] && [ "${UPDATE_SERVER}" = "TRUE" ]; then
  echo "⚠️ [WARNING] Update monitor is disabled when API=TRUE"
  echo "⚠️ [WARNING] You must manually update the server using the POK-manager.sh script with:"
  echo "⚠️           ./POK-manager.sh -stop <instance_name>"
  echo "⚠️           ./POK-manager.sh -start <instance_name>"
fi

# Keep the init.sh script running to prevent container from exiting
# This will not block log display since logs are handled separately
tail -f /dev/null