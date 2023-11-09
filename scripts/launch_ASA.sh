#!/bin/bash

# Initialize environment variables
initialize_variables() {
    export DISPLAY=:0.0
    USERNAME=anonymous
    APPID=2430930
    ASA_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame"
    CLUSTER_DIR="$ASA_DIR/Cluster"
    CLUSTER_DIR_OVERRIDE="$CLUSTER_DIR"
    SOURCE_DIR="/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/"
    DEST_DIR="$ASA_DIR/Binaries/Win64/"
    PERSISTENT_ACF_FILE="$ASA_DIR/appmanifest_$APPID.acf"
}

# Start xvfb on display :0
start_xvfb() {
    Xvfb :0 -screen 0 1024x768x16 &
}

# Check if the Cluster directory exists
cluster_dir() {
    if [ -d "$CLUSTER_DIR" ]; then
        echo "Cluster directory already exists. Skipping folder creation."
    else
        echo "Creating Cluster Folder..."
        mkdir -p "$CLUSTER_DIR"
    fi
}

# Determine the map path based on environment variable
determine_map_path() {
    if [ "$MAP_NAME" = "TheIsland" ]; then
        MAP_PATH="TheIsland_WP"
    elif [ "$MAP_NAME" = "ScorchedEarth" ]; then
        MAP_PATH="ScorchedEarth_WP"
    else
        echo "Invalid MAP_NAME. Defaulting to The Island."
        MAP_PATH="TheIsland_WP"
    fi
}

# Get the build ID from the appmanifest.acf file
get_build_id_from_acf() {
    if [[ -f "$PERSISTENT_ACF_FILE" ]]; then
        local build_id=$(grep -E "^\s+\"buildid\"\s+" "$PERSISTENT_ACF_FILE" | grep -o '[[:digit:]]*')
        echo "$build_id"
    else
        echo ""
    fi
}

# Get the current build ID from SteamCMD API
get_current_build_id() {
    local build_id=$(curl -sX GET "https://api.steamcmd.net/v1/info/$APPID" | jq -r ".data.\"$APPID\".depots.branches.public.buildid")
    echo "$build_id"
}

install_server() {
    local saved_build_id=$(get_build_id_from_acf)
    local current_build_id=$(get_current_build_id)

    if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
        echo "New server installation or update required..."
        echo "Current build ID is $current_build_id, initiating installation/update..."
        sudo -u games wine "$PROGRAM_FILES/Steam/steamcmd.exe" +login "$USERNAME" +force_install_dir "$ASA_DIR" +app_update "$APPID" +@sSteamCmdForcePlatformType windows +quit
        # Copy the acf file to the persistent volume
        cp "/usr/games/.wine/drive_c/POK/Steam/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
        echo "Installation or update completed successfully."
    else
        echo "No update required. Server build ID $saved_build_id is up to date."
    fi
}

update_server() {
    local saved_build_id=$(get_build_id_from_acf)
    local current_build_id=$(get_current_build_id)

    if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
        echo "Server update detected..."
        echo "Updating server to build ID $current_build_id from $saved_build_id..."
        sudo -u games wine "$PROGRAM_FILES/Steam/steamcmd.exe" +login "$USERNAME" +force_install_dir "$ASA_DIR" +app_update "$APPID" +@sSteamCmdForcePlatformType windows +quit
        # Copy the acf file to the persistent volume
        cp "/usr/games/.wine/drive_c/POK/Steam/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
        echo "Server update completed successfully."
    else
        echo "Server is already running the latest build ID $saved_build_id. Proceeding to start the server."
    fi
}

# Find the last "Log file open" entry and return the line number
find_new_log_entries() {
    LOG_FILE="$ASA_DIR/Saved/Logs/ShooterGame.log"
    LAST_ENTRY_LINE=$(grep -n "Log file open" "$LOG_FILE" | tail -1 | cut -d: -f1)
    echo $((LAST_ENTRY_LINE + 1)) # Return the line number after the last "Log file open"
}

# Update the ini file
update_ini() {
    /IniGenerator/IniGenerator
}

# Start the server and tail the log file
start_server() {
    # Check if the log file exists and rename it to archive
    local old_log_file="$ASA_DIR/Saved/Logs/ShooterGame.log"
    if [ -f "$old_log_file" ]; then
        local timestamp=$(date +%F-%T)
        mv "$old_log_file" "${old_log_file}_$timestamp"
    fi

    # Initialize the mods argument to an empty string
    local mods_arg=""
    # Initialize the battleye argument to an empty string
    local battleye_arg=""

    # Check if MOD_IDS is set and not empty
    if [ -n "$MOD_IDS" ]; then
        mods_arg="-mods=${MOD_IDS}"
    fi

    # Check the USE_BATTLEYE environment variable and set the appropriate flag
    if [ "$BATTLEEYE" = "TRUE" ]; then
        battleye_arg="-UseBattlEye"
    elif [ "$BATTLEEYE" = "FALSE" ]; then
        battleye_arg="-NoBattlEye"
    fi

    # Start the server with the conditional mods and battleye arguments
    sudo -u games wine "$ASA_DIR/Binaries/Win64/ArkAscendedServer.exe" \
        $MAP_PATH?listen?SessionName=${SESSION_NAME}?Port=${ASA_PORT}?QueryPort=${QUERY_PORT}?MaxPlayers=${MAX_PLAYERS}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD} \
        -clusterid=${CLUSTER_ID} -ClusterDirOverride=$CLUSTER_DIR_OVERRIDE \
        -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs -NotifyAdminCommandsInChat -nosteamclient \
        $mods_arg $battleye_arg 2>/dev/null &
    # Server PID
    SERVER_PID=$!

    # Wait for the log file to be created with a timeout
    local LOG_FILE="$ASA_DIR/Saved/Logs/ShooterGame.log"
    local TIMEOUT=120
    while [[ ! -f "$LOG_FILE" && $TIMEOUT -gt 0 ]]; do
        sleep 1
        ((TIMEOUT--))
    done
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Log file not found after waiting. Please check server status."
        return
    fi
    
    # Find the line to start tailing from
    local START_LINE=$(find_new_log_entries)

    # Tail the ShooterGame log file starting from the new session entries
    tail -n +"$START_LINE" -F "$LOG_FILE" &
    local TAIL_PID=$!

    # Wait for the server to exit
    wait $SERVER_PID

    # Kill the tail process when the server stops
    kill $TAIL_PID
}


# Main function
main() {
    initialize_variables
    start_xvfb
    install_server
    update_server
    determine_map_path
    cluster_dir
    update_ini
    start_server
    sleep infinity
}

# Start the main execution
main
