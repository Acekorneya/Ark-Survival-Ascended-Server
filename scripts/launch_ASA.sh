#!/bin/bash
#
# ARK server launcher and startup verifier. This is the authoritative path for
# first-process startup, log monitoring, and leader-ready signaling.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/rcon_commands.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/shutdown_server.sh"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/update_coordination.sh"

LAUNCH_ASA_ADVERTISING_MARKER="Server has completed startup and is now advertising for join"
LAUNCH_ASA_FULL_STARTUP_MARKER="Full Startup:"
LAUNCH_ASA_READY_MARKER_TYPE=""

start_log_tail() {
  local log_file="$1"
  local pid_variable="$2"

  # Stream the complete file directly to container stdout. Following by name
  # keeps the mirror alive when ASA replaces or rotates its log file.
  tail -n +1 -F "$log_file" &
  printf -v "$pid_variable" '%s' "$!"
}

launch_asa_detect_ready_marker() {
  local log_file="$1"

  LAUNCH_ASA_READY_MARKER_TYPE=""
  [ -f "$log_file" ] || return 1

  if grep -qF "$LAUNCH_ASA_FULL_STARTUP_MARKER" "$log_file"; then
    LAUNCH_ASA_READY_MARKER_TYPE="full_startup"
    return 0
  fi

  if grep -qF "$LAUNCH_ASA_ADVERTISING_MARKER" "$log_file"; then
    LAUNCH_ASA_READY_MARKER_TYPE="advertising"
    return 0
  fi

  return 1
}

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

# Function to find and update the server process ID
get_server_process_id() {
  # Get the current PID if available
  if [ -n "$SERVER_PID" ] && ps -p "$SERVER_PID" > /dev/null 2>&1; then
    # Current PID is valid, just return it
    return 0
  fi
  
  # Try to find the server process
  local detected_pid=""
  
  # First check if AsaApiLoader is running (when API=TRUE)
  if [ "${API}" = "TRUE" ]; then
    detected_pid=$(ps aux | grep -v grep | grep "AsaApiLoader.exe" | awk '{print $2}' | head -1)
  fi
  
  # If not found, try the main server executable
  if [ -z "$detected_pid" ]; then
    detected_pid=$(ps aux | grep -v grep | grep "ArkAscendedServer.exe" | awk '{print $2}' | head -1)
  fi
  
  # Update SERVER_PID if a process was found
  if [ -n "$detected_pid" ]; then
    SERVER_PID="$detected_pid"
    echo "Updated SERVER_PID to: $SERVER_PID"
  else
    echo "WARNING: Could not find running server process"
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
  "TheCenter")
    MAP_PATH="TheCenter_WP"
    ;;
  "Aberration")
    MAP_PATH="Aberration_WP"
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

# Set up ArkServerAPI environment if API is enabled
setup_arkserverapi() {
  if [ "${API}" = "TRUE" ]; then
    echo "Setting up AsaApi environment..."
    
    # Define paths to match test_script.sh
    local ASA_BINARY_DIR="${ASA_DIR}/ShooterGame/Binaries/Win64"
    local ASA_PLUGIN_BINARY_NAME="AsaApiLoader.exe"
    local ASA_PLUGIN_BINARY_PATH="$ASA_BINARY_DIR/$ASA_PLUGIN_BINARY_NAME"
    local ASA_PLUGIN_LOADER_ARCHIVE_NAME=$(basename $ASA_BINARY_DIR/AsaApi_*.zip 2>/dev/null)

    # Prepare the selected API source and its executable-specific cache before
    # Wine starts. This deliberately bypasses AsaApi's Windows HTTPS client.
    if ! ensure_ark_server_api_ready; then
      echo "ERROR: AsaApi source or cache preparation did not complete."
      return 1
    fi
    
    # Make sure the directory exists
    mkdir -p "$ASA_BINARY_DIR"
    
    # Check if we have an archive file that needs extraction
    if [ -n "$ASA_PLUGIN_LOADER_ARCHIVE_NAME" ] && [ -f "$ASA_BINARY_DIR/$ASA_PLUGIN_LOADER_ARCHIVE_NAME" ]; then
      echo "Found AsaApi archive: $ASA_PLUGIN_LOADER_ARCHIVE_NAME, extracting..."
      cd "$ASA_BINARY_DIR"
      unzip -o "$ASA_PLUGIN_LOADER_ARCHIVE_NAME" >/dev/null 2>&1
      rm -f "$ASA_PLUGIN_LOADER_ARCHIVE_NAME"
    fi
    
    # Make sure the AsaApiLoader exists
    if [ ! -f "$ASA_PLUGIN_BINARY_PATH" ]; then
      echo "AsaApiLoader.exe not found. Attempting installation via common.sh..."
      # Try up to 3 times to install
      local max_attempts=3
      local attempt=1
      local success=false
      
      while [ $attempt -le $max_attempts ] && [ "$success" = "false" ]; do
        echo "AsaApi installation attempt $attempt of $max_attempts..."
        if install_ark_server_api; then
          success=true
          echo "✅ AsaApi installation succeeded on attempt $attempt"
        else
          echo "⚠️ AsaApi installation attempt $attempt failed"
          attempt=$((attempt + 1))
          sleep 2
        fi
      done
      
      # Re-check if the file exists after installation attempt
      if [ ! -f "$ASA_PLUGIN_BINARY_PATH" ]; then
        echo "ERROR: AsaApiLoader.exe still not found after $max_attempts installation attempts."
        echo "⚠️ Continuing without AsaApi. Server will run but API functionality will be unavailable."
        return 1
      else
        echo "✅ AsaApiLoader.exe found after installation."
      fi
    else
      echo "✅ AsaApiLoader.exe found at $ASA_PLUGIN_BINARY_PATH"
    fi
    
    # Verify if Visual C++ Redistributable might be installed in the Proton prefix
    local vcredist_marker="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio"
    
    if [ ! -d "$vcredist_marker" ]; then
      echo "Visual C++ Redistributable marker not found. Creating directory structure..."
      mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT"
      mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT"
    else
      echo "Visual C++ Redistributable directory structure exists."
    fi

    # Ensure dummy files exist to satisfy AsaApi loader expectations
    touch "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/msvcp140.dll"
    touch "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/vcruntime140.dll"
    touch "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT/msvcp140.dll"
    touch "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT/vcruntime140.dll"

    # If actual redistributable DLLs are missing, attempt a silent reinstall
    if [ ! -f "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/SysWOW64/msvcp140.dll" ] || \
       [ ! -f "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/SysWOW64/vcruntime140.dll" ] || \
       [ ! -f "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/msvcp140.dll" ] || \
       [ ! -f "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/vcruntime140.dll" ]; then
      echo "Visual C++ runtime DLLs missing; running winetricks vcrun2022..."
      WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" winetricks -q vcrun2022 >/dev/null 2>&1 || true
    fi
    
    # Set DLL overrides to ensure API loads properly
    export WINEDLLOVERRIDES="version=n,b"
    echo "Set DLL overrides for AsaApi"
    
    # Create logs directory for AsaApi if it doesn't exist
    mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    
    echo "AsaApi environment setup completed."
    return 0
  fi
  return 0
}

start_server() {
  # Fix for Docker Compose exec / Docker exec parsing inconsistencies
  STEAM_COMPAT_DATA_PATH=$(eval echo "$STEAM_COMPAT_DATA_PATH")

  # Rotate old logs to prevent disk space issues
  echo "Performing log rotation to manage disk space..."
  rotate_log_files 5 "${ASA_DIR}/ShooterGame/Saved/Logs" "*.log" "ShooterGame.log"
  rotate_log_files 5 "${ASA_DIR}/ShooterGame/Binaries/Win64/logs" "*.log"
  
  # Clean temporary files to free up disk space
  clean_temp_files

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
  local cluster_id_arg=""
  local server_password_arg=""
  local session_name_arg="SessionName=\"${SESSION_NAME}\""
  local notify_admin_commands_arg=""

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
    rcon_args="RCONEnabled=True?RCONPort=${RCON_PORT}"
  elif [ "$RCON_ENABLED" = "FALSE" ]; then
    rcon_args="RCONEnabled=False"
  fi

  if [ -n "$CUSTOM_SERVER_ARGS" ]; then
    custom_args="$CUSTOM_SERVER_ARGS"
  fi

  if [ -n "$SERVER_PASSWORD" ]; then
    server_password_arg="?ServerPassword=${SERVER_PASSWORD}"
  fi

  if [ -n "$CLUSTER_ID" ]; then
    cluster_id_arg="-clusterid=${CLUSTER_ID}"
  fi
  
  # Set NotifyAdminCommandsInChat flag based on environment variable
  if [ "$SHOW_ADMIN_COMMANDS_IN_CHAT" = "TRUE" ]; then
    notify_admin_commands_arg="-NotifyAdminCommandsInChat"
  fi

  # Check if the server files exist
  if [ ! -f "/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ]; then
    echo "Error: Server files not found. Please ensure the server is properly installed."
    exit 1
  fi
  
  # Setup ArkServerAPI if enabled
  local LAUNCH_BINARY_NAME="ArkAscendedServer.exe"
  if [ "${API}" = "TRUE" ]; then
    setup_arkserverapi
    # If AsaApiLoader.exe exists, use it instead
    if [ -f "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
      LAUNCH_BINARY_NAME="AsaApiLoader.exe"
      echo "Using AsaApiLoader.exe for server start..."
    else
      echo "WARNING: AsaApiLoader.exe not found, falling back to standard executable."
    fi
  fi
  
  # Handle CPU optimization with backward compatibility
  local CPU_OPT="${CPU_OPTIMIZATION:-FALSE}"
  if [ "$CPU_OPT" = "TRUE" ]; then
    echo "🔧 CPU optimization enabled - applying Proton/Wine performance tweaks..."
    export PROTON_NO_ESYNC=1
    export PROTON_NO_FSYNC=1
    export WINEDEBUG=-all
    export WINE_CPU_TOPOLOGY=FALSE
    echo "   - PROTON_NO_ESYNC=1 (disables eventfd-based synchronization)"
    echo "   - PROTON_NO_FSYNC=1 (disables fsync-based synchronization)"
    echo "   - WINEDEBUG=-all (disables Wine debug messages)"
    echo "   - WINE_CPU_TOPOLOGY=FALSE (prevents CPU topology detection)"
  else
    echo "🔧 CPU optimization disabled (default)"
  fi
  
  # Construct server parameters
  local server_params="$MAP_PATH?listen?$session_name_arg?${rcon_args}${server_password_arg}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD} -Port=${ASA_PORT} -WinLiveMaxPlayers=${MAX_PLAYERS} $cluster_id_arg -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs $notify_admin_commands_arg $custom_args $mods_arg $battleye_arg $passive_mods_arg"
  
  # Change to the binary directory
  cd "${ASA_DIR}/ShooterGame/Binaries/Win64"

  # Health checks use this timestamp to reject an API success message left by
  # an earlier server process. The API log must be updated after this launch
  # checkpoint before managed AsaApi can be reported healthy.
  if [ "$LAUNCH_BINARY_NAME" = "AsaApiLoader.exe" ]; then
    : > "${ASAAPI_LAUNCH_MARKER:-/tmp/pok_asaapi_launch_started}"
  fi

  # Defensive cleanup: Remove problematic Steam DLL files that interfere with Proton/Wine
  echo "[INFO] Performing pre-launch Steam DLL cleanup..."
  rm -f steamclient.dll steamclient64.dll tier0_s.dll tier0_s64.dll vstdlib_s.dll vstdlib_s64.dll 2>/dev/null || true

  local PROTON_EXECUTABLE=""
  echo "Resolving image-pinned Proton installation..."
  if ! resolve_pinned_proton; then
    echo "ERROR: Image-pinned Proton installation is unavailable or mismatched."
    exit 1
  fi
  PROTON_EXECUTABLE="$POK_PROTON_EXECUTABLE"
  echo "Using pinned Proton $POK_PROTON_VERSION: $PROTON_EXECUTABLE"
  
  # Set crucial Wine DLL overrides - this is very important for AsaApiLoader.exe
  export WINEDLLOVERRIDES="version=n,b"
  
  # Ensure proper environment variables are set
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
  export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
  
  echo "Cleaning up any problematic Steam DLLs before launch..."
  # Use the function from common.sh if available
  if type cleanup_steam_dlls >/dev/null 2>&1; then
    cleanup_steam_dlls "$ASA_DIR"
  fi
  
  echo "Launching server..."
  
  # Save the current directory to return to it after launching the server
  local current_dir=$(pwd)
  
  # Ensure the dosdevices directory and symlinks are set up properly
  # This is key to fixing the error when API=FALSE
  ensure_dosdevices_setup
  
  # Additional setup to ensure AsaApi environment is fully prepared
  if [ "$LAUNCH_BINARY_NAME" = "AsaApiLoader.exe" ]; then
    echo "Setting up additional AsaApi environment variables..."
    mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Binaries/Win64"
    
    # For AsaApiLoader, ensure missing registry entries don't cause issues
    if [ -f "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg" ]; then
      if ! grep -q "vcrun2022" "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"; then
        echo "Adding vcrun2022 DLL override to Wine registry..."
        echo "[Software\\\\Wine\\\\DllOverrides]" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
        echo "\"vcrun2022\"=\"native,builtin\"" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
      fi
    fi
    
    # Verify Visual C++ Redistributable installation
    if [ ! -d "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio" ]; then
      echo "Visual C++ Redistributable not detected, creating directory structure..."
      # Create directory structure to make AsaApiLoader believe VC++ is installed
      local vc_dir="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio"
      mkdir -p "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT"
      mkdir -p "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT"

      # Create dummy files
      touch "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/msvcp140.dll"
      touch "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/vcruntime140.dll"
    fi
    
    # Sync to ensure all changes are written
    sync
    sleep 2
    
    # Add first-time launch detection and notification
    local first_launch_file="/home/pok/.first_launch_completed"
    local container_launch_file="/home/pok/.container_launched"
    local is_first_launch=false
    
    # Only show first launch message if both conditions are true:
    # 1. First time running the server (no .first_launch_completed file)
    # 2. First time in this container instance (no .container_launched file)
    if [ ! -f "$first_launch_file" ] && [ ! -f "$container_launch_file" ]; then
      is_first_launch=true
      echo ""
      echo "🔍 FIRST-TIME LAUNCH DETECTED"
      echo "⚠️ The first server launch may take longer and could potentially fail"
      echo "🔄 If the first launch fails, the system will automatically restart"
      echo "   and complete setup on the second attempt (this is normal behavior)"
      echo "⏱️ Please be patient during the first launch process"
      echo ""
    fi
    
    # Always create the container_launched file to mark this container as having been run before
    touch "$container_launch_file"
    
    # Define a function to make a launch attempt
    attempt_launch() {
      local method="$1"
      local binary="$2"
      local params="$3"
      
      echo "[INFO] Attempting launch using method: $method"
      
      # Check for persistent first-launch completed marker
      # Create a permanent config directory that persists across container restarts
      local config_dir="${ASA_DIR}/ShooterGame/Saved/Config/FirstLaunchFlags"
      local api_first_launch_file="${config_dir}/api_first_launch_completed"
      local standard_first_launch_file="${config_dir}/standard_first_launch_completed"
      
      # Create config directory if it doesn't exist
      mkdir -p "$config_dir" 2>/dev/null || true
      
      # Determine if this is genuinely a first launch
      local is_first_launch=false
      if [ "${API}" = "TRUE" ] && [ ! -f "$api_first_launch_file" ]; then
        is_first_launch=true
      elif [ "${API}" != "TRUE" ] && [ ! -f "$standard_first_launch_file" ]; then
        is_first_launch=true
      fi
      
      # Only show first launch message if this is genuinely a first launch
      if [ "$is_first_launch" = "true" ]; then
        echo ""
        echo "🔍 FIRST-TIME LAUNCH DETECTED"
        echo "⚠️ The first server launch may take longer and could potentially fail"
        echo "🔄 If the first launch fails, the system will automatically restart"
        echo "   and complete setup on the second attempt (this is normal behavior)"
        echo "⏱️ Please be patient during the first launch process"
        echo ""
      fi
      
      # Define a function to mark first launch as completed
      mark_first_launch_completed() {
        if [ "${API}" = "TRUE" ]; then
          touch "$api_first_launch_file"
        else
          touch "$standard_first_launch_file"
        fi
        # Also maintain backward compatibility with the home directory flag
        touch "/home/pok/.first_launch_completed"
      }
      
      if [ "$is_first_launch" = "true" ]; then
        # Define status variables
        local start_time=$(date +%s)
        local max_wait=30
        local waited=0
        
        # Launch with background process to allow monitoring
        case "$method" in
          "proton_direct")
            if [ -f "$PROTON_EXECUTABLE" ]; then
              # Set DISPLAY variable to prevent X server errors
              export DISPLAY=:0.0
              # Method 1: Direct Proton launch using found executable
              "$PROTON_EXECUTABLE" run "$binary" $params > /tmp/launch_output.log 2>&1 &
            else
              echo "[WARNING] Proton executable not found, skipping this method."
              return 1
            fi
            ;;
          "proton_retry")
            export DISPLAY=:0.0
            echo "[INFO] Retrying launch with pinned Proton $POK_PROTON_VERSION"
            "$PROTON_EXECUTABLE" run "$binary" $params > /tmp/launch_output.log 2>&1 &
            ;;
        esac
        
        local pid=$!
        echo "[INFO] Launch attempt started with PID: $pid"
        
        # Wait for process to start - use less frequent status updates with cleaner format
        echo "[INFO] Waiting up to ${max_wait} seconds for server process to initialize..."
        
        while [ $waited -lt $max_wait ]; do
          # Check every 5 seconds without a spinner animation
          sleep 5
          waited=$((waited + 5))
          
          # Only log status at specific intervals
          if [ $((waited % 10)) -eq 0 ]; then
            echo "[INFO] Waiting for server initialization... (${waited}s elapsed)"
          fi
          
          # Check for ARK processes which indicate successful launch
          if pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 || pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
            LAUNCH_ATTEMPT_PID=$(pgrep -f "AsaApiLoader.exe|ArkAscendedServer.exe" | head -n 1)
            echo "[SUCCESS] ARK Server process detected with PID: $LAUNCH_ATTEMPT_PID"
            break
          fi

          if ! kill -0 "$pid" 2>/dev/null; then
            echo "[ERROR] Proton launcher exited before an ARK process appeared (${waited}s)"
            break
          fi
        done

        if [ -n "${LAUNCH_ATTEMPT_PID:-}" ]; then
          echo "[SUCCESS] Launch successful using method: $method (${waited}s)"
          mark_first_launch_completed
          return 0
        else
          kill -TERM "$pid" 2>/dev/null || true
          echo "[ERROR] Launch failed using method: $method after ${waited}s"
          # Check if this was a MSVCP140.dll error
          if grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" /tmp/launch_output.log 2>/dev/null; then
            echo "[WARNING] DETECTED MSVCP140.dll LOADING ERROR:"
            echo "[INFO] This is a common first-launch error that should resolve on restart"
            # Create a flag file so monitor can detect this specific error
            echo "MSVCP140.dll loading error detected on first launch" > /home/pok/.first_launch_msvcp140_error
          else
            # Show the last few lines of output for debugging
            echo "[INFO] Last output from launch attempt:"
            tail -5 /tmp/launch_output.log 2>/dev/null
          fi
          return 1
        fi
      else
        # Non-first launch - use cleaner progress updates without spinners
        # Launch with the chosen method
        case "$method" in
          "proton_direct")
            if [ -f "$PROTON_EXECUTABLE" ]; then
              # Set DISPLAY variable to prevent X server errors
              export DISPLAY=:0.0
              # Method 1: Direct Proton launch using found executable
              "$PROTON_EXECUTABLE" run "$binary" $params > /tmp/launch_output.log 2>&1 &
            else
              echo "[WARNING] Proton executable not found, skipping this method."
              return 1
            fi
            ;;
          "proton_retry")
            export DISPLAY=:0.0
            echo "[INFO] Retrying launch with pinned Proton $POK_PROTON_VERSION"
            "$PROTON_EXECUTABLE" run "$binary" $params > /tmp/launch_output.log 2>&1 &
            ;;
        esac
        
        local pid=$!
        echo "[INFO] Launch attempt started with PID: $pid"
        
        # Wait a moment to see if the process starts, with minimal status updates
        echo "[INFO] Waiting for server initialization..."
        sleep 5
        
        LAUNCH_ATTEMPT_PID=""
        if pgrep -f "AsaApiLoader.exe" >/dev/null 2>&1 || pgrep -f "ArkAscendedServer.exe" >/dev/null 2>&1; then
          LAUNCH_ATTEMPT_PID=$(pgrep -f "AsaApiLoader.exe|ArkAscendedServer.exe" | head -n 1)
          echo "[SUCCESS] ARK Server process detected with PID: $LAUNCH_ATTEMPT_PID"
        fi

        if [ -n "$LAUNCH_ATTEMPT_PID" ]; then
          echo "[SUCCESS] Launch successful using method: $method"
          mark_first_launch_completed
          return 0
        else
          kill -TERM "$pid" 2>/dev/null || true
          echo "[ERROR] Launch failed using method: $method"
          # Check if this was a MSVCP140.dll error
          if grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" /tmp/launch_output.log 2>/dev/null; then
            echo "[WARNING] DETECTED MSVCP140.dll LOADING ERROR - Flagging for automatic restart"
            # Create a flag file so monitor can detect this specific error
            echo "MSVCP140.dll loading error detected on first launch" > /home/pok/.first_launch_msvcp140_error
          fi
          return 1
        fi
      fi
    }
    
    # Try different launch methods for AsaApiLoader with better fallbacks
    SERVER_PID=""
    
    LAUNCH_ATTEMPT_PID=""
    if attempt_launch "proton_direct" "$LAUNCH_BINARY_NAME" "$server_params"; then
      SERVER_PID="$LAUNCH_ATTEMPT_PID"
    elif attempt_launch "proton_retry" "$LAUNCH_BINARY_NAME" "$server_params"; then
      SERVER_PID="$LAUNCH_ATTEMPT_PID"
    else
      # As a last resort, try launching the regular server executable
      echo "All AsaApiLoader launch attempts failed. Falling back to standard server executable..."
      LAUNCH_BINARY_NAME="ArkAscendedServer.exe"
      
      # Try the same sequence of methods with the standard executable
      LAUNCH_ATTEMPT_PID=""
      if attempt_launch "proton_direct" "$LAUNCH_BINARY_NAME" "$server_params"; then
        SERVER_PID="$LAUNCH_ATTEMPT_PID"
      elif attempt_launch "proton_retry" "$LAUNCH_BINARY_NAME" "$server_params"; then
        SERVER_PID="$LAUNCH_ATTEMPT_PID"
      else
        echo "ERROR: All launch attempts failed! Server could not be started."
        echo "This is likely a first boot issue. The monitor process will automatically restart the server."
        echo "Please wait for the automatic restart to complete."
        # Create a flag file to indicate this is the first launch error
        echo "First launch error detected at $(date)" > /home/pok/.first_launch_error
        exit 1
      fi
    fi
  else
    SERVER_PID=""
    local launch_attempt
    local proton_launcher_pid

    for launch_attempt in 1 2; do
      if [ "$launch_attempt" -eq 1 ]; then
        echo "Launching with pinned Proton $POK_PROTON_VERSION"
      else
        echo "Retrying launch with pinned Proton $POK_PROTON_VERSION"
      fi
      "$PROTON_EXECUTABLE" run "$LAUNCH_BINARY_NAME" $server_params &
      proton_launcher_pid=$!
      sleep 5

      SERVER_PID=$(pgrep -f "ArkAscendedServer.exe" | head -n 1 || true)
      if [ -n "$SERVER_PID" ]; then
        echo "Server process detected with PID $SERVER_PID using pinned Proton $POK_PROTON_VERSION."
        break
      fi

      kill -TERM "$proton_launcher_pid" 2>/dev/null || true
      SERVER_PID=""
    done

    if [ -z "$SERVER_PID" ]; then
      echo "ERROR: Both launch attempts with pinned Proton $POK_PROTON_VERSION failed."
      exit 1
    fi
  fi
  
  echo "Server process started with PID: $SERVER_PID"

  # Immediate write to PID file
  echo $SERVER_PID > $PID_FILE
  echo "PID $SERVER_PID written to $PID_FILE"

  # ===== IMPROVED LOGGING SECTION =====
  echo ""
  echo "====== ARK SERVER IS STARTING UP ======"
  echo "This may take a few minutes. Please be patient..."
  echo ""
  
  display_server_logs() {
    local game_log="${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
    local api_log_dir="${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    local api_log=""
    local max_wait=120
    local check_interval=3
    local elapsed=0
    local api_elapsed=0

    echo "📊 MONITORING SERVER LOGS"
    echo "---------------------------------------------"

    unset API_TAIL_PID
    unset GAME_TAIL_PID
    unset LOGS_DISPLAY_PID

    if [ "${API}" = "TRUE" ]; then
      echo "🔍 Looking for AsaApi logs (API is enabled)..."
      while [ $api_elapsed -lt $max_wait ]; do
        api_log="$(find "$api_log_dir" \( -name "ArkApi_*.log" -o -name "ArkApi.log" -o -name "AsaApi.log" \) -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
        if [ -n "$api_log" ] && [ -f "$api_log" ]; then
          echo ""
          echo "✅ Found AsaApi logs: $(basename "$api_log")"
          echo "---------------------------------------------"
          echo "📋 ASAAPI LOG OUTPUT:"
          echo "---------------------------------------------"
          start_log_tail "$api_log" API_TAIL_PID
          break
        fi
        printf "\r🔍 Waiting for AsaApi logs... (%ds elapsed)      " "$api_elapsed"
        sleep $check_interval
        api_elapsed=$((api_elapsed + check_interval))
      done

      if [ $api_elapsed -ge $max_wait ] && [ ! -f "$api_log" ]; then
        echo ""
        echo "⚠️ No AsaApi logs found after ${max_wait}s."
      fi
    fi

    echo "🔍 Looking for ShooterGame logs..."
    while [ $elapsed -lt $max_wait ]; do
      if [ -f "$game_log" ]; then
        echo ""
        echo "✅ Found ShooterGame.log"
        echo "---------------------------------------------"
        echo "📋 ARK SERVER LOG OUTPUT:"
        echo "---------------------------------------------"
        start_log_tail "$game_log" GAME_TAIL_PID
        return 0
      fi
      printf "\r🔍 Waiting for ShooterGame.log... (%ds elapsed)      " "$elapsed"
      sleep $check_interval
      elapsed=$((elapsed + check_interval))
    done

    echo ""
    echo "⚠️ ShooterGame.log not found after ${max_wait}s."
    echo "  → Once available, logs will be located at: $game_log"
    return 1
  }

  if [ "${API}" = "TRUE" ] && [ -f "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
    echo "🔌 Starting server with AsaApi enabled"
  elif [ "${API}" = "TRUE" ]; then
    echo "⚠️ AsaApiLoader.exe not found, launching without AsaApi"
  else
    echo "ℹ️ AsaApi is disabled, launching normal server"
  fi
  display_server_logs

  # Wait for the server to fully start, monitoring the log file
  echo ""
  echo "====== VERIFYING SERVER STARTUP ======"
  echo "[INFO] Waiting for server to become fully operational..."
  update_coordination_cleanup || true
  local LOG_FILE="$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
  local max_wait_time=600  # 10 minutes maximum wait time (increased from 300 to ensure we catch the log message)
  local wait_time=0
  local startup_message_displayed=false
  local logs_shown_timestamp=0
  local logs_display_interval=60  # Show logs every 60 seconds
  local server_id=""
  
  # Check for SERVER ID in API logs if API is enabled
  if [ "${API}" = "TRUE" ]; then
    local api_log_dir="${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    if [ -d "$api_log_dir" ]; then
      # Find the most recent API log file
      local latest_api_log=$(find "$api_log_dir" -name "ArkApi_*.log" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
      if [ -n "$latest_api_log" ] && [ -f "$latest_api_log" ]; then
        # Set up a background process to check for SERVER ID
        (
          local max_check_time=300  # 5 minutes
          local check_interval=5
          local elapsed=0
          
          while [ $elapsed -lt $max_check_time ]; do
            if grep -q "SERVER ID:" "$latest_api_log"; then
              # Extract SERVER ID and save it
              server_id=$(grep "SERVER ID:" "$latest_api_log" | head -1 | grep -o "SERVER ID: [0-9]*" | cut -d' ' -f3)
              if [ -n "$server_id" ]; then
                echo "$server_id" > /tmp/ark_server_id
                break
              fi
            fi
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
          done
        ) &
        SERVER_ID_CHECK_PID=$!
      fi
    fi
  fi
  
  # Initial delay to give the server time to start creating logs
  sleep 10
  
  # Log status variables
  local last_status_time=0
  local status_interval=30
  
  # Retry loop for server verification - with cleaner status updates
  while [ $wait_time -lt $max_wait_time ]; do
    if update_coordination_enabled && update_coordination_is_active_leader; then
      update_coordination_touch_heartbeat >/dev/null 2>&1 || true
    fi

    # Check if server process is running
    if ! ps -p $SERVER_PID > /dev/null; then
      echo "[ERROR] Server process ($SERVER_PID) is no longer running!"
      echo "[ERROR] Server failed to start properly. Check logs for errors."
      
      # If log file exists, show the last 20 lines
      if [ -f "$LOG_FILE" ]; then
        echo "[INFO] Last 20 lines of log file:"
        tail -n 20 "$LOG_FILE"
      fi
      exit 1
    fi
    
    # Display status only at regular intervals in a more monitoring-friendly format
    if [ "$startup_message_displayed" = "false" ] && { [ $wait_time -eq 0 ] || [ $((wait_time - last_status_time)) -ge $status_interval ]; }; then
      echo "[INFO] SERVER STARTUP: Waiting for server to complete initialization (${wait_time}s elapsed)"
      last_status_time=$wait_time
    fi
    
    # Check for successful server startup in logs
    if [ -f "$LOG_FILE" ]; then
      if launch_asa_detect_ready_marker "$LOG_FILE"; then
        if [ "$startup_message_displayed" = "false" ]; then
          # Use a clear message format that works well in all monitoring tools
          echo "=========================================================="
          if [ "$LAUNCH_ASA_READY_MARKER_TYPE" = "full_startup" ]; then
            echo "[SUCCESS] Full Startup marker detected in ShooterGame.log!"
          else
            echo "[SUCCESS] ${LAUNCH_ASA_ADVERTISING_MARKER}!"
          fi
          echo ""
          echo "🎮 ====== SERVER FULLY STARTED ====== 🎮"
          echo "[INFO] Server started successfully. PID: $SERVER_PID"
          if [ "$LAUNCH_ASA_READY_MARKER_TYPE" = "full_startup" ]; then
            echo "[INFO] Server completed the first full startup pass and is ready to release waiting followers."
          else
            echo "[INFO] Server is now advertising for join and ready to accept connections!"
          fi
          
          # Display SERVER ID if available
          if [ "${API}" = "TRUE" ]; then
            # First check if we already have the ID from the background process
            if [ -f "/tmp/ark_server_id" ]; then
              server_id=$(cat /tmp/ark_server_id)
            else
              # If not, try to grab it directly from API logs
              local api_log_dir="${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
              if [ -d "$api_log_dir" ]; then
                local latest_api_log=$(find "$api_log_dir" -name "ArkApi_*.log" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
                if [ -n "$latest_api_log" ] && [ -f "$latest_api_log" ]; then
                  server_id=$(grep "SERVER ID:" "$latest_api_log" 2>/dev/null | head -1 | grep -o "SERVER ID: [0-9]*" | cut -d' ' -f3)
                fi
              fi
            fi
            
            # Display the server ID if we found it
            if [ -n "$server_id" ]; then
              echo "[INFO] SERVER ID: $server_id"
            fi
          fi
          
          startup_message_displayed=true
          
          # Create the first_launch_completed file to mark that the server has launched successfully
          if [ "${API}" = "TRUE" ]; then
            # Create a persistent flag in the config directory
            mkdir -p "${ASA_DIR}/ShooterGame/Saved/Config/FirstLaunchFlags" 2>/dev/null
            touch "${ASA_DIR}/ShooterGame/Saved/Config/FirstLaunchFlags/api_first_launch_completed"
          else
            # Create a persistent flag in the config directory
            mkdir -p "${ASA_DIR}/ShooterGame/Saved/Config/FirstLaunchFlags" 2>/dev/null
            touch "${ASA_DIR}/ShooterGame/Saved/Config/FirstLaunchFlags/standard_first_launch_completed"
          fi
          
          # Maintain backward compatibility
          touch "/home/pok/.first_launch_completed"

          # A rollback candidate is trusted only after both the game and every
          # managed AsaApi plugin completed this launch successfully.
          record_successful_api_deployment || true
        fi
        
        # Double verify correct PID file
        get_server_process_id
        
        # Update PID file with proper value
        echo "[INFO] Ensuring PID file is up-to-date with server PID: $SERVER_PID"
        echo "$SERVER_PID" > "$PID_FILE"

        if update_coordination_enabled && update_coordination_is_active_leader; then
          update_coordination_mark_ready || true
        fi
        
        echo "[INFO] Server monitoring is now active."
        break
      else
        if [ "$startup_message_displayed" = "false" ]; then
          # Server still starting up, only show log content at regular intervals using a monitoring-friendly format
          if [ $((wait_time % logs_display_interval)) -eq 0 ] && [ $wait_time -gt 0 ] && [ $wait_time -ne $logs_shown_timestamp ]; then
            echo "[INFO] Server initialization in progress (${wait_time}s elapsed)"
            echo "[INFO] Waiting for startup completion markers: '${LAUNCH_ASA_FULL_STARTUP_MARKER}' or '${LAUNCH_ASA_ADVERTISING_MARKER}'"
            if [ -z "${GAME_TAIL_PID:-}" ]; then
              echo "[INFO] Recent log entries:"
              tail -n 5 "$LOG_FILE"
              echo ""
            fi
            logs_shown_timestamp=$wait_time
          fi
        fi
      fi
    else
      if [ "$startup_message_displayed" = "false" ]; then
        # Only log messages at regular intervals to reduce log spam, using a format that works well in monitoring tools
        if [ $wait_time -eq 0 ] || [ $((wait_time % status_interval)) -eq 0 ]; then
          echo "[INFO] Server log file not created yet. Initialization in progress... (${wait_time}s elapsed)"
        fi
      fi
    fi
    
    # Use a simpler sleep approach with less frequent updates
    sleep 10
    wait_time=$((wait_time + 10))
  done
  
  # If we reached the timeout but didn't find the completion message
  if [ $wait_time -ge $max_wait_time ]; then
    echo "[WARNING] Server verification timed out after ${max_wait_time}s, but process with PID $SERVER_PID is still running."
    echo "[INFO] Considering server as started, but it may not be fully operational yet."
    echo "[INFO] Updating PID file to prevent unnecessary restart attempts."
    echo "$SERVER_PID" > "$PID_FILE"
  fi

  # Wait for the server process to exit
  wait $SERVER_PID
  echo "Server stopped."
  
  # Clean up all background processes
  if [ -n "${GAME_TAIL_PID:-}" ]; then
    kill "$GAME_TAIL_PID" 2>/dev/null || true
    wait "$GAME_TAIL_PID" 2>/dev/null || true
    echo "Stopped tailing ShooterGame.log."
  fi
  
  if [ -n "$LOGS_DISPLAY_PID" ]; then
    kill -TERM $LOGS_DISPLAY_PID 2>/dev/null || true
    echo "Stopped logs display process."
  fi
  
  if [ -n "${API_TAIL_PID:-}" ]; then
    kill "$API_TAIL_PID" 2>/dev/null || true
    wait "$API_TAIL_PID" 2>/dev/null || true
    echo "Stopped tailing AsaApi log."
  fi
  
  if [ -n "$API_CHECK_PID" ]; then
    kill $API_CHECK_PID 2>/dev/null || true
    echo "Stopped API log check process."
  fi
  
  if [ -n "$SERVER_ID_CHECK_PID" ]; then
    kill $SERVER_ID_CHECK_PID 2>/dev/null || true
    echo "Stopped SERVER ID check process."
  fi
  
  # Clean up temporary files
  rm -f /tmp/ark_server_id 2>/dev/null || true
}


# Main function
main() {
  prepare_runtime_env
  trap shutdown_handler SIGTERM
  determine_map_path
  update_game_user_settings
  start_server
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
