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
