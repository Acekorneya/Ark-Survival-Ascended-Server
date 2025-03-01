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
trap cleanup EXIT

# Installation logic
echo "Starting server installation process..."

saved_build_id=$(get_build_id_from_acf)
current_build_id=$(get_current_build_id)

if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
  echo "-----Installing ARK server-----"
  touch "$ASA_DIR/updating.flag"
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
