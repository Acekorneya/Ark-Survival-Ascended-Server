#!/bin/bash
source /home/pok/scripts/common.sh

# Check for updates
saved_build_id=$(get_build_id_from_acf)
current_build_id=$(get_current_build_id)

if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "[INFO] Update available: Current build ID: $current_build_id, Installed build ID: $saved_build_id"
    fi
    exit 0
else
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "[INFO] No updates available. Server is running latest build ID: $current_build_id"
    fi
    exit 1
fi