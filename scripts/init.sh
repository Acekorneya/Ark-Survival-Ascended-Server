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

# Ensure Proton environment is properly set up before proceeding
echo "----Setting up Proton environment----"
mkdir -p "${STEAM_COMPAT_DATA_PATH}"
if [ ! -d "${STEAM_COMPAT_DATA_PATH}" ]; then
  echo "Error creating ${STEAM_COMPAT_DATA_PATH}" >&2
  exit 1
fi

# Initialize Proton prefix to prevent race conditions
initialize_proton_prefix

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

# Function to verify Proton environment is properly set up
verify_proton_environment() {
  echo "----Verifying Proton environment for ArkServerAPI----"
  
  # Check if Proton prefix exists
  if [ ! -d "${STEAM_COMPAT_DATA_PATH}/pfx" ]; then
    echo "WARNING: Proton prefix directory not found. Creating it..."
    mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx"
  fi
  
  # Check if Wine is functional in the Proton environment
  echo "Testing Wine/Proton functionality..."
  if ! WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine --version >/dev/null 2>&1; then
    echo "WARNING: Wine does not appear to be functioning correctly in the Proton environment."
    echo "This may affect ArkServerAPI functionality."
  else
    echo "Wine/Proton environment is functional."
  fi
}

# Install/Update ArkServerAPI if API=TRUE
if [ "${API}" = "TRUE" ]; then
  echo "----Installing/Updating ArkServerAPI (Framework-ArkServerApi)----"
  # Verify Proton environment first
  verify_proton_environment
  # Install the API
  install_ark_server_api
  
  # Verify the installation
  if [ -d "${ASA_DIR}/ShooterGame/Binaries/Win64/ArkApi" ]; then
    echo "ArkServerAPI installation confirmed."
    # Check if the API directory has the expected files
    if [ -f "${ASA_DIR}/ShooterGame/Binaries/Win64/ArkApi/version.dll" ]; then
      echo "API core files verified."
    else
      echo "WARNING: API core files missing. Installation may not be complete."
    fi
  else
    echo "WARNING: ArkServerAPI directory not found after installation attempt."
  fi
fi

# Start the main application
echo "----Starting Ark Server----"
exec /home/pok/scripts/launch_ASA.sh
# Keep the script running to catch the signal