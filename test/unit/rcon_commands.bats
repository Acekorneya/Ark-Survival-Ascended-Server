#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "rcon_commands.sh can be sourced without executing commands" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    printf "send=%s\n" "$(type -t send_rcon_command)"
  '

  assert_success
  assert_output --partial "send=function"
}

@test "saveWorld delegates to send_rcon_command" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    send_rcon_command() {
      printf "command=%s\n" "$1"
    }
    saveWorld
  '

  assert_success
  assert_output --partial "command=saveworld"
  assert_output --partial "World save command issued."
}

@test "send_rcon_command retries a failed connection and succeeds on the next attempt" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    attempts_file="$BATS_TEST_TMPDIR/rcon-attempts"
    timeout() {
      local count=0
      if [ -f "$attempts_file" ]; then
        count=$(cat "$attempts_file")
      fi
      count=$((count + 1))
      echo "$count" > "$attempts_file"
      if [ "$count" -eq 1 ]; then
        echo "Failed to connect"
        return 1
      fi
      echo "No Players Connected"
      return 0
    }
    sleep() { :; }
    RCON_PATH=/usr/local/bin/rcon-cli
    RCON_HOST=127.0.0.1
    RCON_PORT=27020
    RCON_PASSWORD=secret
    set +e
    send_rcon_command "ListPlayers"
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "attempts=%s\n" "$(cat "$attempts_file")"
  '

  assert_success
  assert_output --partial "Warning: Failed to connect to RCON server (attempt 1/3). Retrying..."
  assert_output --partial "No Players Connected"
  assert_output --partial "status=0"
  assert_output --partial "attempts=2"
}

@test "send_rcon_command treats no-response confirmations as success" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    timeout() {
      echo "Server received, But no response!!"
      return 0
    }
    RCON_PATH=/usr/local/bin/rcon-cli
    RCON_HOST=127.0.0.1
    RCON_PORT=27020
    RCON_PASSWORD=secret
    send_rcon_command "DoExit"
  '

  assert_success
  assert_output --partial "Command received by server, but no response was provided."
}

@test "get_or_refresh_eos_token returns a cached token when it is still valid" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-cache.json"
    printf "%s" "{\"token\":\"cached-token\",\"expires_at\":1600}" > "$EOS_TOKEN_CACHE"
    date() { echo 1000; }
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
  '

  assert_success
  assert_output --partial "status=0"
  assert_output --partial "token=cached-token"
}

@test "get_or_refresh_eos_token reports cached token auth progress without polluting stdout" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    INSTANCE_NAME="demo"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-cache-progress.json"
    printf "%s" "{\"token\":\"cached-token\",\"expires_at\":1600}" > "$EOS_TOKEN_CACHE"
    date() { echo 1000; }
    set +e
    token=$(STATUS_AUTH_PROGRESS=TRUE get_or_refresh_eos_token 3>&2)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
  '

  assert_success
  assert_output --partial "Status auth: valid cached EOS userToken found (10m 0s remaining). Token source: cache."
  assert_output --partial "status=0"
  assert_output --partial "token=cached-token"
}

@test "get_or_refresh_eos_token can suppress cached token auth progress" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    INSTANCE_NAME="demo"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-cache-progress-suppressed.json"
    printf "%s" "{\"token\":\"cached-token\",\"expires_at\":1600}" > "$EOS_TOKEN_CACHE"
    date() { echo 1000; }
    set +e
    token=$(STATUS_AUTH_PROGRESS=TRUE STATUS_AUTH_SUPPRESS_CACHE_PROGRESS=TRUE get_or_refresh_eos_token 3>&2)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
  '

  assert_success
  refute_output --partial "Status auth: valid cached EOS userToken"
  assert_output --partial "status=0"
  assert_output --partial "token=cached-token"
}

@test "get_or_refresh_eos_token refreshes the cache when the token is missing or expired" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-refresh.json"
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    node() { echo "ticket-hex"; }
    python3() { printf "%s" "{\"token\":\"fresh-token\",\"expires_at\":1700}"; }
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
    printf "cache=%s\n" "$(cat "$EOS_TOKEN_CACHE")"
  '

  assert_success
  assert_output --partial "status=0"
  assert_output --partial "token=fresh-token"
  assert_output --partial "\"token\":\"fresh-token\""
}

@test "get_or_refresh_eos_token reports fresh exchange auth progress without leaking tokens" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    INSTANCE_NAME="demo"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-refresh-progress.json"
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    node() { printf "%0128d" 0 | tr "0" "A"; }
    python3() { printf "%s" "{\"token\":\"fresh-token\",\"expires_in\":3600,\"expires_at\":4600}"; }
    date() { echo 1000; }
    set +e
    token=$(STATUS_AUTH_PROGRESS=TRUE get_or_refresh_eos_token 3>&2)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
  '

  assert_success
  assert_output --partial "Status auth: no valid cached EOS userToken. Acquiring fresh Steam ticket..."
  assert_output --partial "Status auth: Steam ticket obtained (64 bytes)."
  assert_output --partial "Status auth: exchanging Steam ticket for EOS userToken..."
  assert_output --partial "Status auth: EOS userToken obtained (60m 0s remaining). Token source: fresh exchange."
  assert_output --partial "status=0"
  assert_output --partial "token=fresh-token"
  refute_output --partial "AAAAAAAAAAAAAAAA"
}

@test "get_or_refresh_eos_token normalizes Steam ticket hex before EOS exchange" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-uppercase.json"
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    node() { echo "deadbeef"; }
    python3() {
      printf "ticket_arg=%s\n" "$2" > "$BATS_TEST_TMPDIR/python-args"
      printf "%s" "{\"token\":\"fresh-token\",\"expires_at\":1700}"
    }
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
    cat "$BATS_TEST_TMPDIR/python-args"
  '

  assert_success
  assert_output --partial "status=0"
  assert_output --partial "token=fresh-token"
  assert_output --partial "ticket_arg=DEADBEEF"
}

@test "get_or_refresh_eos_token fails cleanly when Steam credentials are missing" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-missing.json"
    STEAM_USERNAME=""
    STEAM_PASSWORD=""
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "token=MISSING_CREDENTIALS"
}

@test "get_or_refresh_eos_token reports Steam ticket acquisition failures" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-ticket-fail.json"
    EOS_EXCHANGE_MAX_ATTEMPTS=1
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    node() { return 1; }
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "token=STEAM_TICKET_FAILED"
}

@test "get_or_refresh_eos_token fails immediately on Steam rate limiting" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-rate-limit.json"
    EOS_EXCHANGE_MAX_ATTEMPTS=3
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    attempts_file="$BATS_TEST_TMPDIR/ticket-attempts"
    node() {
      local count=0
      if [ -f "$attempts_file" ]; then
        count=$(cat "$attempts_file")
      fi
      count=$((count + 1))
      echo "$count" > "$attempts_file"
      echo "Steam error: RateLimitExceeded. Steam is temporarily rate-limiting this account. Wait a few minutes and try -status again." >&2
      return 1
    }
    sleep() { echo "unexpected-sleep"; }
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
    printf "attempts=%s\n" "$(cat "$attempts_file")"
  '

  assert_success
  assert_output --partial "Steam error: RateLimitExceeded. Steam is temporarily rate-limiting this account. Wait a few minutes and try -status again."
  assert_output --partial "status=1"
  assert_output --partial "token=STEAM_TICKET_FAILED"
  assert_output --partial "attempts=1"
  refute_output --partial "unexpected-sleep"
}

@test "get_or_refresh_eos_token fails immediately when Steam Guard is required" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-guard-required.json"
    EOS_EXCHANGE_MAX_ATTEMPTS=3
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    attempts_file="$BATS_TEST_TMPDIR/ticket-attempts"
    node() {
      local count=0
      if [ -f "$attempts_file" ]; then
        count=$(cat "$attempts_file")
      fi
      count=$((count + 1))
      echo "$count" > "$attempts_file"
      echo "STEAM_GUARD_REQUIRED:mobile authenticator" >&2
      echo "Steam Guard required (mobile authenticator). Enter the current 5-digit code from your Steam app when prompted." >&2
      return 1
    }
    sleep() { echo "unexpected-sleep"; }
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
    printf "attempts=%s\n" "$(cat "$attempts_file")"
  '

  assert_success
  assert_output --partial "STEAM_GUARD_REQUIRED:mobile authenticator"
  assert_output --partial "status=1"
  assert_output --partial "token=STEAM_TICKET_FAILED"
  assert_output --partial "attempts=1"
  refute_output --partial "unexpected-sleep"
}

@test "get_or_refresh_eos_token reports EOS exchange failures" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-exchange-fail.json"
    EOS_EXCHANGE_MAX_ATTEMPTS=1
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    node() { echo "ticket-hex"; }
    python3() { return 1; }
    set +e
    token=$(get_or_refresh_eos_token)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "token=EOS_EXCHANGE_FAILED"
}

@test "get_or_refresh_eos_token retries EOS exchange to allow Steam mobile approval" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-mobile-approval.json"
    EOS_EXCHANGE_MAX_ATTEMPTS=3
    EOS_EXCHANGE_RETRY_DELAY_SECONDS=1
    attempts_file="$BATS_TEST_TMPDIR/exchange-attempts"
    ticket_file="$BATS_TEST_TMPDIR/ticket-attempts"
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    node() {
      local count=0
      if [ -f "$ticket_file" ]; then
        count=$(cat "$ticket_file")
      fi
      count=$((count + 1))
      echo "$count" > "$ticket_file"
      echo "ticket-hex-${count}"
    }
    python3() {
      local count=0
      if [ -f "$attempts_file" ]; then
        count=$(cat "$attempts_file")
      fi
      count=$((count + 1))
      echo "$count" > "$attempts_file"
      if [ "$count" -lt 3 ]; then
        echo "EOS exchange failed (HTTP 400): approval pending" >&2
        return 1
      fi
      printf "%s" "{\"token\":\"fresh-token\",\"expires_at\":1700}"
    }
    sleep() { :; }
    set +e
    token=$(STATUS_AUTH_PROGRESS=TRUE get_or_refresh_eos_token 3>&2)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "token=%s\n" "$token"
    printf "attempts=%s\n" "$(cat "$attempts_file")"
    printf "ticket_attempts=%s\n" "$(cat "$ticket_file")"
  '

  assert_success
  assert_output --partial "EOS exchange failed. Waiting 1s before retrying (1/3)..."
  assert_output --partial "EOS exchange failed. Waiting 1s before retrying (2/3)..."
  assert_output --partial "status=0"
  assert_output --partial "token=fresh-token"
  assert_output --partial "attempts=3"
  assert_output --partial "ticket_attempts=1"
}

@test "full_status_display shows detailed EOS exchange errors" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_DEPLOYMENT_ID="deployment"
    curl() { echo "127.0.0.1"; }
    get_or_refresh_eos_token() {
      echo "EOS_EXCHANGE_FAILED"
      echo "EOS exchange failed (HTTP 400): approval pending" >&2
      return 1
    }
    set +e
    full_status_display
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Error: Failed to exchange Steam ticket for EOS token."
  assert_output --partial "EOS exchange failed (HTTP 400): approval pending"
  assert_output --partial "status=1"
}
