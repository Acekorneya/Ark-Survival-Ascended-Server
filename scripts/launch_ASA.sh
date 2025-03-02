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
      unzip -o "$ASA_PLUGIN_LOADER_ARCHIVE_NAME"
      rm -f "$ASA_PLUGIN_LOADER_ARCHIVE_NAME"
    fi
    
    # Make sure the AsaApiLoader exists
    if [ ! -f "$ASA_PLUGIN_BINARY_PATH" ]; then
      echo "WARNING: AsaApiLoader.exe not found! API may not be properly installed."
      echo "Attempting one more installation via common.sh install_ark_server_api function..."
      install_ark_server_api
      
      # Re-check if the file exists after installation attempt
      if [ ! -f "$ASA_PLUGIN_BINARY_PATH" ]; then
        echo "ERROR: AsaApiLoader.exe still not found after installation attempt."
        return 1
      else
        echo "AsaApiLoader.exe found after installation."
      fi
    else
      echo "AsaApiLoader.exe found at $ASA_PLUGIN_BINARY_PATH"
    fi
    
    # Verify if Visual C++ Redistributable might be installed in the Proton prefix
    local vcredist_marker="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio"
    
    if [ ! -d "$vcredist_marker" ]; then
      echo "Visual C++ Redistributable marker not found. Installing VC++ redistributable via winetricks..."
      # Use winetricks to install Visual C++ 2019 Redistributable
      WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" winetricks -q vcrun2019
    else
      echo "Visual C++ Redistributable appears to be installed in Proton prefix."
    fi
    
    # Set DLL overrides to ensure API loads properly
    export WINEDLLOVERRIDES="version=n,b"
    echo "Set DLL overrides for AsaApi"
    
    # Create logs directory for AsaApi if it doesn't exist
    mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    
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
    
    # Define a function to make a launch attempt
    attempt_launch() {
      local method="$1"
      local binary="$2"
      local params="$3"
      
      echo "Attempting launch using method: $method"
      
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
          WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$binary" $params &
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
        return 1
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
      while [ $elapsed -lt $max_wait ]; do
        if [ -f "$api_log" ]; then
          found_api_log="$api_log"
          echo "✅ Found AsaApi logs: $api_log"
          break
        elif [ -d "$api_folder" ] && [ "$(ls -A $api_folder 2>/dev/null | grep -i .log)" ]; then
          # If AsaApi.log doesn't exist but other logs exist in the folder
          local other_api_log=$(ls -t $api_folder/*.log 2>/dev/null | head -1)
          if [ -n "$other_api_log" ]; then
            found_api_log="$other_api_log"
            echo "✅ Found alternative API log: $(basename $other_api_log)"
            break
          fi
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        if [ $((elapsed % 10)) -eq 0 ]; then
          echo "⏳ Still waiting for AsaApi logs... ($elapsed seconds elapsed)"
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
          
          while [ $shooter_elapsed -lt $shooter_wait ]; do
            if [ -f "$game_log" ]; then
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
            
            sleep $check_interval
            shooter_elapsed=$((shooter_elapsed + check_interval))
          done
          
          if [ $shooter_elapsed -ge $shooter_wait ] && [ ! -f "$game_log" ]; then
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
    
    while [ $elapsed -lt $max_wait ]; do
      if [ -f "$game_log" ]; then
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
      
      sleep $check_interval
      elapsed=$((elapsed + check_interval))
      if [ $((elapsed % 10)) -eq 0 ]; then
        echo "⏳ Still waiting for ShooterGame logs... ($elapsed seconds elapsed)"
      fi
    done
    
    if [ $elapsed -ge $max_wait ] && [ ! -f "$game_log" ]; then
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
  local max_wait_time=300  # 5 minutes maximum wait time
  local wait_time=0
  
  # Initial delay to give the server time to start creating logs
  sleep 10
  
  # Retry loop for server verification
  while [ $wait_time -lt $max_wait_time ]; do
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
    
    # Check for successful server startup in logs
    if [ -f "$LOG_FILE" ]; then
      if grep -q "Server started" "$LOG_FILE" || grep -q "Server has completed startup and is now advertising for join" "$LOG_FILE"; then
        echo ""
        echo "🎮 ====== SERVER FULLY STARTED ====== 🎮"
        echo "Server started successfully. PID: $SERVER_PID"
        echo "Server is now advertising for join and ready to accept connections!"
        
        # Double verify correct PID file
        get_server_process_id
        
        # Update PID file with proper value
        echo "Ensuring PID file is up-to-date with server PID: $SERVER_PID"
        echo "$SERVER_PID" > "$PID_FILE"
        
        echo "Server monitoring is now active."
        break
      else
        echo "Server still starting up... (waited ${wait_time}s)"
      fi
    else
      echo "Waiting for server log file to be created... (waited ${wait_time}s)"
    fi
    
    sleep 10
    wait_time=$((wait_time + 10))
  done
  
  if [ $wait_time -ge $max_wait_time ]; then
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
}


# Main function
main() {
  determine_map_path
  update_game_user_settings
  start_server
}

# Start the main execution
main
