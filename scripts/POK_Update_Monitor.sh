#!/bin/bash

# Define necessary variables
ASA_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame"
APPID=2430930  


# Function to get the build ID from the appmanifest.acf file
get_build_id_from_acf() {
    local acf_file="$ASA_DIR/appmanifest_$APPID.acf"
    if [[ -f "$acf_file" ]]; then
        local build_id=$(grep -E "^\s+\"buildid\"\s+" "$acf_file" | grep -o '[[:digit:]]*')
        echo "$build_id"
    else
        echo ""
    fi
}

# Function to get the current build ID from SteamCMD API
get_current_build_id() {
    local build_id=$(curl -sX GET "https://api.steamcmd.net/v1/info/$APPID" | jq -r ".data.\"$APPID\".depots.branches.public.buildid")
    echo "$build_id"
}

# Check for updates
saved_build_id=$(get_build_id_from_acf)
current_build_id=$(get_current_build_id)

if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "Update available."
    fi
    exit 0
else
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "No updates."
    fi
    exit 1
fi