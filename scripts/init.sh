#!/bin/bash
#
# Main container entrypoint. Sets up runtime prerequisites, verifies shared
# server files, launches the server, and starts background monitoring.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/update_coordination.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/shutdown_server.sh"

INIT_SHUTDOWN_IN_PROGRESS=false

container_signal_shutdown() {
  if [ "$INIT_SHUTDOWN_IN_PROGRESS" = "true" ]; then
    return 0
  fi

  INIT_SHUTDOWN_IN_PROGRESS=true
  trap '' SIGTERM SIGINT
  echo "[INFO] Container stop signal received; starting verified two-stage ASA shutdown..."

  if safe_container_stop; then
    echo "[SUCCESS] Both world saves are verified. Exiting container cleanly."
    exit 0
  fi

  echo "[FATAL] Container stop remains unsafe because save verification failed." >&2
  echo "[FATAL] PID 1 will remain alive until Docker's configured grace period expires." >&2
  INIT_SHUTDOWN_IN_PROGRESS=false
  trap container_signal_shutdown SIGTERM SIGINT
  return 1
}

trap container_signal_shutdown SIGTERM SIGINT
rm -f "$VERIFIED_SHUTDOWN_MARKER" 2>/dev/null || true

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

prepare_runtime_env

# Setup container timezone based on TZ environment variable
setup_container_timezone() {
  echo "🕐 Setting up container timezone..."
  
  if [ -z "$TZ" ]; then
    echo "⚠️ TZ environment variable not set, using system default timezone"
    local current_time=$(date)
    echo "📅 Current system time: $current_time"
    return 0
  fi
  
  echo "🕐 Configuring timezone: $TZ"
  
  # Validate timezone by checking if it exists in the timezone database
  if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    # Timezone file exists, so it's valid
    export TZ="$TZ"
    local current_time=$(TZ="$TZ" date)
    local tz_abbrev=$(TZ="$TZ" date "+%Z")
    
    echo "✅ Container timezone: $current_time"
    echo "ℹ️  ARK server logs show UTC time, but update windows use local time ($tz_abbrev)"
  else
    # Invalid timezone, fallback to UTC with helpful message
    echo "❌ Invalid timezone: '$TZ'"
    echo "⚠️  Available timezones: America/Los_Angeles, America/New_York, Europe/London, etc."
    echo "🔧 Falling back to UTC timezone for system stability"
    
    export TZ="UTC"
    local current_time=$(TZ="$TZ" date)
    
    echo "✅ Container timezone: $current_time (UTC fallback)"
    echo "ℹ️  To fix: Set a valid timezone in your docker-compose.yaml file"
  fi
  
  # Create a user-space timezone indicator file for scripts to reference
  mkdir -p /home/pok/.timezone
  echo "$TZ" > /home/pok/.timezone/current 2>/dev/null || true
  echo "$(date +%s)" > /home/pok/.timezone/set_at 2>/dev/null || true
  
  return 0
}

start_health_service() {
  local health_server="/home/pok/scripts/health_server.py"

  mkdir -p /home/pok/logs

  if ! command -v python3 >/dev/null 2>&1; then
    echo "⚠️ Health service not started: python3 is not available in the container."
    return 0
  fi

  if [ ! -f "$health_server" ]; then
    echo "⚠️ Health service not started: ${health_server} was not found."
    return 0
  fi

  python3 "$health_server" >/home/pok/logs/health_server.log 2>&1 &
  HEALTH_SERVER_PID=$!

  if kill -0 "$HEALTH_SERVER_PID" 2>/dev/null; then
    echo "💓 Health service listening on port ${HEALTHCHECK_PORT:-8080}"
  else
    echo "⚠️ Health service failed to start."
  fi
}

# Setup timezone early in the initialization
setup_container_timezone
start_health_service

if env_value_is_truthy "${UPDATE_MODE:-FALSE}"; then
  echo "🔧 ==== RUNNING IN UPDATE-ONLY MODE ==== 🔧"
  echo "This container is for server file updates via SteamCMD only."
  echo "Server startup will be skipped. Container will stay alive for update operations."
  echo ""

  update_base_dir="${ASA_DIR:-/home/pok/arkserver}"
  mkdir -p "${update_base_dir}/ShooterGame/Binaries/Win64/logs"
  mkdir -p "${update_base_dir}/ShooterGame/Saved/Config/WindowsServer"
  mkdir -p "${update_base_dir}/ShooterGame/Saved/SavedArks"

  echo "Container ready for update operations. Waiting for commands..."
  exec tail -f /dev/null
fi

# Clean up any legacy locks and dirty flags from previous system usage
echo "🧹 Cleaning up legacy locks and dirty flags..."
if declare -f cleanup_legacy_locks >/dev/null 2>&1; then
  cleanup_legacy_locks "startup"
else
  echo "[WARNING] cleanup_legacy_locks function not found in common.sh"
fi
update_coordination_cleanup || true

# Add random startup delay if enabled
if env_value_is_truthy "${RANDOM_STARTUP_DELAY:-FALSE}"; then
  DELAY=$((RANDOM % 10 + 1))
  echo "🕐 Random startup delay enabled. Waiting ${DELAY} seconds before proceeding..."
  sleep ${DELAY}
fi

# Check if the server needs an update before starting
ensure_server_files_ready() {
  echo "🔍 Ensuring server files are present and up to date..."
  if /home/pok/scripts/install_server.sh; then
    echo "✅ Server files verified."
    return 0
  else
    local exit_code=$?
    echo "❌ Server install/update helper exited with status $exit_code"
    echo "   Aborting startup to avoid running with inconsistent files."
    exit $exit_code
  fi
}

# Add disk space cleanup function to remove non-essential data
cleanup_disk_space() {
  echo "🧹 Performing disk space cleanup..."

  rotate_log_files 5 "${ASA_DIR}/ShooterGame/Saved/Logs" "*.log" "ShooterGame.log" || true
  rotate_log_files 5 "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" "*.log" || true
  clean_temp_files
  
  # Remove old PID files if present
  if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE" 2>/dev/null || true
  fi
  
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

# Check for updates before launching the server
if [ "${UPDATE_SERVER^^}" = "TRUE" ]; then
  ensure_server_files_ready
elif [ ! -f "$PERSISTENT_ACF_FILE" ]; then
  echo "⚠️ UPDATE_SERVER disabled but no installation found. Running installer once..."
  ensure_server_files_ready
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
  export WINEDLLOVERRIDES="*version=n,b;vcrun2022=n,b"
  export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
}

# Robust AsaApi initialization for container environment
verify_proton_environment() {
  echo "----Robust Proton Environment Verification for AsaApi----"

  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser"

  if ! resolve_pinned_proton; then
    echo "ERROR: The image-pinned Proton installation failed verification." >&2
    return 1
  fi
  echo "Using image-pinned Proton: $POK_PROTON_VERSION"
  echo "Proton executable: $POK_PROTON_EXECUTABLE"

  echo "Force resetting Proton prefix for clean environment..."
  initialize_proton_prefix || return 1

  echo "Setting correct permissions for top-level directories..."
  chmod 755 "${STEAM_COMPAT_DATA_PATH}"
  chmod 755 "$(dirname "$POK_PROTON_DIR")"

  sync
  sleep 3

  echo "Testing Wine functionality..."
  if WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine --version >/dev/null 2>&1; then
    echo "Wine is functional in the environment."
  else
    echo "WARNING: Wine does not appear to be functioning correctly."
    export LD_LIBRARY_PATH="/usr/lib/wine:/usr/lib32/wine:$LD_LIBRARY_PATH"
  fi

  echo "Proton environment verification completed."
}

# Set up virtual display
setup_virtual_display

echo ""
echo "🔍 Running environment checks..."
# Run comprehensive pre-launch environment check
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

# Inject required DLL before initializing Proton/Wine to ensure it's present
if [ -f "/home/pok/require_files/xaudio2_9redist.dll" ]; then
  echo "Copying required xaudio2_9redist.dll into binaries folder..."
  mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/"
  
  # Copy as original redistributable name
  cp -f "/home/pok/require_files/xaudio2_9redist.dll" "${ASA_DIR}/ShooterGame/Binaries/Win64/xaudio2_9redist.dll"
  chmod 755 "${ASA_DIR}/ShooterGame/Binaries/Win64/xaudio2_9redist.dll"
  
  # Also copy as standard xaudio2_9.dll (some mods explicitly look for this name)
  cp -f "/home/pok/require_files/xaudio2_9redist.dll" "${ASA_DIR}/ShooterGame/Binaries/Win64/xaudio2_9.dll"
  chmod 755 "${ASA_DIR}/ShooterGame/Binaries/Win64/xaudio2_9.dll"
fi

# Initialize Proton environment regardless of API setting
if ! verify_proton_environment; then
  echo "❌ ERROR: Pinned Proton environment verification failed." >&2
  exit 1
fi

# Install/Update AsaApi if API=TRUE
if [ "${API}" = "TRUE" ]; then
  echo ""
  echo "🔌 Initializing AsaApi plugin system..."
  
  # Install the selected API source and prepare its cache before any Wine
  # invocation, including the loader preflight below.
  ensure_ark_server_api_ready
  
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
if env_value_is_truthy "${UPDATE_SERVER:-FALSE}" && \
    { [ "${API}" != "TRUE" ] || rollback_state_is_active; }; then
  echo "[INFO] Starting update monitor in background..."
  # Remove residual stop flag from previous container run before launching monitor
  rm -f /home/pok/stop_monitor.flag 2>/dev/null || true
  
  if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
    # When display is enabled, redirect output to both console and log file
    nohup /home/pok/scripts/monitor_ark_server.sh > >(tee -a /home/pok/logs/monitor.log) 2>&1 &
  else
    # When display is disabled, redirect output only to log file
    nohup /home/pok/scripts/monitor_ark_server.sh > /home/pok/logs/monitor.log 2>&1 &
  fi
  
  MONITOR_PID=$!
  echo "[INFO] Update monitor started with PID: $MONITOR_PID"
elif [ "${API}" = "TRUE" ] && env_value_is_truthy "${UPDATE_SERVER:-FALSE}"; then
  echo "⚠️ [WARNING] Update monitor is disabled when API=TRUE"
  echo "⚠️ [WARNING] You must manually update the server using the POK-manager.sh script with:"
  echo "⚠️           ./POK-manager.sh -stop <instance_name>"
  echo "⚠️           ./POK-manager.sh -start <instance_name>"
fi

# Keep PID 1 interruptible so SIGTERM runs the verified shutdown handler. A
# foreground `tail -f /dev/null` can prevent Bash from processing the trap.
while true; do
  sleep 86400 &
  wait $! || true
done
