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

# Function to initiate server shutdown
shutdownServer() {
  send_rcon_command "DoExit"
  echo "Server shutdown command issued."
}

# Enhanced RCON command function with better error handling
send_rcon_command() {
  local command="$1"
  local max_retries=3
  local retry=0
  local success=false

  # Configure timeout for rcon command to prevent hanging
  local timeout_seconds=10
  
  while [ $retry -lt $max_retries ] && [ "$success" = "false" ]; do
    # Capture the output and error of the rcon command with timeout
    local output
    output=$(timeout $timeout_seconds ${RCON_PATH} -a ${RCON_HOST}:${RCON_PORT} -p "${RCON_PASSWORD}" "$command" 2>&1)
    local status=$?
    
    # Check for timeout
    if [ $status -eq 124 ]; then
      echo "Warning: RCON command timed out after $timeout_seconds seconds. Retrying..." >&2
      retry=$((retry + 1))
      sleep 1
      continue
    fi

    # Check if the output contains a critical failure message
    if echo "$output" | grep -q "Failed to connect"; then
      if [ $retry -lt $((max_retries - 1)) ]; then
        echo "Warning: Failed to connect to RCON server (attempt $((retry + 1))/$max_retries). Retrying..." >&2
        retry=$((retry + 1))
        sleep 1
      else
        echo "Error: Failed to connect to RCON server after $max_retries attempts." >&2
        return 1
      fi
    elif [ "${RCON_QUIET_MODE:-FALSE}" != "TRUE" ] && echo "$output" | grep -q "Server received, But no response!!"; then
      # For commands that don't return responses (like DoExit), this is normal
      echo "Command received by server, but no response was provided." >&2
      success=true
      break
    else
      # Command succeeded
      success=true
      
      # Only print output if not in quiet mode or if output contains actual content beyond status messages
      if [ "${RCON_QUIET_MODE:-FALSE}" != "TRUE" ] || ! echo "$output" | grep -q "Server received"; then
        echo "$output" # Print the output for visibility
      fi
      
      break
    fi
  done
  
  # Return success or failure
  if [ "$success" = "true" ]; then
    return 0
  else
    return 1
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

# Function to check PDB availability and download pdb-sym2addr-rs
full_status_setup() {
  echo "Full status setup no longer requires extracting credentials."
  return 0
}

full_status_first_run() {
  return 0
}


# Display full server status
full_status_display() {
  # Check if the EOS credentials file exists
  # Recover current ip
  ip=$(curl -s https://ifconfig.me/ip)

  deployment_id="$EOS_DEPLOYMENT_ID"

  if [ -z "$deployment_id" ] || [ -z "$EOS_BASIC_AUTH" ]; then
    echo "Error: EOS credential constants are not set"
    return 1
  fi

  # Requesting OAuth token from EOS
  oauthResponse=$(
    curl -s -H 'Content-Type: application/x-www-form-urlencoded' \
      -H 'Accept: application/json' \
      -H "Authorization: ${EOS_BASIC_AUTH}" \
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
    curl -s -X "POST" "${EOS_MATCHMAKING_BASE}/${deployment_id}/filter" \
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
  mods=$(echo "$serv" | jq -r '.attributes.ENABLEDMODS_s // empty')
  if [[ -z "$mods" ]]; then
    local mods_ids
    mods_ids=$(echo "$serv" | jq -r '.attributes.ENABLEDMODSFILEIDS_s // empty')
    if [[ -n "$mods_ids" ]]; then
      mods="IDs: ${mods_ids}"
    fi
  fi
  server_version_detailed=$(echo "$serv" | jq -r '.attributes.SESSIONNAMEUPPER_s' | grep -oP '\(V\K[\d.]+(?=\))')
  server_address="$ip:${ASA_PORT}"
  cluster_id=$(echo "$serv" | jq -r '.attributes.CLUSTERID_s')
  eos_server_ping=$(echo "$serv" | jq -r '.attributes.EOSSERVERPING_l')

  if [[ -z "$mods" || "$mods" == "null" ]]; then
    mods="None"
  fi

  if [[ -z "$cluster_id" || "$cluster_id" == "null" ]]; then
    cluster_id="None"
  fi

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
  echo "Displaying server status..."
  full_status_display
}
