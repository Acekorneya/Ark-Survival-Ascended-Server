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
  
  echo "Current build ID is $current_build_id, initiating installation.."
  /opt/steamcmd/steamcmd.sh +force_install_dir "$ASA_DIR" +login anonymous +app_update "$APPID" +quit

  # Check for success and copy the appmanifest file
  if [[ -f "$ASA_DIR/steamapps/appmanifest_$APPID.acf" ]]; then
    cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
    echo "Server installation or update completed."
  else
    echo "Error: appmanifest_$APPID.acf was not found after installation."
    exit 1
  fi
  # Note: We no longer need to explicitly remove the flag here because the trap will handle it
  # rm "$ASA_DIR/updating.flag"  - Commented out as trap will handle this
  echo "-----Installation complete-----"
else
  echo "No installation required, The installed server files build id:$saved_build_id and unofficials server build id: $current_build_id are the same."
fi
