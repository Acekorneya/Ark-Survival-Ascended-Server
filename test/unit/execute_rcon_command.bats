#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "execute_rcon_command processes all running instances for standard commands" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-all" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { echo "alpha beta"; }
    validate_instance() { return 0; }
    run_in_container() { echo "ran:$1:$2:$3"; }
    execute_rcon_command -saveworld -all
  '

  assert_success
  assert_output --partial "----- Processing -saveworld command for all running instances. Please wait... -----"
  assert_output --partial "----- Server alpha: Command: saveworld -----"
  assert_output --partial "----- Server beta: Command: saveworld -----"
  assert_output --partial "ran:alpha:-saveworld:"
  assert_output --partial "ran:beta:-saveworld:"
}

@test "execute_rcon_command normalizes invalid shutdown timers before dispatch" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-shutdown" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { echo "alpha"; }
    enhanced_shutdown_command() { echo "shutdown:$1:$2"; }
    execute_rcon_command -shutdown -all nope
  '

  assert_success
  assert_output --partial "Error: Invalid shutdown time 'nope'. Must be a positive number."
  assert_output --partial "Using default of 1 minute instead."
  assert_output --partial "Using enhanced shutdown functionality for all instances..."
  assert_output --partial "shutdown:1:-all"
}

@test "execute_rcon_command warns before single-instance restart when running instances mix API modes" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-restart" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo" "$BASE_DIR/Instance_other"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<EOF
services:
  asaserver:
    environment:
      - API=TRUE
EOF
    cat > "$BASE_DIR/Instance_other/docker-compose-other.yaml" <<EOF
services:
  asaserver:
    environment:
      - API=FALSE
EOF
    source "$REPO_ROOT/POK-manager.sh"
    validate_instance() { return 0; }
    list_running_instances() { echo "demo other"; }
    enhanced_restart_command() { echo "restart:$1:$2"; }
    sleep() { :; }
    execute_rcon_command -restart demo 5
  '

  assert_success
  assert_output --partial "Using enhanced restart functionality for instance: demo"
  assert_output --partial "⚠️ WARNING: Mixed API modes detected across running instances. ⚠️"
  assert_output --partial "restart:5:demo"
}

@test "execute_rcon_command skips single-instance status output until the server is fully started" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-status" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    validate_instance() { return 0; }
    docker() {
      if [[ "$*" == *"/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"* ]]; then
        return 1
      fi
      if [[ "$*" == *"/home/pok/update.flag"* ]]; then
        return 1
      fi
      return 0
    }
    run_in_container() { echo "unexpected-run"; }
    execute_rcon_command -status demo
  '

  assert_success
  assert_output --partial "Processing -status command on demo..."
  assert_output --partial "Instance demo has not fully started yet. Please wait a few minutes before checking the status."
  refute_output --partial "unexpected-run"
}

@test "execute_rcon_command routes single-instance status through the Steam-aware helper" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-status-helper" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    validate_instance() { return 0; }
    _rcon_status_ready() { return 0; }
    ensure_steam_credentials() {
      STEAM_USERNAME="steam_user"
      STEAM_PASSWORD="steam_pass"
      STEAM_SHARED_SECRET=""
    }
    _run_status_in_container() {
      printf "status:%s:%s:%s:%s\n" "$1" "$STEAM_USERNAME" "$STEAM_PASSWORD" "$STEAM_SHARED_SECRET"
    }
    _prompt_steam_guard_code() { echo "unexpected-guard-prompt"; return 1; }
    run_in_container() { echo "unexpected-run"; }
    execute_rcon_command -status demo
  '

  assert_success
  assert_output --partial "Processing -status command on demo..."
  assert_output --partial "status:demo:steam_user:steam_pass:"
  refute_output --partial "unexpected-guard-prompt"
  refute_output --partial "unexpected-run"
}

@test "execute_rcon_command resolves Steam credentials once for status -all" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-status-all" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    calls_file="$BATS_TEST_TMPDIR/ensure_calls"
    : > "$calls_file"
    list_running_instances() { echo "alpha beta"; }
    validate_instance() { return 0; }
    _rcon_status_ready() { return 0; }
    ensure_steam_credentials() {
      local count=0
      if [ -s "$calls_file" ]; then
        count=$(cat "$calls_file")
      fi
      count=$((count + 1))
      echo "$count" > "$calls_file"
      STEAM_USERNAME="steam_user"
      STEAM_PASSWORD="steam_pass"
      STEAM_SHARED_SECRET="steam_secret"
    }
    _run_status_in_container() {
      printf "status:%s:%s\n" "$1" "$STEAM_USERNAME"
    }
    execute_rcon_command -status -all
    printf "ensure_calls=%s\n" "$(cat "$calls_file")"
  '

  assert_success
  assert_output --partial "status:alpha:steam_user"
  assert_output --partial "status:beta:steam_user"
  assert_output --partial "ensure_calls=1"
}

@test "execute_rcon_command prompts for Steam Guard only after status requires it" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-status-guard" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    validate_instance() { return 0; }
    _rcon_status_ready() { return 0; }
    ensure_steam_credentials() {
      STEAM_USERNAME="steam_user"
      STEAM_PASSWORD="steam_pass"
      STEAM_SHARED_SECRET=""
    }
    _run_status_in_container() {
      if [ -z "${STEAM_GUARD_CODE:-}" ]; then
        printf "Displaying server status...\nSTEAM_GUARD_REQUIRED:mobile authenticator\nError: Failed to get Steam session ticket.\n"
        return 1
      fi
      printf "status:%s:%s\n" "$1" "$STEAM_GUARD_CODE"
    }
    _prompt_steam_guard_code() {
      printf "prompted:%s\n" "$1"
      STEAM_GUARD_CODE="54321"
    }
    execute_rcon_command -status demo
  '

  assert_success
  assert_output --partial "Processing -status command on demo..."
  assert_output --partial "Displaying server status..."
  assert_output --partial "Error: Failed to get Steam session ticket."
  assert_output --partial "prompted:demo"
  assert_output --partial "status:demo:54321"
}

@test "execute_rcon_command reuses prompted Steam Guard code for status -all" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-status-all-guard" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    prompt_calls_file="$BATS_TEST_TMPDIR/prompt_calls"
    : > "$prompt_calls_file"
    list_running_instances() { echo "alpha beta"; }
    validate_instance() { return 0; }
    _rcon_status_ready() { return 0; }
    ensure_steam_credentials() {
      STEAM_USERNAME="steam_user"
      STEAM_PASSWORD="steam_pass"
      STEAM_SHARED_SECRET=""
    }
    _run_status_in_container() {
      if [ "$1" = "alpha" ] && [ -z "${STEAM_GUARD_CODE:-}" ]; then
        printf "STEAM_GUARD_REQUIRED:mobile authenticator\n"
        return 1
      fi
      printf "status:%s:%s\n" "$1" "${STEAM_GUARD_CODE:-none}"
    }
    _prompt_steam_guard_code() {
      local count=0
      if [ -s "$prompt_calls_file" ]; then
        count=$(cat "$prompt_calls_file")
      fi
      count=$((count + 1))
      echo "$count" > "$prompt_calls_file"
      STEAM_GUARD_CODE="54321"
    }
    execute_rcon_command -status -all
    printf "prompt_calls=%s\n" "$(cat "$prompt_calls_file")"
  '

  assert_success
  assert_output --partial "status:alpha:54321"
  assert_output --partial "status:beta:54321"
  assert_output --partial "prompt_calls=1"
}

@test "execute_rcon_command skips Steam credential resolution when status target is not ready" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-status-no-creds" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    validate_instance() { return 0; }
    docker() {
      if [[ "$*" == *"/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"* ]]; then
        return 1
      fi
      if [[ "$*" == *"/home/pok/update.flag"* ]]; then
        return 1
      fi
      return 0
    }
    ensure_steam_credentials() { echo "unexpected-creds"; }
    _run_status_in_container() { echo "unexpected-status"; }
    execute_rcon_command -status demo
  '

  assert_success
  assert_output --partial "Instance demo has not fully started yet. Please wait a few minutes before checking the status."
  refute_output --partial "unexpected-creds"
  refute_output --partial "unexpected-status"
}

@test "execute_rcon_command rejects custom commands that start with a dash" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rcon-custom" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    execute_rcon_command -custom demo -SaveWorld
  '

  assert_failure
  assert_output --partial "Error: RCON command should not start with a dash."
  assert_output --partial "Usage: ./POK-manager.sh -custom <RCON command> <instance_name|-all>"
}
