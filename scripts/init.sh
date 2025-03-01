#!/bin/bash

source /home/pok/scripts/common.sh

# Add a random delay between 0-30 seconds to prevent all containers from
# checking for updates simultaneously when multiple servers start at once
# Default to TRUE if the variable isn't set in the environment
if [ "${RANDOM_STARTUP_DELAY:-TRUE}" = "TRUE" ]; then
  # Get a random delay from 0 to 10 seconds
  DELAY=$((RANDOM % 10))
  echo "----Random startup delay: waiting for $DELAY seconds to prevent update conflicts----"
  sleep $DELAY
fi

mkdir -p "${STEAM_COMPAT_DATA_PATH}"
if [ ! -d "${STEAM_COMPAT_DATA_PATH}" ]; then
  echo "Error creating ${STEAM_COMPAT_DATA_PATH}" >&2
  exit 1
fi

# Check for stale update flags which could prevent proper startup
# If this was a previous interrupted update, clear the flag
echo "----Checking for stale update flags----"
check_stale_update_flag 1 # Consider flags older than 1 hours as stale

echo "----Starting POK Ark Server Monitoring----"
/home/pok/scripts/monitor_ark_server.sh &

# Check if the server is installed
if [ ! -f "$PERSISTENT_ACF_FILE" ]; then
  echo "----Installing Ark Server----"
  /home/pok/scripts/install_server.sh
else
  lock_file="$ASA_DIR/updating.flag"
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

# Install/Update ArkServerAPI if API=TRUE
if [ "${API}" = "TRUE" ]; then
  echo "----Installing/Updating ArkServerAPI (Framework-ArkServerApi)----"
  install_ark_server_api
fi

# Start the main application
echo "----Starting Ark Server----"
exec /home/pok/scripts/launch_ASA.sh
# Keep the script running to catch the signal