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
    echo "Setting up ArkServerAPI environment..."
    
    # Make sure the API directory exists
    if [ ! -d "${ASA_DIR}/ShooterGame/Binaries/Win64/ArkApi" ]; then
      echo "WARNING: ArkServerAPI directory not found! API may not be properly installed."
      return 1
    fi
    
    # Verify if Visual C++ Redistributable might be installed in the Proton prefix
    local vcredist_marker="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio"
    
    if [ ! -d "$vcredist_marker" ]; then
      echo "WARNING: Visual C++ Redistributable marker not found in Proton prefix."
      echo "The ArkServerAPI may not function correctly."
      echo "Trying to verify redistributable installation..."
      
      # Attempt to check registry keys in Wine for VC++ redist
      local reg_output
      reg_output=$(WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine reg query "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64" 2>/dev/null)
      
      if [ $? -eq 0 ] && [ -n "$reg_output" ]; then
        echo "Visual C++ Redistributable appears to be installed based on registry entries."
      else
        echo "No registry entries found for Visual C++ Redistributable."
        echo "Attempting to reinstall Visual C++ Redistributable..."
        
        # Create a directory for the VC++ redistributable
        local vcredist_dir="/tmp/vcredist"
        mkdir -p "$vcredist_dir"
        
        # Download the VC++ 2019 redistributable (x64)
        local vcredist_url="https://aka.ms/vs/16/release/vc_redist.x64.exe"
        local vcredist_file="$vcredist_dir/vc_redist.x64.exe"
        
        echo "Downloading VC++ redistributable..."
        if curl -L -o "$vcredist_file" "$vcredist_url"; then
          echo "Installing VC++ redistributable in Proton environment..."
          
          # Copy the redistributable to the Proton prefix directory
          local proton_drive_c="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c"
          mkdir -p "$proton_drive_c/temp"
          cp "$vcredist_file" "$proton_drive_c/temp/"
          
          # Run the installer using Proton with /force to ensure installation
          WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "$proton_drive_c/temp/vc_redist.x64.exe" /quiet /norestart /force
          
          echo "VC++ redistributable installation attempted."
          
          # Clean up
          rm -f "$vcredist_file"
          rm -f "$proton_drive_c/temp/vc_redist.x64.exe"
        else
          echo "WARNING: Failed to download Visual C++ redistributable."
        fi
      fi
    else
      echo "Visual C++ Redistributable appears to be installed in Proton prefix."
    fi
    
    # Set DLL overrides to ensure API loads properly
    export WINEDLLOVERRIDES="version=n,b"
    echo "Set DLL overrides for ArkServerAPI"
    
    # Create a simple test to verify ArkAPI functionality
    echo "Verifying ArkServerAPI can load..."
    local test_script="${ASA_DIR}/ShooterGame/Binaries/Win64/test_arkapi.bat"
    echo '@echo off' > "$test_script"
    echo 'echo Testing ArkServerAPI loading...' >> "$test_script"
    echo 'if exist ArkApi\version.dll (echo ArkAPI DLL found) else (echo ArkAPI DLL NOT found)' >> "$test_script"
    
    WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine cmd /c "$test_script"
    rm -f "$test_script"
    
    echo "ArkServerAPI environment setup completed."
  fi
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
  
  # Check if the current user has the necessary permissions
  #if [ ! -r "/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ] || [ ! -x "/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ]; then
    #echo "Error: Insufficient permissions to run the server. Please check the file permissions."
    #exit 1
  #fi
  
  # Setup ArkServerAPI if enabled
  if [ "${API}" = "TRUE" ]; then
    setup_arkserverapi
  fi
  
  # Construct the full server start command
  local server_command="proton run /home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe $MAP_PATH?listen?$session_name_arg?${rcon_args}${server_password_arg}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD} -Port=${ASA_PORT} -WinLiveMaxPlayers=${MAX_PLAYERS} $cluster_id_arg -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs $notify_admin_commands_arg $custom_args $mods_arg $battleye_arg $passive_mods_arg"

  # Start the server using Proton-GE
  echo "Starting server with Proton-GE..."
  
  # Make sure Proton environment is fully initialized before starting the server
  if [ ! -f "${STEAM_COMPAT_DATA_PATH}/tracked_files" ] || [ ! -d "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c" ]; then
    echo "WARNING: Proton environment not fully initialized. Reinitializing..."
    initialize_proton_prefix
  fi
  
  bash -c "$server_command" &

  SERVER_PID=$!
  echo "Server process started with PID: $SERVER_PID"

  # Immediate write to PID file
  echo $SERVER_PID > $PID_FILE
  echo "PID $SERVER_PID written to $PID_FILE"

  # Check for the existence of the ShooterGame.log file with a timeout
  local timeout=30
  local elapsed=0
  while [ ! -f "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log" ]; do
    if [ $elapsed -ge $timeout ]; then
      echo "Error: ShooterGame.log not created within the specified timeout. Server may have failed to start."
      echo "Please check the server logs for more information."
      kill $SERVER_PID
      exit 1
    fi
    echo "Waiting for ShooterGame.log to be created..."
    sleep 2
    elapsed=$((elapsed + 2))
  done

  # Now that the file exists, start tailing it to the console
  echo "ShooterGame.log exists, starting to tail."
  tail -f "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log" &
  TAIL_PID=$!
  echo "Tailing ShooterGame.log with PID: $TAIL_PID"

  # Wait for the server to fully start, monitoring the log file
  echo "Waiting for server to start..."
  while true; do
    if [ -f "$LOG_FILE" ] && grep -q "Server started" "$LOG_FILE"; then
      echo "Server started successfully. PID: $SERVER_PID"
      break
    fi
    sleep 10
  done

  # Wait for the server process to exit
  wait $SERVER_PID
  echo "Server stopped."
  # Kill the tail process when the server stops
  kill $TAIL_PID
  echo "Stopped tailing ShooterGame.log."
}


# Main function
main() {
  determine_map_path
  update_game_user_settings
  start_server
}

# Start the main execution
main
