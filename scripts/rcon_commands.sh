#!/bin/bash
#
# Reusable RCON command helpers shared by monitor, restart, and CLI wrappers.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"

EOS_TOKEN_CACHE="/home/pok/arkserver/ShooterGame/Binaries/Win64/.eos_token.json"
HELPERS_DIR="/home/pok/scripts/helpers"

_status_auth_format_duration() {
  local seconds="${1:-0}"
  local minutes=0
  local remaining_seconds=0

  if ! [[ "$seconds" =~ ^[0-9]+$ ]]; then
    seconds=0
  fi

  minutes=$((seconds / 60))
  remaining_seconds=$((seconds % 60))
  printf '%sm %ss' "$minutes" "$remaining_seconds"
}

_status_auth_progress() {
  local message="$1"
  local prefix="Status auth"
  local progress_fd="${STATUS_AUTH_PROGRESS_FD:-2}"

  if [ "${STATUS_AUTH_PROGRESS:-FALSE}" != "TRUE" ]; then
    return 0
  fi

  printf '%s: %s\n' "$prefix" "$message" >&"${progress_fd}"
}

_status_auth_token_remaining() {
  local token_json="$1"
  local now="$2"
  local expires_in=""
  local expires_at=""

  expires_in=$(printf '%s' "$token_json" | jq -r '.expires_in // empty' 2>/dev/null)
  if [[ "$expires_in" =~ ^[0-9]+$ ]]; then
    printf '%s' "$expires_in"
    return 0
  fi

  expires_at=$(printf '%s' "$token_json" | jq -r '.expires_at // empty' 2>/dev/null)
  if [[ "$expires_at" =~ ^[0-9]+$ ]] && [ "$expires_at" -gt "$now" ]; then
    printf '%s' "$((expires_at - now))"
    return 0
  fi

  printf '0'
}

get_or_refresh_eos_token() {
  local ticket_err_file=""
  local exchange_err_file=""
  local ticket_status=0
  local exchange_status=0
  local ticket_error=""
  local exchange_error=""
  local exchange_attempt=1
  local max_attempts="${EOS_EXCHANGE_MAX_ATTEMPTS:-12}"
  local retry_delay="${EOS_EXCHANGE_RETRY_DELAY_SECONDS:-5}"
  local ticket_hex=""
  local token_json=""
  local suppress_cache_progress="${STATUS_AUTH_SUPPRESS_CACHE_PROGRESS:-FALSE}"

  if [ -f "$EOS_TOKEN_CACHE" ]; then
    local token expires_at now buffer=300
    token=$(jq -r '.token' "$EOS_TOKEN_CACHE" 2>/dev/null)
    expires_at=$(jq -r '.expires_at' "$EOS_TOKEN_CACHE" 2>/dev/null)
    now=$(date +%s)

    if [ -n "$token" ] && [ "$token" != "null" ] && \
       [ -n "$expires_at" ] && [ "$expires_at" != "null" ] && \
       [ "$now" -lt "$((expires_at - buffer))" ] 2>/dev/null; then
      if [ "$suppress_cache_progress" != "TRUE" ]; then
        _status_auth_progress "valid cached EOS userToken found ($(_status_auth_format_duration "$((expires_at - now))") remaining). Token source: cache."
      fi
      echo "$token"
      return 0
    fi
  fi

  if [ -z "$STEAM_USERNAME" ] || [ -z "$STEAM_PASSWORD" ]; then
    echo "MISSING_CREDENTIALS"
    return 1
  fi

  _status_auth_progress "no valid cached EOS userToken. Acquiring fresh Steam ticket..."

  _steam_ticket_error_is_retryable() {
    local ticket_error_text="$1"

    case "$ticket_error_text" in
      *"STEAM_GUARD_REQUIRED:"*)
        return 1
        ;;
      *"RateLimitExceeded"*)
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }

  while [ "$exchange_attempt" -le "$max_attempts" ]; do
    # The container path uses steam-user for ticket generation. Request a
    # fresh Steam ticket on every retry so we don't keep reusing a ticket that
    # was created before mobile approval or app session readiness completed.
    ticket_err_file=$(mktemp)
    ticket_hex=$(node "${HELPERS_DIR}/steam_ticket.js" 2>"$ticket_err_file")
    ticket_status=$?
    ticket_error="$(cat "$ticket_err_file" 2>/dev/null)"
    rm -f "$ticket_err_file"

    if [ $ticket_status -ne 0 ] || [ -z "$ticket_hex" ]; then
      if [ -n "$ticket_error" ] && ! _steam_ticket_error_is_retryable "$ticket_error"; then
        printf '%s\n' "$ticket_error" >&2
        echo "STEAM_TICKET_FAILED"
        return 1
      fi

      if [ "$exchange_attempt" -lt "$max_attempts" ]; then
        _status_auth_progress "Steam ticket is not ready yet. Waiting ${retry_delay}s before retrying (${exchange_attempt}/${max_attempts})..."
        sleep "$retry_delay"
        exchange_attempt=$((exchange_attempt + 1))
        continue
      fi

      if [ -n "$ticket_error" ]; then
        printf '%s\n' "$ticket_error" >&2
      else
        echo "Steam ticket helper returned no ticket." >&2
      fi
      echo "STEAM_TICKET_FAILED"
      return 1
    fi
    ticket_hex="${ticket_hex^^}"
    _status_auth_progress "Steam ticket obtained ($((${#ticket_hex} / 2)) bytes)."
    _status_auth_progress "exchanging Steam ticket for EOS userToken..."

    exchange_err_file=$(mktemp)
    token_json=$(python3 "${HELPERS_DIR}/eos_token.py" "$ticket_hex" 2>"$exchange_err_file")
    exchange_status=$?
    exchange_error="$(cat "$exchange_err_file" 2>/dev/null)"
    rm -f "$exchange_err_file"

    if [ $exchange_status -eq 0 ] && [ -n "$token_json" ]; then
      break
    fi

    if [ "$exchange_attempt" -lt "$max_attempts" ]; then
      _status_auth_progress "Steam login may still be awaiting mobile approval or the session ticket may not be ready yet. Waiting ${retry_delay}s before requesting a fresh Steam ticket and retrying EOS token exchange (${exchange_attempt}/${max_attempts})..."
      sleep "$retry_delay"
    fi

    exchange_attempt=$((exchange_attempt + 1))
  done

  if [ $exchange_status -ne 0 ] || [ -z "$token_json" ]; then
    if [ -n "$exchange_error" ]; then
      printf '%s\n' "$exchange_error" >&2
    else
      echo "EOS token helper returned no token." >&2
    fi
    echo "EOS_EXCHANGE_FAILED"
    return 1
  fi

  mkdir -p "$(dirname "$EOS_TOKEN_CACHE")"
  local tmp_cache="${EOS_TOKEN_CACHE}.tmp.$$"
  printf '%s' "$token_json" > "$tmp_cache"
  mv "$tmp_cache" "$EOS_TOKEN_CACHE"

  _status_auth_progress "EOS userToken obtained ($(_status_auth_format_duration "$(_status_auth_token_remaining "$token_json" "$(date +%s)")") remaining). Token source: fresh exchange."

  echo "$token_json" | jq -r '.token'
  return 0
}

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

# Display full server status
full_status_display() {
  local token=""
  local token_status=0
  local auth_error_file=""
  local auth_error=""

  # Recover current ip
  ip=$(curl -s https://ifconfig.me/ip)

  deployment_id="$EOS_DEPLOYMENT_ID"

  if [ -z "$deployment_id" ]; then
    echo "Error: EOS deployment constant is not set"
    return 1
  fi

  auth_error_file=$(mktemp)
  token=$(STATUS_AUTH_PROGRESS=TRUE STATUS_AUTH_PROGRESS_FD=3 get_or_refresh_eos_token 3>&2 2>"$auth_error_file")
  token_status=$?
  auth_error="$(cat "$auth_error_file" 2>/dev/null)"
  rm -f "$auth_error_file"

  if [ $token_status -ne 0 ] || [ -z "$token" ]; then
    case "$token" in
    "MISSING_CREDENTIALS")
      echo "Error: Steam credentials not configured."
      echo "Add STEAM_USERNAME and STEAM_PASSWORD to your docker-compose environment section."
      echo "Or run -status again - the manager will prompt you to set them up."
      ;;
    "STEAM_TICKET_FAILED")
      echo "Error: Failed to get Steam session ticket."
      echo "Check your STEAM_USERNAME, STEAM_PASSWORD, and current Steam Guard mobile code if the account requires one."
      if [ -n "$auth_error" ]; then
        printf '%s\n' "$auth_error"
      fi
      ;;
    "EOS_EXCHANGE_FAILED")
      echo "Error: Failed to exchange Steam ticket for EOS token."
      if [ -n "$auth_error" ]; then
        printf '%s\n' "$auth_error"
      fi
      ;;
    *)
      echo "Error: Could not get EOS authentication token."
      ;;
    esac
    return 1
  fi

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
