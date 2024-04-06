#!/bin/bash
source /home/pok/scripts/common.sh

# Installation logic
echo "Starting server installation process..."

saved_build_id=$(get_build_id_from_acf)
current_build_id=$(get_current_build_id)

if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
  echo "-----Installing ARK server-----"
  touch /home/pok/updating.flag
  echo "Current build ID is $current_build_id, initiating installation.."
  /opt/steamcmd/steamcmd.sh +force_install_dir "$ASA_DIR" +login anonymous +app_update "$APPID" validate +quit

  # Check for success and copy the appmanifest file
  if [[ -f "$ASA_DIR/steamapps/appmanifest_$APPID.acf" ]]; then
    cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
    echo "Server installation or update completed."
  else
    echo "Error: appmanifest_$APPID.acf was not found after installation."
    exit 1
  fi
  rm /home/pok/updating.flag
  echo "-----Installation complete-----"
else
  echo "No installation required, The installed server files build id:$saved_build_id and unofficials server build id: $current_build_id are the same."
fi
