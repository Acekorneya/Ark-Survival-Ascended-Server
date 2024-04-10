#!/bin/bash
source /home/pok/scripts/common.sh
# Get the current build ID at the start to ensure it's defined for later use
current_build_id=$(get_current_build_id)
# Function to check if the server needs to be updated
server_needs_update() {
  local saved_build_id=$(get_build_id_from_acf)

  if [[ -z "$saved_build_id" || "$saved_build_id" != "$current_build_id" ]]; then
    return 0 # True, needs update
  else
    return 1 # False, no update needed
  fi
}

# Update logic
echo "---checking for server update---"

if server_needs_update; then
  echo "A server update is available. Updating server to build ID $current_build_id..."
  touch /home/pok/updating.flag
  /opt/steamcmd/steamcmd.sh +force_install_dir "$ASA_DIR" +login anonymous +app_update "$APPID" +quit

  # Copy the new appmanifest for future checks
  if [[ -f "$ASA_DIR/steamapps/appmanifest_$APPID.acf" ]]; then
    cp "$ASA_DIR/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
    echo "Server update completed successfully."
  else
    echo "Error: appmanifest_$APPID.acf was not found after update."
    exit 1
  fi
  rm /home/pok/updating.flag
else
  echo "Server is already running the latest build ID: $current_build_id; no update needed."
fi
echo "---server update complete---"