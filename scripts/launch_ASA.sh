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
    BUILD_ID_FILE="$ASA_DIR/build_id.txt"
}

# Start xvfb on display :0
start_xvfb() {
    Xvfb :0 -screen 0 1024x768x16 &
}

cluster_dir() {
    # Check if the Cluster directory exists
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

install_server() {
    local saved_build_id

    # Try to retrieve the saved build ID
    if [ -f "$BUILD_ID_FILE" ]; then
        saved_build_id=$(cat "$BUILD_ID_FILE")
    else
        echo "No saved build ID found. Will proceed to install the server."
        saved_build_id=""
    fi

    # Get the current build ID
    local current_build_id
    current_build_id=$(get_current_build_id)
    if [ -z "$current_build_id" ]; then
        echo "Unable to retrieve current build ID. Cannot proceed with installation."
        return 1
    fi

    # Compare the saved build ID with the current build ID
    if [ "$saved_build_id" != "$current_build_id" ]; then
        echo "Saved build ID ($saved_build_id) does not match current build ID ($current_build_id). Installing or updating the server..."
        sudo -u games wine "$PROGRAM_FILES/Steam/steamcmd.exe" +login "$USERNAME" +force_install_dir "$ASA_DIR" +app_update "$APPID" +@sSteamCmdForcePlatformType windows +quit

        # Save the new build ID
        save_build_id "$current_build_id"
    else
        echo "Server is up to date. Skipping installation."
    fi
}



 # Get the current build ID from SteamCMD API
get_current_build_id() {
    local build_id
    build_id=$(curl -sX GET "https://api.steamcmd.net/v1/info/$APPID" | jq -r ".data.\"$APPID\".depots.branches.public.buildid")
    
    # Check if the build ID is valid
    if [ -z "$build_id" ] || [ "$build_id" = "null" ]; then
        echo "Unable to retrieve current build ID."
        return 1
    fi
    
    echo "$build_id"
    return 0
}

# Check for updates and update the server if necessary
update_server() {
    CURRENT_BUILD_ID=$(get_current_build_id)
    
    if [ -z "$CURRENT_BUILD_ID" ]; then
        echo "Unable to retrieve current build ID. Skipping update check."
        return
    fi

    if [ ! -f "$BUILD_ID_FILE" ]; then
        echo "No previous build ID found. Assuming first run and skipping update check."
        save_build_id "$CURRENT_BUILD_ID"
        return
    fi

    PREVIOUS_BUILD_ID=$(cat "$BUILD_ID_FILE")
    if [ "$CURRENT_BUILD_ID" != "$PREVIOUS_BUILD_ID" ]; then
        echo "Update available (Previous: $PREVIOUS_BUILD_ID, Current: $CURRENT_BUILD_ID). Installing update..."
        sudo -u games wine "$PROGRAM_FILES/Steam/steamcmd.exe" +login "$USERNAME" +force_install_dir "$ASA_DIR" +app_update "$APPID" +@sSteamCmdForcePlatformType windows +quit
        save_build_id "$CURRENT_BUILD_ID"
    else
        echo "Continuing with server start."
    fi
}

# Save the build ID to a file and change ownership to the games user
save_build_id() {
    local build_id=$1
    echo "$build_id" > "$BUILD_ID_FILE"
    chown $PUID:$PGID "$BUILD_ID_FILE"
    echo "Saved build ID: $build_id"
}

# Find the last "Log file open" entry and return the line number
find_new_log_entries() {
    LOG_FILE="$ASA_DIR/Saved/Logs/ShooterGame.log"
    LAST_ENTRY_LINE=$(grep -n "Log file open" "$LOG_FILE" | tail -1 | cut -d: -f1)
    echo $((LAST_ENTRY_LINE + 1)) # Return the line number after the last "Log file open"
}

# Start the server and tail the log file
start_server() {
    
    # Check if the log file exists and rename it to archive
    local old_log_file="$ASA_DIR/Saved/Logs/ShooterGame.log"
    if [ -f "$old_log_file" ]; then
        local timestamp=$(date +%F-%T)
        mv "$old_log_file" "${old_log_file}_$timestamp"
    fi

    sudo -u games wine "$ASA_DIR/Binaries/Win64/ArkAscendedServer.exe" $MAP_PATH?listen?SessionName=${SESSION_NAME}?Port=${ASA_PORT}?QueryPort=${QUERY_PORT}?MaxPlayers=${MAX_PLAYERS}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD} -clusterid=${CLUSTER_ID} -ClusterDirOverride=$CLUSTER_DIR_OVERRIDE -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs -NotifyAdminCommandsInChat -useallavailablecores -usecache -nosteamclient -game -server -log 2>/dev/null &
    # Server PID
    SERVER_PID=$!

      # Wait for the log file to be created with a timeout
    LOG_FILE="$ASA_DIR/Saved/Logs/ShooterGame.log"
    TIMEOUT=120
    while [[ ! -f "$LOG_FILE" && $TIMEOUT -gt 0 ]]; do
        sleep 1
        ((TIMEOUT--))
    done
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Log file not found after waiting. Please check server status."
        return
    fi
    
    # Find the line to start tailing from
    START_LINE=$(find_new_log_entries)

    # Tail the ShooterGame log file starting from the new session entries
    tail -n +"$START_LINE" -F "$ASA_DIR/Saved/Logs/ShooterGame.log" &
    TAIL_PID=$!

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
    start_server
    sleep infinity
}

main