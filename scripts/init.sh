#!/bin/bash

# Define paths
ASA_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame"
ARK_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server"
CLUSTER_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ShooterGame"

# Get PUID and PGID from environment variables, or default to 1001
PUID=${PUID:-1001}
PGID=${PGID:-1001}

# Function to check if vm.max_map_count is set to a sufficient value
check_vm_max_map_count() {
    local required_map_count=262144
    local current_map_count=$(cat /proc/sys/vm/max_map_count)

    if [ "$current_map_count" -lt "$required_map_count" ]; then
        echo "ERROR: The vm.max_map_count on the host system is too low ($current_map_count) and needs to be at least $required_map_count."
        echo "To fix this issue temporarily (until the next reboot), run the following command on your Docker host:"
        echo "sudo sysctl -w vm.max_map_count=262144"
        echo "For a permanent fix, add the following line to /etc/sysctl.conf on your Docker host and then run 'sysctl -p':"
        echo "vm.max_map_count=262144"
        echo "After making this change, please restart the Docker container."
        exit 1
    fi
}

# Check vm.max_map_count before proceeding
check_vm_max_map_count

# Create directories if they do not exist and set permissions
for DIR in "$ASA_DIR" "$ARK_DIR" "$CLUSTER_DIR"; do
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
    fi
    chown -R $PUID:$PGID "$DIR"
    chmod -R 755 "$DIR"
done

# Adjust permissions for build_id.txt if it exists
BUILD_ID_FILE="$ASA_DIR/build_id.txt"
if [ -f "$BUILD_ID_FILE" ]; then
    chown $PUID:$PGID "$BUILD_ID_FILE"
fi

# Continue with the main application
exec /usr/games/scripts/launch_ASA.sh
