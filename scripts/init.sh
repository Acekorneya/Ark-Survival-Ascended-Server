#!/bin/bash

# Define paths
ASA_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame"
ARK_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server"
CLUSTER_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ShooterGame"

# Get PUID and PGID from environment variables, or default to 1001
PUID=${PUID:-1001}
PGID=${PGID:-1001}

# Create directories if they do not exist and set permissions
for DIR in "$ASA_DIR" "$ARK_DIR" "$CLUSTER_DIR"; do
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
    fi
    chown -R $PUID:$PGID "$DIR"
    chmod -R 755 "$DIR"
done

# Continue with the main application
exec /usr/games/scripts/launch_ASA.sh