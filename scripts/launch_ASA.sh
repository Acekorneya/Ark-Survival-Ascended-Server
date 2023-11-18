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
    # Clean and format MOD_IDS if it's set
    if [ -n "$MOD_IDS" ]; then
        # Remove all quotes and extra spaces
        MOD_IDS=$(echo "$MOD_IDS" | tr -d '"' | tr -d "'" | tr -d ' ')
    fi
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
    case "$MAP_NAME" in
        "TheIsland")
            MAP_PATH="TheIsland_WP"
            ;;
        "ScorchedEarth")
            MAP_PATH="ScorchedEarth_WP"
            ;;
        *)
            # Check if the custom MAP_NAME already ends with '_WP'
            if [[ "$MAP_NAME" == *"_WP" ]]; then
                MAP_PATH="$MAP_NAME"
            else
                MAP_PATH="${MAP_NAME}_WP"
            fi
            echo "Using map: $MAP_PATH"
            ;;
    esac
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
        touch /usr/games/updating.flag
        echo "Current build ID is $current_build_id, initiating installation/update..."
        sudo -u games wine "$PROGRAM_FILES/Steam/steamcmd.exe" +login "$USERNAME" +force_install_dir "$ASA_DIR" +app_update "$APPID" +@sSteamCmdForcePlatformType windows +quit
        # Copy the acf file to the persistent volume
        cp "/usr/games/.wine/drive_c/POK/Steam/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
        echo "Installation or update completed successfully."
        rm -f /usr/games/updating.flag
    else
        echo "No update required. Server build ID $saved_build_id is up to date."
    fi
}

update_server() {
    local saved_build_id=$(get_build_id_from_acf)
    local current_build_id=$(get_current_build_id)

    if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
        echo "Server update detected..."
        touch /usr/games/updating.flag
        echo "Updating server to build ID $current_build_id from $saved_build_id..."
        sudo -u games wine "$PROGRAM_FILES/Steam/steamcmd.exe" +login "$USERNAME" +force_install_dir "$ASA_DIR" +app_update "$APPID" +@sSteamCmdForcePlatformType windows +quit
        # Copy the acf file to the persistent volume
        cp "/usr/games/.wine/drive_c/POK/Steam/steamapps/appmanifest_$APPID.acf" "$PERSISTENT_ACF_FILE"
        echo "Server update completed successfully."
        rm -f /usr/games/updating.flag
    else
        echo "Server is already running the latest build ID $saved_build_id. Proceeding to start the server."
    fi
}

# Function to check if save is complete
save_complete_check() {
    local log_file="$ASA_DIR/Saved/Logs/ShooterGame.log"
    # Check if the "World Save Complete" message is in the log file
    if tail -n 10 "$log_file" | grep -q "World Save Complete"; then
        echo "Save operation completed."
        return 0
    else
        return 1
    fi
}

# Function to handle graceful shutdown
shutdown_handler() {
    echo "Initiating graceful shutdown..."
    echo "Notifying players about the immediate shutdown and save..."
    rcon-cli --host localhost --port $RCON_PORT --password $SERVER_ADMIN_PASSWORD "ServerChat Immediate server shutdown initiated. Saving the world..."

    echo "Saving the world..."
    rcon-cli --host localhost --port $RCON_PORT --password $SERVER_ADMIN_PASSWORD "saveworld"

    # Wait for save to complete
    echo "Waiting for save to complete..."
    while ! save_complete_check; do
        sleep 5  # Check every 5 seconds
    done

    echo "World saved. Shutting down the server..."
 
    exit 0
}

# Trap SIGTERM
trap 'shutdown_handler' SIGTERM

# Find the last "Log file open" entry and return the line number
find_new_log_entries() {
    LOG_FILE="$ASA_DIR/Saved/Logs/ShooterGame.log"
    LAST_ENTRY_LINE=$(grep -n "Log file open" "$LOG_FILE" | tail -1 | cut -d: -f1)
    echo $((LAST_ENTRY_LINE + 1)) # Return the line number after the last "Log file open"
}

start_server() {

   # Check if the log file exists and rename it to archive
    local old_log_file="$ASA_DIR/Saved/Logs/ShooterGame.log"
    if [ -f "$old_log_file" ]; then
        local timestamp=$(date +%F-%T)
        mv "$old_log_file" "${old_log_file}_$timestamp.log"
    fi

    # Initialize the mods argument to an empty string
    local mods_arg=""
    local battleye_arg=""
    local rcon_args=""
    local custom_args=""
    local session_name_arg="SessionName=\"${SESSION_NAME}\""

    # Check if MOD_IDS is set and not empty
    if [ -n "$MOD_IDS" ]; then
        mods_arg="-mods=${MOD_IDS}"
    fi

    # Set BattlEye flag based on environment variable
    if [ "$BATTLEEYE" = "TRUE" ]; then
        battleye_arg="-UseBattlEye"
    elif [ "$BATTLEEYE" = "FALSE" ]; then
        battleye_arg="-NoBattlEye"
    fi

    # Set RCON arguments based on RCON_ENABLED environment variable
    if [ "$RCON_ENABLED" = "TRUE" ]; then
        rcon_args="?RCONEnabled=True?RCONPort=${RCON_PORT}"
    elif [ "$RCON_ENABLED" = "FALSE" ]; then
        rcon_args="?RCONEnabled=False?"
    fi
    
    if [ -n "$CUSTOM_SERVER_ARGS" ]; then
        custom_args="$CUSTOM_SERVER_ARGS"
    fi

    # Start the server with conditional arguments
    sudo -u games wine "$ASA_DIR/Binaries/Win64/ArkAscendedServer.exe" \
        $MAP_PATH?listen?$session_name_arg?Port=${ASA_PORT}${rcon_args}?MaxPlayers=${MAX_PLAYERS}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD} \
        -clusterid=${CLUSTER_ID} -ClusterDirOverride=$CLUSTER_DIR_OVERRIDE \
        -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs -NotifyAdminCommandsInChat -nosteamclient $custom_args \
        $mods_arg $battleye_arg 2>/dev/null &

    SERVER_PID=$!
    echo "Server process started with PID: $SERVER_PID"

    # Immediate write to PID file
    echo $SERVER_PID > /usr/games/ark_server.pid
    echo "PID $SERVER_PID written to /usr/games/ark_server.pid"

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
    tail -n +"$START_LINE" -f "$LOG_FILE" &
    local TAIL_PID=$!

    # Wait for the server to fully start
    echo "Waiting for server to start..."
    while true; do
        if grep -q "wp.Runtime.HLOD" "$LOG_FILE"; then
            echo "Server started. PID: $SERVER_PID"
            break
        fi
        sleep 10
    done

    # Wait for the server process to exit
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
}

# Start the main execution
main
