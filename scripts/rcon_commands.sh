#!/bin/bash
source /home/pok/scripts/common.sh

# Define RCON commands as functions
saveWorld() {
  send_rcon_command "saveworld"
  echo "World save command issued."
}

sendChat() {
  local message="$1"
  send_rcon_command "ServerChat $message" 
  echo "Chat message sent: $message"
}

send_rcon_command() {
  local command="$1"

  # Capture the output and error of the rcon-cli command
  local output
  output=$(rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" "$command" 2>&1)

  echo "$output" # Print the output for visibility

  # Check if the output contains a critical failure message
  if echo "$output" | grep -q "Failed to connect to RCON server"; then
    echo "Error: Failed to connect to RCON server. Terminating script." >&2
    exit 1 # Exit the script with an error status
  elif echo "$output" | grep -q "Server received, But no response!!"; then
    echo "Warning: Command received by server, but no response was provided." >&2
    # Optionally, you can handle this case differently, such as logging the incident or sending a notification.
  fi
}


# Function for interactive mode
interactive_mode() {
  echo "Entering interactive RCON mode. Type 'exit' to quit."
  while true; do
    echo -n "RCON> "
    read -r cmd args
    if [[ "$cmd" == "exit" ]]; then
      break
    fi
    # Pass command and arguments to main function
    main "$cmd" "$args"
  done
}

# Function for restart sequence
initiate_restart() {
  local duration_in_minutes

  if [ -z "$1" ]; then
    while true; do
      echo -n "Enter countdown duration in minutes (or type 'cancel' to return to main menu): "
      read input

      if [[ "$input" =~ ^[0-9]+$ ]]; then
        duration_in_minutes=$input
        break
      elif [[ "$input" == "cancel" ]]; then
        echo "Restart cancelled. Returning to main menu."
        return
      else
        echo "Invalid input. Please enter a number or 'cancel'."
      fi
    done
  else
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
      echo "Invalid duration: $1. Must be a number."
      return
    fi
    duration_in_minutes=$1
  fi

  local total_seconds=$((duration_in_minutes * 60))
  local seconds_remaining=$total_seconds

  while [ $seconds_remaining -gt 0 ]; do
    local minutes_remaining=$((seconds_remaining / 60))

    if [ $seconds_remaining -le 10 ]; then
      # Notify every second for the last 10 seconds
      send_rcon_command "ServerChat Server restarting in $seconds_remaining second(s)"
    elif [ $((seconds_remaining % 300)) -eq 0 ] || [ $seconds_remaining -eq $total_seconds ]; then
      # Notify at 5 minute intervals
      send_rcon_command "ServerChat Server restarting in $minutes_remaining minute(s)"
    fi

    sleep 1
    ((seconds_remaining--))
  done

  send_rcon_command "saveworld"
  echo "World saved. Restarting the server..."
  send_rcon_command "DoExit"
  rm -f "$PID_FILE"
  echo "----Server restart complete----"
}

# Function for shutdown sequence
initiate_shutdown() {
  local duration_in_minutes

  if [ -z "$1" ]; then
    while true; do
      echo -n "Enter countdown duration in minutes (or type 'cancel' to return to main menu): "
      read input

      if [[ "$input" =~ ^[0-9]+$ ]]; then
        duration_in_minutes=$input
        break
      elif [[ "$input" == "cancel" ]]; then
        echo "Restart cancelled. Returning to main menu."
        return
      else
        echo "Invalid input. Please enter a number or 'cancel'."
      fi
    done
  else
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
      echo "Invalid duration: $1. Must be a number."
      return
    fi
    duration_in_minutes=$1
  fi

  local total_seconds=$((duration_in_minutes * 60))
  local seconds_remaining=$total_seconds

  while [ $seconds_remaining -gt 0 ]; do
    local minutes_remaining=$((seconds_remaining / 60))

    if [ $seconds_remaining -le 10 ]; then
      # Notify every second for the last 10 seconds
      send_rcon_command "ServerChat Server Shuting Down in $seconds_remaining second(s)"
    elif [ $((seconds_remaining % 300)) -eq 0 ] || [ $seconds_remaining -eq $total_seconds ]; then
      # Notify at 5 minute intervals
      send_rcon_command "ServerChat Server Shuting Down in $minutes_remaining minute(s)"
    fi

    sleep 1
    ((seconds_remaining--))
  done

  send_rcon_command "saveworld"
  echo "World saved. Shuting Down the server..."
  send_rcon_command "DoExit"
  rm -f "$PID_FILE"
}
# Function to check PDB availability and download pdb-sym2addr-rs
full_status_setup() {
  # Ensure the pdb file exists
  if [[ ! -f "$ASA_DIR/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" ]]; then
    echo "$ASA_DIR/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb is needed to setup full status."
    return 1
  fi

  # Download and extract pdb-sym2addr-rs to a specific directory
  mkdir -p "$ASA_DIR/pdb-sym2addr"
  wget -q https://github.com/azixus/pdb-sym2addr-rs/releases/latest/download/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -O "$ASA_DIR/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz"
  tar -xzf "$ASA_DIR/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz" -C "$ASA_DIR/pdb-sym2addr"
  rm "$ASA_DIR/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz"

  # Extract and save EOS credentials
  symbols=$("$ASA_DIR/pdb-sym2addr/pdb-sym2addr" "$ASA_DIR/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" "$ASA_DIR/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" DedicatedServerClientSecret DedicatedServerClientId DeploymentId)

  client_id=$(echo "$symbols" | grep -o 'DedicatedServerClientId.*' | cut -d, -f2)
  client_secret=$(echo "$symbols" | grep -o 'DedicatedServerClientSecret.*' | cut -d, -f2)
  deployment_id=$(echo "$symbols" | grep -o 'DeploymentId.*' | cut -d, -f2)

  # Save base64 login and deployment id to file
  creds=$(echo -n "$client_id:$client_secret" | base64 -w0)
  echo "${creds},${deployment_id}" > "$EOS_FILE"
}

full_status_first_run() {
  # Automatically proceed with the full status setup without user confirmation
  echo "Proceeding with full status setup..."
  full_status_setup

  if [[ $? != 0 ]]; then
    echo "Full status setup failed."
    return 1
  else
    echo "Full status setup completed successfully." 
    return 0
  fi
}


# Display full server status
full_status_display() {
  # Check if the EOS credentials file exists
  if [[ ! -f "$EOS_FILE" ]]; then
    echo "Error: EOS credentials file not found at $EOS_FILE."
    return 1
  fi

  # Read the full content from the file
  fullContent=$(tr -d ' \n' < "$EOS_FILE")
  # echo "Debug: Full Content: '${fullContent}'"

  # Recover current ip
  ip=$(curl -s https://ifconfig.me/ip)

  # Split the content to get the base64-encoded credentials and the deployment ID
  IFS=',' read -ra ADDR <<< "$fullContent"
  creds="${ADDR[0]}"
  deployment_id="${ADDR[1]}"

  # echo "Debug: Using Credentials (base64 encoded): '${creds}'"
  # echo "Debug: Deployment ID: ${deployment_id}"

  # Requesting OAuth token from EOS
  oauthResponse=$(
    curl -s -H 'Content-Type: application/x-www-form-urlencoded' \
      -H 'Accept: application/json' \
      -H "Authorization: Basic ${creds}" \
      -X POST https://api.epicgames.dev/auth/v1/oauth/token \
      -d "grant_type=client_credentials&deployment_id=${deployment_id}"
  )

  if echo "$oauthResponse" | jq -e '.error' >/dev/null; then
    echo "Error: OAuth request failed with error: $(echo "$oauthResponse" | jq -r '.error_description')"
    return 1
  fi

  token=$(echo "$oauthResponse" | jq -r '.access_token')

  # Server query request
  res=$(
    curl -s -X "POST" "https://api.epicgames.dev/matchmaking/v1/${deployment_id}/filter" \
      -H "Content-Type:application/json" \
      -H "Accept:application/json" \
      -H "Authorization: Bearer $token" \
      -d "{\"criteria\": [{\"key\": \"attributes.ADDRESS_s\", \"op\": \"EQUAL\", \"value\": \"${ip}\"}]}"
  )

  # Error handling in response
  if [[ "$res" == *"errorCode"* ]]; then
    echo "Error: Failed to query EOS... Possible issue with the request or server registration."
    return 1
  fi

  # Extract the server based on the ASA_PORT
  serv=$(echo "$res" | jq -r ".sessions[] | select( .attributes.ADDRESSBOUND_s | endswith(\":${ASA_PORT}\"))")

  if [[ -z "$serv" ]]; then
    echo "Error: Server not found under the current IP: $ip and PORT: $ASA_PORT. Server might be down or not started yet."
    return 1
  fi

  # Extract information to display
  server_name=$(echo "$serv" | jq -r '.attributes.CUSTOMSERVERNAME_s')
  map=$(echo "$serv" | jq -r '.attributes.MAPNAME_s')
  day=$(echo "$serv" | jq -r '.attributes.DAYTIME_s')
  players=$(echo "$serv" | jq -r '.totalPlayers')
  max_players=$(echo "$serv" | jq -r '.settings.maxPublicPlayers')
  mods=$(echo "$serv" | jq -r '.attributes.ENABLEDMODS_s')
  server_version_detailed=$(echo "$serv" | jq -r '.attributes.SESSIONNAMEUPPER_s' | grep -oP '\(V\K[\d.]+(?=\))')
  server_address="$ip:${ASA_PORT}"
  cluster_id=$(echo "$serv" | jq -r '.attributes.CLUSTERID_s')
  eos_server_ping=$(echo "$serv" | jq -r '.attributes.EOSSERVERPING_l')

  echo -e "Server Name:    $server_name"
  echo -e "Map:            $map"
  echo -e "Day:            $day"
  echo -e "Players:        $players / $max_players" 
  echo -e "Mods:           $mods"
  echo -e "Cluster ID:     $cluster_id"
  echo -e "Server Version: $server_version_detailed"
  echo -e "Server Address: $server_address"
  echo -e "Server Ping:    $eos_server_ping ms"
  echo "Server is up"
}


# Server status function
status() {
  if [[ ! -f "$EOS_FILE" ]]; then
    echo "Full status setup is required. Running setup now..."
    full_status_first_run
    if [[ $? != 0 ]]; then
      echo "Unable to proceed without full status setup."
      return
    fi
  fi

  echo "Displaying server status..."
  full_status_display
}
