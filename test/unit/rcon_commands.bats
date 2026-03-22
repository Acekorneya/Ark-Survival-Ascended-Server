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
