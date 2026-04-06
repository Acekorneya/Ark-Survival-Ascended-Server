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

@test "get_or_refresh_eos_token refreshes the cache when the token is missing or expired" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-refresh.json"
    STEAM_USERNAME="steam_user"
    STEAM_PASSWORD="steam_pass"
    STEAM_SHARED_SECRET=""
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

@test "get_or_refresh_eos_token reports EOS exchange failures" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_commands.sh"
    EOS_TOKEN_CACHE="$BATS_TEST_TMPDIR/eos-token-exchange-fail.json"
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
