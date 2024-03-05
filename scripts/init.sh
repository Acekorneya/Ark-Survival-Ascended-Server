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
  echo "----Checking for new Ark Server version----"
  /home/pok/scripts/update_server.sh
fi

# Start the main application
echo "----Starting Ark Server----"
exec /home/pok/scripts/launch_ASA.sh
# Keep the script running to catch the signal
