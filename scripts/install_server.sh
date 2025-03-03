#!/bin/bash
source /home/pok/scripts/common.sh

# Create a cleanup function to remove the updating.flag
cleanup() {
  local exit_code=$?
  
  # Check if updating.flag exists and remove it
  if [ -f "$ASA_DIR/updating.flag" ]; then
    echo "Cleaning up updating.flag due to script exit (code: $exit_code)"
    rm -f "$ASA_DIR/updating.flag"
  fi
  
  # Return the original exit code
  exit $exit_code
}

# Set up trap to call cleanup on exit (including normal exit, crashes, and signals)
trap cleanup EXIT INT TERM

# Improved update lock acquisition with retry logic
acquire_update_lock() {
  local lock_file="$ASA_DIR/updating.flag"
  local max_attempts=10
  local attempt=1
  local retry_delay=5
  
  echo "Attempting to acquire installation lock..."
  
  # Make sure the directory exists
  mkdir -p "$ASA_DIR" 2>/dev/null || {
    echo "ERROR: Failed to create directory $ASA_DIR. Check permissions."
    return 1
  }
  
  while [ $attempt -le $max_attempts ]; do
    # Try to create the lock file atomically
    if ! touch "$lock_file" 2>/dev/null; then
      echo "Installation lock is held by another process (attempt $attempt/$max_attempts)..."
      sleep $retry_delay
      attempt=$((attempt + 1))
      continue
    fi
    
    # Write the current timestamp and process info to the lock file for tracking
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Lock acquired by instance: ${INSTANCE_NAME:-unknown} (PID: $$)" > "$lock_file"
    echo "Installation lock acquired successfully"
    return 0
  done
  
  echo "Failed to acquire installation lock after $max_attempts attempts. Aborting installation."
  return 1
}

# Installation logic
echo "Starting server installation process..."

# Make sure the steamcmd directory exists and is executable
if [ ! -d "/opt/steamcmd" ] || [ ! -x "/opt/steamcmd/steamcmd.sh" ]; then
  echo "ERROR: SteamCMD not found or not executable at /opt/steamcmd/steamcmd.sh"
  echo "Current directory structure:"
  ls -la /opt/ 2>/dev/null || echo "Failed to list /opt directory"
  echo "Attempting to fix steamcmd permissions..."
  chmod +x /opt/steamcmd/steamcmd.sh 2>/dev/null || echo "Failed to set execute permissions"
  if [ ! -x "/opt/steamcmd/steamcmd.sh" ]; then
    echo "CRITICAL ERROR: Cannot execute steamcmd.sh. Container may need to be rebuilt."
    exit 1
  fi
fi

saved_build_id=$(get_build_id_from_acf)
current_build_id=$(get_current_build_id)

if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
  echo "-----Installing ARK server-----"
  
  # Attempt to acquire the installation lock
  if ! acquire_update_lock; then
    echo "Another instance is currently installing or updating the server. Waiting for it to complete..."
    
    # Wait for the other installation to complete
    lock_file="$ASA_DIR/updating.flag"
    while [ -f "$lock_file" ]; do
      echo "Installation in progress by another instance. Waiting..."
      sleep 15
    done
    
    # After the lock is released, check if installation is still needed
    saved_build_id=$(get_build_id_from_acf)
    current_build_id=$(get_current_build_id)
    
    if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
      echo "Still need to install/update after waiting. Retrying acquisition..."
      if ! acquire_update_lock; then
        echo "Failed to acquire lock after waiting. Aborting installation."
        exit 1
      fi
    else
      echo "Server is now up to date after waiting. No installation needed."
      exit 0
    fi
  fi
  
  # Ensure directories exist
  mkdir -p "$ASA_DIR" 2>/dev/null || {
    echo "ERROR: Cannot create directory $ASA_DIR. Check permissions."
    exit 1
  }
  
  # Make sure we have write permissions to the server directory
  if [ ! -w "$ASA_DIR" ]; then
    echo "ERROR: No write permission to $ASA_DIR. Checking ownership and permissions..."
    ls -la $ASA_DIR
    echo "Current user: $(whoami)"
    echo "Current user ID: $(id -u)"
    echo "Expected owner ID: $PUID"
    echo "Attempting to fix permissions..."
    chmod -R 755 "$ASA_DIR" 2>/dev/null || echo "Failed to fix permissions. Container may need to be rebuilt."
    exit 1
  fi
  
  echo "Current build ID is $current_build_id, initiating installation.."
  
  # Run steamcmd with more verbose output
  echo "Running: /opt/steamcmd/steamcmd.sh +force_install_dir \"$ASA_DIR\" +login anonymous +app_update \"$APPID\" +quit"
  /opt/steamcmd/steamcmd.sh +force_install_dir "$ASA_DIR" +login anonymous +app_update "$APPID" +quit
  
  install_result=$?
  if [ $install_result -ne 0 ]; then
    echo "ERROR: SteamCMD returned error code $install_result"
    echo "Check steamcmd logs for details."
    exit 1
  fi

  # Check for success and copy the appmanifest file
  if [[ -f "$ASA_DIR/steamapps/appmanifest_$APPID.acf" ]]; then
    # Make sure the directory exists
    mkdir -p "$(dirname "$PERSISTENT_ACF_FILE")" 2>/dev/null || {
      echo "WARNING: Failed to create directory for persistent ACF file"
    }
    
    cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE" || {
      echo "WARNING: Failed to copy appmanifest file to persistent location"
    }
    
    echo "Server installation or update completed."
  else
    echo "Error: appmanifest_$APPID.acf was not found after installation."
    echo "Installation may have failed or SteamCMD may have encountered an error."
    echo "Checking for server executable..."
    
    # Check if the server executable exists despite missing manifest
    if [[ -f "$ASA_DIR/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ]]; then
      echo "Server executable found despite missing manifest. Installation may have succeeded partially."
      # Create a dummy manifest file to prevent reinstallation attempts
      mkdir -p "$ASA_DIR/steamapps" 2>/dev/null
      echo "{\"appid\":\"$APPID\",\"buildid\":\"$current_build_id\"}" > "$ASA_DIR/steamapps/appmanifest_$APPID.acf"
      cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE" 2>/dev/null || true
    else
      echo "Server executable not found. Installation failed."
      exit 1
    fi
  fi
  # Note: We no longer need to explicitly remove the flag here because the trap will handle this
  # rm "$ASA_DIR/updating.flag"  - Commented out as trap will handle this
  echo "-----Installation complete-----"
else
  echo "No installation required, The installed server files build id:$saved_build_id and unofficials server build id: $current_build_id are the same."
fi
