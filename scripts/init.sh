#!/bin/bash

source /home/pok/scripts/common.sh

mkdir -p "${STEAM_COMPAT_DATA_PATH}"
if [ ! -d "${STEAM_COMPAT_DATA_PATH}" ]; then
  echo "Error creating ${STEAM_COMPAT_DATA_PATH}" >&2
  exit 1
fi

echo "----Starting POK Ark Server Monitoring----"
/home/pok/scripts/monitor_ark_server.sh &

# Check if the server is installed
if [ ! -f "$PERSISTENT_ACF_FILE" ]; then
  echo "----Installing Ark Server----"
  /home/pok/scripts/install_server.sh
else
  lock_file="/home/pok/updating.flag"
  current_build_id=$(get_current_build_id)
  saved_build_id=$(get_build_id_from_acf)

  if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
    # Check if an update is in progress by another instance
    while [ -f "$lock_file" ]; do
        echo "Update in progress by another instance. Waiting for it to complete..."
        sleep 15
    done

    # Run the update_server.sh script
    echo "----Checking for new Ark Server version----"
    /home/pok/scripts/update_server.sh
  else
    echo "----Server is already up to date with build ID: $current_build_id----"
  fi
fi

# Start the main application
echo "----Starting Ark Server----"
exec /home/pok/scripts/launch_ASA.sh
# Keep the script running to catch the signal