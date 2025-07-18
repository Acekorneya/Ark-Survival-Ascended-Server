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

# Get build IDs with proper error handling
saved_build_id=""
current_build_id=""

if saved_build_id=$(get_build_id_from_acf); then
  echo "Current saved build ID: $saved_build_id"
else
  echo "Could not read saved build ID (file may not exist): $saved_build_id"
  saved_build_id=""  # Treat as missing, will trigger update
fi

if current_build_id=$(get_current_build_id); then
  echo "Current available build ID: $current_build_id"
else
  echo "Could not read current build ID from SteamCMD: $current_build_id"
  # This is a more serious error, but we'll continue and let the update attempt handle it
fi

# Check if installation is needed
if [[ -z "$saved_build_id" || "$saved_build_id" =~ ^error || -z "$current_build_id" || "$current_build_id" =~ ^error || "$saved_build_id" != "$current_build_id" ]]; then
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
    
    # After the lock is released, check if installation is still needed with retry logic
    echo "Lock released. Re-checking if installation is still needed..."
    
    # Allow time for ACF file to be fully written by the updating instance
    sleep 3
    
    # Retry logic for build ID verification after lock release
    local retry_count=0
    local max_retries=5
    local update_still_needed=true
    
    while [ $retry_count -lt $max_retries ]; do
      # Get build IDs with proper error handling
      saved_build_id=""
      current_build_id=""
      
      if saved_build_id=$(get_build_id_from_acf); then
        echo "Successfully read saved build ID: $saved_build_id"
      else
        echo "Failed to read saved build ID: $saved_build_id"
      fi
      
      if current_build_id=$(get_current_build_id); then
        echo "Successfully read current build ID: $current_build_id"
      else
        echo "Failed to read current build ID: $current_build_id"
      fi
      
      echo "Retry $((retry_count + 1))/$max_retries: Saved ID: $saved_build_id, Current ID: $current_build_id"
      
      # Check if both build IDs are valid (not error messages) and equal
      if [[ -n "$saved_build_id" && ! "$saved_build_id" =~ ^error ]] && [[ -n "$current_build_id" && ! "$current_build_id" =~ ^error ]]; then
        if [[ "$saved_build_id" =~ ^[0-9]+$ ]] && [[ "$current_build_id" =~ ^[0-9]+$ ]]; then
          if [[ "$saved_build_id" == "$current_build_id" ]]; then
            echo "Server is now up to date after waiting. No installation needed."
            update_still_needed=false
            break
          else
            echo "Build IDs are different: saved=$saved_build_id, current=$current_build_id"
          fi
        else
          echo "Build IDs are not in correct numeric format"
        fi
      else
        echo "One or both build IDs could not be retrieved"
      fi
      
      retry_count=$((retry_count + 1))
      if [ $retry_count -lt $max_retries ]; then
        echo "Build IDs don't match or invalid. Retrying in 3 seconds..."
        sleep 3
      fi
    done
    
    if [ "$update_still_needed" = "true" ]; then
      echo "Still need to install/update after waiting and retries. Retrying acquisition..."
      if ! acquire_update_lock; then
        echo "Failed to acquire lock after waiting. Aborting installation."
        exit 1
      fi
    else
      exit 0
    fi
  fi
  
  echo "Current build ID is $current_build_id, initiating installation.."
  /opt/steamcmd/steamcmd.sh +force_install_dir "$ASA_DIR" +login anonymous +app_update "$APPID" +quit

  # Check for success and copy the appmanifest file
  if [[ -f "$ASA_DIR/steamapps/appmanifest_$APPID.acf" ]]; then
    cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
    
    # Force filesystem sync to ensure ACF file is visible to other containers immediately
    sync
    
    # Add small delay to ensure file visibility across container filesystems
    sleep 2
    
    # Verify the ACF file is readable and contains valid build ID
    if ! get_build_id_from_acf >/dev/null 2>&1; then
      echo "Warning: ACF file copied but build ID not immediately readable. Waiting..."
      sleep 3
    fi
    
    echo "Server installation or update completed."
    
    # Mark other instances as dirty since server files were updated
    echo "-----Marking other instances as dirty after server files installation-----"
    mark_other_instances_dirty
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
