#!/bin/bash
source /home/pok/scripts/common.sh
# Get the current build ID at the start to ensure it's defined for later use
current_build_id=$(get_current_build_id)

# Create a cleanup function to remove the updating.flag
cleanup() {
  local exit_code=$?
  
  # Check if updating.flag exists and remove it
  if [ -f "$ASA_DIR/updating.flag" ]; then
    echo "[INFO] Cleaning up updating.flag due to script exit (code: $exit_code)"
    rm -f "$ASA_DIR/updating.flag"
  fi
  
  # Clean up SteamCMD temporary files to save disk space
  echo "[INFO] Cleaning up SteamCMD temporary files..."
  rm -rf /opt/steamcmd/Steam/logs/* 2>/dev/null || true
  rm -rf /opt/steamcmd/Steam/appcache/httpcache/* 2>/dev/null || true
  rm -rf /tmp/SteamCMD_* 2>/dev/null || true
  
  # Return the original exit code
  exit $exit_code
}

# Set up trap to call cleanup on exit (including normal exit, crashes, and signals)
trap cleanup EXIT INT TERM

# Function to check if the server needs to be updated
server_needs_update() {
  local saved_build_id=$(get_build_id_from_acf)

  if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
    return 0 # True, needs update
  else
    return 1 # False, no update needed
  fi
}

# Improved update lock acquisition with retry logic
acquire_update_lock() {
  local lock_file="$ASA_DIR/updating.flag"
  local max_attempts=10
  local attempt=1
  local retry_delay=5
  
  echo "[INFO] Attempting to acquire update lock..."
  
  while [ $attempt -le $max_attempts ]; do
    # Try to create the lock file atomically
    if ! touch "$lock_file" 2>/dev/null; then
      echo "[WARNING] Update lock is held by another process (attempt $attempt/$max_attempts)..."
      sleep $retry_delay
      attempt=$((attempt + 1))
      continue
    fi
    
    # Write the current timestamp and process info to the lock file for tracking
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Lock acquired by instance: ${INSTANCE_NAME:-unknown} (PID: $$)" > "$lock_file"
    echo "[SUCCESS] Update lock acquired successfully"
    return 0
  done
  
  echo "[ERROR] Failed to acquire update lock after $max_attempts attempts. Aborting update."
  return 1
}

# Update logic
echo "[INFO] Checking for ARK server updates..."

if server_needs_update; then
  echo "[INFO] Server update available: Current build ID: $current_build_id, Installed build ID: $(get_build_id_from_acf)"
  
  # Attempt to acquire the update lock
  if ! acquire_update_lock; then
    echo "[WARNING] Another instance is currently updating the server. Aborting update."
    exit 0
  fi
  
  # We now have the update lock, proceed with update
  echo "[INFO] Starting SteamCMD update process for ARK (AppID: $APPID)..."
  /opt/steamcmd/steamcmd.sh +force_install_dir "$ASA_DIR" +login anonymous +app_update "$APPID" +quit
  update_result=$?

  # Copy the new appmanifest for future checks
  if [[ $update_result -eq 0 && -f "$ASA_DIR/steamapps/appmanifest_$APPID.acf" ]]; then
    cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
    echo "[SUCCESS] Server updated successfully to build ID: $current_build_id"
  else
    echo "[ERROR] Server update failed with exit code: $update_result"
    exit 1
  fi
  # Note: We no longer need to explicitly remove the flag here because the trap will handle this
  # rm "$ASA_DIR/updating.flag"  - Commented out as trap will handle this
else
  echo "[INFO] Server is already running the latest build ID: $current_build_id; no update needed."
fi
echo "[INFO] Update check completed."