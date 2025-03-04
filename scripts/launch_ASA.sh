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
      mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x64/Microsoft.VC142.CRT"
      mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x86/Microsoft.VC142.CRT"
      
      # Create dummy files
      touch "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x64/Microsoft.VC142.CRT/msvcp140.dll"
      touch "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x64/Microsoft.VC142.CRT/vcruntime140.dll"
      
      # Try winetricks installation as a fallback
      echo "Attempting Visual C++ installation via winetricks..."
      WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" winetricks -q vcrun2019 >/dev/null 2>&1 || true
    else
      echo "Visual C++ Redistributable directory structure exists."
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
  
  # Launch the server using proton run directly, similar to test_script.sh
  # Using the same approach as in test_script.sh which we know works
  local STEAM_COMPAT_DIR="/home/pok/.steam/steam/compatibilitytools.d"
  
  # Construct server parameters
  local server_params="$MAP_PATH?listen?$session_name_arg?${rcon_args}${server_password_arg}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD} -Port=${ASA_PORT} -WinLiveMaxPlayers=${MAX_PLAYERS} $cluster_id_arg -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs $notify_admin_commands_arg $custom_args $mods_arg $battleye_arg $passive_mods_arg"
  
  # Change to the binary directory
  cd "${ASA_DIR}/ShooterGame/Binaries/Win64"
  
  # Improved Proton path detection with multiple fallbacks
  local FOUND_PROTON=false
  local PROTON_EXECUTABLE=""
  
  # Define an array of potential Proton directories to check
  local POTENTIAL_PROTON_DIRS=(
    "${STEAM_COMPAT_DIR}/GE-Proton-Current"
    "${STEAM_COMPAT_DIR}/GE-Proton8-21"
    "${STEAM_COMPAT_DIR}/GE-Proton9-25"
  )
  
  # Find a working Proton installation
  echo "Looking for Proton installations..."
  for proton_dir in "${POTENTIAL_PROTON_DIRS[@]}"; do
    if [ -f "$proton_dir/proton" ]; then
      PROTON_EXECUTABLE="$proton_dir/proton"
      PROTON_DIR_NAME=$(basename "$proton_dir")
      echo "Found Proton executable at: $PROTON_EXECUTABLE (directory: $PROTON_DIR_NAME)"
      FOUND_PROTON=true
      break
    fi
  done
  
  # If no Proton found in standard locations, search for any GE-Proton* directory
  if ! $FOUND_PROTON; then
    echo "No Proton found in standard locations, searching for any GE-Proton installation..."
    # Find any GE-Proton* directory
    local ANY_PROTON_DIR=$(find $STEAM_COMPAT_DIR -maxdepth 1 -name "GE-Proton*" -type d | head -n 1)
    
    if [ -n "$ANY_PROTON_DIR" ] && [ -f "$ANY_PROTON_DIR/proton" ]; then
      PROTON_EXECUTABLE="$ANY_PROTON_DIR/proton"
      PROTON_DIR_NAME=$(basename "$ANY_PROTON_DIR")
      echo "Found Proton executable at: $PROTON_EXECUTABLE (directory: $PROTON_DIR_NAME)"
      FOUND_PROTON=true
    else
      echo "WARNING: No Proton installation found. Will try system 'proton' command."
      # Check if system 'proton' command exists
      if command -v proton >/dev/null 2>&1; then
        echo "System 'proton' command exists, will use it."
        PROTON_EXECUTABLE="proton"
        FOUND_PROTON=true
      else
        echo "ERROR: No Proton installation found and no system 'proton' command."
        echo "Creating minimal Proton script as a last resort..."
        
        # Create minimal Proton directory and script as last resort
        mkdir -p "${STEAM_COMPAT_DIR}/GE-Proton-Fallback"
        echo '#!/bin/bash' > "${STEAM_COMPAT_DIR}/GE-Proton-Fallback/proton"
        echo 'export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"' >> "${STEAM_COMPAT_DIR}/GE-Proton-Fallback/proton"
        echo 'wine "$@"' >> "${STEAM_COMPAT_DIR}/GE-Proton-Fallback/proton"
        chmod +x "${STEAM_COMPAT_DIR}/GE-Proton-Fallback/proton"
        
        PROTON_EXECUTABLE="${STEAM_COMPAT_DIR}/GE-Proton-Fallback/proton"
        PROTON_DIR_NAME="GE-Proton-Fallback"
        echo "Created fallback Proton script at: $PROTON_EXECUTABLE"
        FOUND_PROTON=true
      fi
    fi
  fi
  
  # Set crucial Wine DLL overrides - this is very important for AsaApiLoader.exe
  export WINEDLLOVERRIDES="version=n,b"
  
  # Ensure proper environment variables are set
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
  export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
  
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
      if ! grep -q "vcrun2019" "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"; then
        echo "Adding vcrun2019 DLL override to Wine registry..."
        echo "[Software\\\\Wine\\\\DllOverrides]" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
        echo "\"vcrun2019\"=\"native,builtin\"" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
      fi
    fi
    
    # Verify Visual C++ Redistributable installation
    if [ ! -d "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio" ]; then
      echo "Visual C++ Redistributable not detected, creating directory structure..."
      # Create directory structure to make AsaApiLoader believe VC++ is installed
      local vc_dir="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio"
      mkdir -p "$vc_dir/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x64/Microsoft.VC142.CRT"
      mkdir -p "$vc_dir/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x86/Microsoft.VC142.CRT"
      
      # Create dummy files
      touch "$vc_dir/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x64/Microsoft.VC142.CRT/msvcp140.dll"
      touch "$vc_dir/2019/BuildTools/VC/Redist/MSVC/14.29.30133/x64/Microsoft.VC142.CRT/vcruntime140.dll"
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
      
      echo "Attempting launch using method: $method"
      
      if [ "$is_first_launch" = "true" ]; then
        local spinner=('.' '..' '...' '.' '..' '...')
        local i=0
        local start_time=$(date +%s)
        
        # Start the launch process in background
        case "$method" in
          "proton_direct")
            if [ -f "$PROTON_EXECUTABLE" ]; then
              # Set DISPLAY variable to prevent X server errors
              export DISPLAY=:0.0
              # Method 1: Direct Proton launch using found executable
              "$PROTON_EXECUTABLE" run "$binary" $params > /tmp/launch_output.log 2>&1 &
            else
              echo "Proton executable not found, skipping this method."
              return 1
            fi
            ;;
          "proton_fallback")
            # Method 2: Fallback to fixed path
            export DISPLAY=:0.0
            if [ -f "${STEAM_COMPAT_DIR}/GE-Proton8-21/proton" ]; then
              echo "Using GE-Proton8-21 for fallback launch"
              "${STEAM_COMPAT_DIR}/GE-Proton8-21/proton" run "$binary" $params > /tmp/launch_output.log 2>&1 &
            elif [ -f "${STEAM_COMPAT_DIR}/GE-Proton9-25/proton" ]; then
              echo "Using GE-Proton9-25 for fallback launch"
              "${STEAM_COMPAT_DIR}/GE-Proton9-25/proton" run "$binary" $params > /tmp/launch_output.log 2>&1 &
            else
              # Last resort: check for any available GE-Proton directory
              local ANY_PROTON=$(find "${STEAM_COMPAT_DIR}" -name "GE-Proton*" -type d | head -1)
              if [ -n "$ANY_PROTON" ] && [ -f "$ANY_PROTON/proton" ]; then
                echo "Using $ANY_PROTON for fallback launch"
                "$ANY_PROTON/proton" run "$binary" $params > /tmp/launch_output.log 2>&1 &
              else
                echo "Fallback Proton paths not found, skipping this method."
                return 1
              fi
            fi
            ;;
          "proton_command")
            # Method 3: System proton command
            STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam" \
            STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH}" \
            proton run "$binary" $params > /tmp/launch_output.log 2>&1 &
            ;;
          "wine_direct")
            # Method 4: Direct Wine launch with virtual display
            export DISPLAY=:0.0
            # Create virtual display with Xvfb if available
            if command -v Xvfb >/dev/null 2>&1; then
              # Create .X11-unix directory first to avoid errors
              mkdir -p /tmp/.X11-unix 2>/dev/null || true
              chmod 1777 /tmp/.X11-unix 2>/dev/null || true
              
              # Start Xvfb with error output suppressed
              Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
              XVFB_PID=$!
              sleep 2  # Give Xvfb time to start
            fi
            # Add environment variables to help wine find libraries
            export WINEDLLOVERRIDES="*version=n,b;vcrun2019=n,b"
            export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
            WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$binary" $params > /tmp/launch_output.log 2>&1 &
            ;;
        esac
        
        local pid=$!
        echo "Launch attempt PID: $pid"
        
        # Show animated progress indicator for up to 30 seconds
        local max_wait=30
        local waited=0
        local spinner=('.' '..' '...' '.' '..' '...')
        local i=0
        
        while [ $waited -lt $max_wait ]; do
          # Print spinner - don't clear the line with a separate printf, do it in one command
          printf "\r%s Waiting for server startup... (%s seconds elapsed)      " "${spinner[i]}" "$waited"
          i=$(( (i+1) % ${#spinner[@]} ))
          sleep 0.2  # Medium speed for spinner animation
          
          # Only increment wait time every 1 second (5 spinner frames)
          if [ $((i % 5)) -eq 0 ]; then
            waited=$((waited + 1))
          fi
          
          # Check if process is still running
          if ! kill -0 $pid 2>/dev/null; then
            # Process exited early
            break
          fi
        done
        
        # Wait a moment to see if the process starts
        sleep 5
        
        # Check if process is still running
        if kill -0 $pid 2>/dev/null; then
          echo "✅ Launch successful using method: $method (${waited}s)"
          # Create the first launch completed file to skip this next time
          touch "$first_launch_file"
          return 0
        else
          echo "❌ Launch failed using method: $method after ${waited}s"
          # Check if this was a MSVCP140.dll error
          if grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" /tmp/launch_output.log 2>/dev/null; then
            echo "DETECTED MSVCP140.dll LOADING ERROR:"
            echo "This is a common first-launch error that should resolve on restart"
            # Create a flag file so monitor can detect this specific error
            echo "MSVCP140.dll loading error detected on first launch" > /home/pok/.first_launch_msvcp140_error
          else
            # Show the last few lines of output for debugging
            echo "Last output from launch attempt:"
            tail -5 /tmp/launch_output.log 2>/dev/null
          fi
          return 1
        fi
      else
        # Non-first launch - use the original code without progress indicator
        case "$method" in
          "proton_direct")
            if [ -f "$PROTON_EXECUTABLE" ]; then
              # Set DISPLAY variable to prevent X server errors
              export DISPLAY=:0.0
              # Method 1: Direct Proton launch using found executable
              "$PROTON_EXECUTABLE" run "$binary" $params &
            else
              echo "Proton executable not found, skipping this method."
              return 1
            fi
            ;;
          "proton_fallback")
            # Method 2: Fallback to fixed path
            export DISPLAY=:0.0
            if [ -f "${STEAM_COMPAT_DIR}/GE-Proton8-21/proton" ]; then
              echo "Using GE-Proton8-21 for fallback launch"
              "${STEAM_COMPAT_DIR}/GE-Proton8-21/proton" run "$binary" $params &
            elif [ -f "${STEAM_COMPAT_DIR}/GE-Proton9-25/proton" ]; then
              echo "Using GE-Proton9-25 for fallback launch"
              "${STEAM_COMPAT_DIR}/GE-Proton9-25/proton" run "$binary" $params &
            else
              # Last resort: check for any available GE-Proton directory
              local ANY_PROTON=$(find "${STEAM_COMPAT_DIR}" -name "GE-Proton*" -type d | head -1)
              if [ -n "$ANY_PROTON" ] && [ -f "$ANY_PROTON/proton" ]; then
                echo "Using $ANY_PROTON for fallback launch"
                "$ANY_PROTON/proton" run "$binary" $params &
              else
                echo "Fallback Proton paths not found, skipping this method."
                return 1
              fi
            fi
            ;;
          "proton_command")
            # Method 3: System proton command
            STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam" \
            STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH}" \
            proton run "$binary" $params &
            ;;
          "wine_direct")
            # Method 4: Direct Wine launch with virtual display
            export DISPLAY=:0.0
            # Create virtual display with Xvfb if available
            if command -v Xvfb >/dev/null 2>&1; then
              # Create .X11-unix directory first to avoid errors
              mkdir -p /tmp/.X11-unix 2>/dev/null || true
              chmod 1777 /tmp/.X11-unix 2>/dev/null || true
              
              # Start Xvfb with error output suppressed
              Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
              XVFB_PID=$!
              sleep 2  # Give Xvfb time to start
            fi
            # Add environment variables to help wine find libraries
            export WINEDLLOVERRIDES="*version=n,b;vcrun2019=n,b"
            export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
            WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$binary" $params 2>&1 | tee -a /home/pok/logs/wine_launch.log &
            ;;
        esac
        
        local pid=$!
        echo "Launch attempt PID: $pid"
        
        # Wait a moment to see if the process starts
        sleep 5
        
        # Check if process is still running
        if kill -0 $pid 2>/dev/null; then
          echo "Launch successful using method: $method"
          return 0
        else
          echo "Launch failed using method: $method"
          # Check if this was a MSVCP140.dll error
          if grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" /home/pok/logs/wine_launch.log 2>/dev/null; then
            echo "DETECTED MSVCP140.dll LOADING ERROR - Flagging for automatic restart"
            # Create a flag file so monitor can detect this specific error
            echo "MSVCP140.dll loading error detected on first launch" > /home/pok/.first_launch_msvcp140_error
          fi
          return 1
        fi
      fi
    }
    
    # Try different launch methods for AsaApiLoader with better fallbacks
    SERVER_PID=""
    
    if attempt_launch "proton_direct" "$LAUNCH_BINARY_NAME" "$server_params"; then
      SERVER_PID=$!
    elif attempt_launch "proton_fallback" "$LAUNCH_BINARY_NAME" "$server_params"; then
      SERVER_PID=$!
    elif attempt_launch "proton_command" "$LAUNCH_BINARY_NAME" "$server_params"; then
      SERVER_PID=$!
    elif attempt_launch "wine_direct" "$LAUNCH_BINARY_NAME" "$server_params"; then
      SERVER_PID=$!
    else
      # As a last resort, try launching the regular server executable
      echo "All AsaApiLoader launch attempts failed. Falling back to standard server executable..."
      LAUNCH_BINARY_NAME="ArkAscendedServer.exe"
      
      # Try the same sequence of methods with the standard executable
      if attempt_launch "proton_direct" "$LAUNCH_BINARY_NAME" "$server_params"; then
        SERVER_PID=$!
      elif attempt_launch "proton_fallback" "$LAUNCH_BINARY_NAME" "$server_params"; then
        SERVER_PID=$!
      elif attempt_launch "proton_command" "$LAUNCH_BINARY_NAME" "$server_params"; then
        SERVER_PID=$!
      elif attempt_launch "wine_direct" "$LAUNCH_BINARY_NAME" "$server_params"; then
        SERVER_PID=$!
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
    # For regular server launch, try each method in sequence
    SERVER_PID=""
    
    # Try first with the found Proton executable
    if [ -f "$PROTON_EXECUTABLE" ]; then
      echo "Launching with found Proton executable: $PROTON_EXECUTABLE"
      "$PROTON_EXECUTABLE" run "$LAUNCH_BINARY_NAME" $server_params &
      SERVER_PID=$!
      
      # Wait a moment to see if the server started correctly
      sleep 5
      
      # Check if the process is running
      if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "WARNING: First launch attempt failed. Trying alternative methods..."
        SERVER_PID=""
      else
        echo "Server started successfully with primary Proton method."
      fi
    else
      echo "No primary Proton executable found, trying alternative methods..."
      SERVER_PID=""
    fi
    
    # If first method failed, try alternative methods
    if [ -z "$SERVER_PID" ] || ! kill -0 $SERVER_PID 2>/dev/null; then
      # Try different launch methods in sequence
      if [ -f "${STEAM_COMPAT_DIR}/GE-Proton8-21/proton" ]; then
        echo "Trying GE-Proton8-21..."
        "${STEAM_COMPAT_DIR}/GE-Proton8-21/proton" run "$LAUNCH_BINARY_NAME" $server_params &
        SERVER_PID=$!
        sleep 5
      elif [ -f "${STEAM_COMPAT_DIR}/GE-Proton9-25/proton" ]; then
        echo "Trying GE-Proton9-25..."
        "${STEAM_COMPAT_DIR}/GE-Proton9-25/proton" run "$LAUNCH_BINARY_NAME" $server_params &
        SERVER_PID=$!
        sleep 5
      elif command -v proton >/dev/null 2>&1; then
        echo "Trying system proton command..."
        proton run "$LAUNCH_BINARY_NAME" $server_params &
        SERVER_PID=$!
        sleep 5
      elif command -v wine >/dev/null 2>&1; then
        echo "Trying direct wine command..."
        WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$LAUNCH_BINARY_NAME" $server_params &
        SERVER_PID=$!
        sleep 5
      else
        echo "ERROR: No viable launch method found! Server could not be started."
        exit 1
      fi
      
      # Check if any of these methods worked
      if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "ERROR: All launch attempts failed! Server could not be started."
        exit 1
      else
        echo "Server started successfully with alternative method."
      fi
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
  
  # Modified display_server_logs function to avoid duplication
  display_server_logs() {
    echo "📊 MONITORING SERVER LOGS"
    echo "---------------------------------------------"
    
    # Define log paths
    local game_log="${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
    local max_wait=60  # Maximum seconds to wait for logs
    local check_interval=2
    local elapsed=0
    
    # Clear variables to prevent any accidental reuse
    unset API_TAIL_PID
    unset GAME_TAIL_PID
    
    # Run all log display operations in the background to ensure script continues
    (
    # Branch logic based on API setting
    if [ "${API}" = "TRUE" ]; then
      # Define API log paths only when API is enabled
      local api_log="${ASA_DIR}/ShooterGame/Binaries/Win64/logs/AsaApi.log"
      local api_folder="${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
      local found_api_log=""
      
      # First, check and display AsaApi logs (priority)
      echo "🔍 Looking for AsaApi logs (API is enabled)..."
      
      # Define spinner characters - spinning dots animation
      local spinner=('.' '..' '...' '.' '..' '...')
      local spinner_idx=0
      local spinner_check_count=0
      
      while [ $elapsed -lt $max_wait ]; do
        # Update spinner
        local current_spinner=${spinner[$spinner_idx]}
        spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
      
        if [ -f "$api_log" ]; then
          # Clear the spinner line before displaying completion message
          printf "\r                                                               \r"
          found_api_log="$api_log"
          echo "✅ Found AsaApi logs: $api_log"
          break
        elif [ -d "$api_folder" ] && [ "$(ls -A $api_folder 2>/dev/null | grep -i .log)" ]; then
          # If AsaApi.log doesn't exist but other logs exist in the folder
          local other_api_log=$(ls -t $api_folder/*.log 2>/dev/null | head -1)
          if [ -n "$other_api_log" ]; then
            # Clear the spinner line before displaying completion message
            printf "\r                                                               \r"
            found_api_log="$other_api_log"
            echo "✅ Found alternative API log: $(basename $other_api_log)"
            break
          fi
        fi
        
        # Display status with spinner (on a single line)
        printf "\r%s Looking for AsaApi logs... (%s seconds elapsed)      " "${current_spinner}" "$elapsed"
        
        sleep 0.2  # Medium speed for spinner animation
        
        # Increment elapsed time every 10 spinner updates (2 seconds)
        spinner_check_count=$((spinner_check_count + 1))
        if [ $spinner_check_count -ge 10 ]; then
          elapsed=$((elapsed + check_interval))
          spinner_check_count=0
        fi
      done
      
      # If API log is found, display it and wait for SERVER ID message
      if [ -n "$found_api_log" ]; then
        echo "---------------------------------------------"
        echo "📋 ASAAPI LOG OUTPUT:"
        echo "---------------------------------------------"
        
        # Use a named pipe for the API logs to enable monitoring for SERVER ID
        local api_pipe="/tmp/asaapi_logs_pipe_$$"
        mkfifo "$api_pipe"
        
        # Start tailing in the background and direct to both output and named pipe
        tail -f "$found_api_log" | tee "$api_pipe" &
        API_TAIL_PID=$!
        
        # Monitor the pipe for SERVER ID
        (
          local server_id_wait=180  # Wait up to 3 minutes for server ID
          local server_id_detected=false
          
          while IFS= read -r line; do
            if echo "$line" | grep -q "SERVER ID:"; then
              server_id_detected=true
              # Extract and save SERVER ID to a file for later use
              echo "$line" | grep -o "SERVER ID: [0-9]*" | cut -d' ' -f3 > /tmp/ark_server_id
              # Wait a bit more for subsequent logs after SERVER ID
              sleep 2
              # Kill the API log tail
              kill $API_TAIL_PID 2>/dev/null || true
              break
            fi
          done < "$api_pipe"
          
          # Clean up pipe
          rm -f "$api_pipe"
          
          # Switch to game logs after finding SERVER ID or timeout
          echo ""
          if [ "$server_id_detected" = "true" ]; then
            echo "✅ AsaApi SERVER ID detected, switching to ShooterGame logs..."
          else
            echo "⚠️ SERVER ID not detected in AsaApi logs, switching to ShooterGame logs anyway..."
          fi
          
          # Wait for ShooterGame log file to appear
          local shooter_wait=60
          local shooter_elapsed=0
          
          # Define spinner characters - spinning dots animation
          local spinner=('.' '..' '...' '.' '..' '...')
          local spinner_idx=0
          local spinner_check_count=0
          
          while [ $shooter_elapsed -lt $shooter_wait ]; do
            # Update spinner
            local current_spinner=${spinner[$spinner_idx]}
            spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
            
            if [ -f "$game_log" ]; then
              # Clear the spinner line before displaying completion message
              printf "\r                                                               \r"
              echo ""
              echo "✅ Found ShooterGame logs: $game_log"
              echo "---------------------------------------------"
              echo "📋 ARK SERVER LOG OUTPUT (FULL LOG):"
              echo "---------------------------------------------"
              
              # Display entire log once
              if [ -s "$game_log" ]; then
                cat "$game_log"
                echo "---------------------------------------------"
                echo "📋 CONTINUING LIVE LOGS:"
                echo "---------------------------------------------"
              fi
              
              # Then tail for new entries
              tail -f "$game_log" &
              GAME_TAIL_PID=$!
              # Store PID for cleanup later
              export TAIL_PID=$GAME_TAIL_PID
              break
            fi
            
            # Display status with spinner (on a single line)
            printf "\r%s Looking for ShooterGame logs... (%s seconds elapsed)      " "${current_spinner}" "$shooter_elapsed"
            
            sleep 0.2  # Medium speed for spinner animation
            
            # Increment elapsed time every 10 spinner updates (2 seconds)
            spinner_check_count=$((spinner_check_count + 1))
            if [ $spinner_check_count -ge 10 ]; then
              shooter_elapsed=$((shooter_elapsed + check_interval))
              spinner_check_count=0
            fi
          done
          
          if [ $shooter_elapsed -ge $shooter_wait ] && [ ! -f "$game_log" ]; then
            # Clear the spinner line before showing message
            printf "\r                                                               \r"
            echo "⚠️ No ShooterGame logs found after waiting. Server might still be starting up."
          fi
        ) &
        
      else
        # If no API logs found, just wait for game logs
        echo "⚠️ No AsaApi logs found after $max_wait seconds despite API being enabled"
        fallback_to_game_logs
      fi
    else
      # When API is disabled, just display game logs
      echo "ℹ️ AsaApi is disabled (API=FALSE) - Only displaying ShooterGame logs"
      fallback_to_game_logs
    fi
    ) &
    LOGS_DISPLAY_PID=$!
    # Important: Add brief pause to allow log processes to start
    sleep 2
  }
  
  # Helper function to fall back to game logs when API logs aren't available
  fallback_to_game_logs() {
    local game_log="${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
    local max_wait=60
    local check_interval=2
    local elapsed=0
    
    echo "🔍 Looking for ShooterGame logs..."
    
    # Define spinner characters - spinning dots animation
    local spinner=('.' '..' '...' '.' '..' '...')
    local spinner_idx=0
    local spinner_check_count=0
    
    while [ $elapsed -lt $max_wait ]; do
      # Update spinner
      local current_spinner=${spinner[$spinner_idx]}
      spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
      
      if [ -f "$game_log" ]; then
        # Clear the spinner line before displaying completion message
        printf "\r                                                               \r"
        echo "✅ Found ShooterGame logs: $game_log"
        echo "---------------------------------------------"
        echo "📋 ARK SERVER LOG OUTPUT (FULL LOG):"
        echo "---------------------------------------------"
        
        # Display entire log once
        if [ -s "$game_log" ]; then
          cat "$game_log"
          echo "---------------------------------------------"
          echo "📋 CONTINUING LIVE LOGS:"
          echo "---------------------------------------------"
        fi
        
        # Then tail for new entries - RUN IN BACKGROUND
        tail -f "$game_log" &
        GAME_TAIL_PID=$!
        # Store PID for cleanup later
        export TAIL_PID=$GAME_TAIL_PID
        break
      fi
      
      # Display status with spinner (on a single line)
      printf "\r%s Looking for ShooterGame logs... (%s seconds elapsed)      " "${current_spinner}" "$elapsed"
      
      sleep 0.2  # Medium speed for spinner animation
      
      # Increment elapsed time every 10 spinner updates (2 seconds)
      spinner_check_count=$((spinner_check_count + 1))
      if [ $spinner_check_count -ge 10 ]; then
        elapsed=$((elapsed + check_interval))
        spinner_check_count=0
      fi
    done
    
    if [ $elapsed -ge $max_wait ] && [ ! -f "$game_log" ]; then
      # Clear the spinner line before showing message
      printf "\r                                                               \r"
      echo "⚠️ No ShooterGame logs found after $max_wait seconds. Server might still be starting up."
      echo "  → Once available, logs will be located at: $game_log"
    fi
  }
  
  # Replace existing log tailing code with improved function
  if [ "${API}" = "TRUE" ]; then
    if [ -f "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
      # Launch with AsaApiLoader.exe
      echo "🔌 Starting server with AsaApi enabled"
      display_server_logs
    else
      # Launch with regular executable  
      echo "⚠️ AsaApiLoader.exe not found, launching without AsaApi"
      display_server_logs
    fi
  else
    # Launch with regular executable if API is disabled
    echo "ℹ️ AsaApi is disabled, launching normal server"
    display_server_logs
  fi

  # Wait for the server to fully start, monitoring the log file
  echo ""
  echo "====== VERIFYING SERVER STARTUP ======"
  echo "Waiting for server to become fully operational..."
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
  
  # Define spinner characters - spinning dots animation
  local spinner=('.' '..' '...' '.' '..' '...')
  local spinner_idx=0
  local spinner_update_count=0
  
  # Retry loop for server verification
  while [ $wait_time -lt $max_wait_time ]; do
    # Update spinner
    local current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    # Check if server process is running
    if ! ps -p $SERVER_PID > /dev/null; then
      echo "ERROR: Server process ($SERVER_PID) is no longer running!"
      echo "Server failed to start properly. Check logs for errors."
      
      # If log file exists, show the last 20 lines
      if [ -f "$LOG_FILE" ]; then
        echo "Last 20 lines of log file:"
        tail -n 20 "$LOG_FILE"
      fi
      exit 1
    fi
    
    # Display status with spinner (on a single line)
    if [ "$startup_message_displayed" = "false" ]; then
      printf "\r%s Waiting for server startup... (%s seconds elapsed)      " "${current_spinner}" "$wait_time"
    fi
    
    # Check for successful server startup in logs
    if [ -f "$LOG_FILE" ]; then
      if grep -q "Server has completed startup and is now advertising for join" "$LOG_FILE"; then
        if [ "$startup_message_displayed" = "false" ]; then
          # Clear the spinner line before displaying completion message
          printf "\r                                                               \r"
          echo "✅ Found the 'Server has completed startup and is now advertising for join' message!"
          echo "$(grep "Server has completed startup and is now advertising for join" "$LOG_FILE" | tail -1)"
          echo ""
          echo "🎮 ====== SERVER FULLY STARTED ====== 🎮"
          echo "Server started successfully. PID: $SERVER_PID"
          echo "Server is now advertising for join and ready to accept connections!"
          
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
              echo "🆔 SERVER ID: $server_id"
            fi
          fi
          
          startup_message_displayed=true
          
          # Create the first_launch_completed file to mark that the server has launched successfully
          touch "$first_launch_file"
        fi
        
        # Double verify correct PID file
        get_server_process_id
        
        # Update PID file with proper value
        echo "Ensuring PID file is up-to-date with server PID: $SERVER_PID"
        echo "$SERVER_PID" > "$PID_FILE"
        
        echo "Server monitoring is now active."
        break
      else
        if [ "$startup_message_displayed" = "false" ]; then
          # Server still starting up, status already shown by spinner
          # Only show log messages on regular intervals
          if [ $((wait_time % logs_display_interval)) -eq 0 ] && [ $wait_time -gt 0 ] && [ $wait_time -ne $logs_shown_timestamp ]; then
            # Clear the spinner line before showing logs
            printf "\r                                                               \r"
            echo -e "\nWaiting for log message: 'Server has completed startup and is now advertising for join'"
            echo "Last few lines of log file:"
            tail -n 5 "$LOG_FILE"
            echo ""
            logs_shown_timestamp=$wait_time
          fi
        fi
      fi
    else
      if [ "$startup_message_displayed" = "false" ]; then
        # Use the same spinner style and format as other messages
        printf "\r%s Waiting for server startup... (%s seconds elapsed)      " "${current_spinner}" "$wait_time"
      fi
    fi
    
    # Sleep for a shorter time to get smoother spinner animation
    sleep 0.2
    
    # Every 50 spinner updates (10 seconds) increment the wait_time counter
    spinner_update_count=$((spinner_update_count + 1))
    if [ $spinner_update_count -ge 50 ]; then
      wait_time=$((wait_time + 10))
      spinner_update_count=0
    fi
  done
  
  # If we reached the timeout but didn't find the completion message
  if [ $wait_time -ge $max_wait_time ]; then
    # Make sure we end with a newline before displaying warning
    if [ "$startup_message_displayed" = "false" ]; then
      printf "\r                                                               \r"
    fi
    
    echo "WARNING: Server verification timed out after ${max_wait_time}s, but process with PID $SERVER_PID is still running."
    echo "Considering server as started, but it may not be fully operational yet."
    echo "Updating PID file anyway to prevent unnecessary restart attempts."
    echo "$SERVER_PID" > "$PID_FILE"
  fi

  # Wait for the server process to exit
  wait $SERVER_PID
  echo "Server stopped."
  
  # Clean up all background processes
  if [ -n "$TAIL_PID" ]; then
    kill $TAIL_PID 2>/dev/null || true
    echo "Stopped tailing ShooterGame.log."
  fi
  
  if [ -n "$LOGS_DISPLAY_PID" ]; then
    kill -TERM $LOGS_DISPLAY_PID 2>/dev/null || true
    echo "Stopped logs display process."
  fi
  
  if [ -n "$API_TAIL_PID" ]; then
    kill $API_TAIL_PID 2>/dev/null || true
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
  determine_map_path
  update_game_user_settings
  start_server
}

# Start the main execution
main
