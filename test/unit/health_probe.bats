#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "health_probe.sh can be sourced without executing the probe" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    printf "main=%s\n" "$(type -t health_probe_main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "health_probe_main returns healthy in update mode" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    UPDATE_MODE=TRUE
    RCON_ENABLED=FALSE
    health_probe_main
  '

  assert_success
  assert_output --partial "ok: update mode"
}

@test "health_probe_main returns starting until the startup marker exists" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    is_process_running() { return 0; }
    set +e
    health_probe_main
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "starting: startup marker not reached"
  assert_output --partial "status=1"
}

@test "health_probe_main returns starting while a follower is waiting for the coordination master" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    update_coordination_is_waiting() { return 0; }
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    set +e
    health_probe_main
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "starting: waiting for coordination master"
  assert_output --partial "status=1"
}

@test "health_probe_main reports the AsaApi cache wait state" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    API=TRUE
    UPDATE_MODE=FALSE
    ASAAPI_WAIT_MARKER="$BATS_TEST_TMPDIR/asaapi-waiting"
    printf "%s\n" "starting: waiting for AsaApi cache" > "$ASAAPI_WAIT_MARKER"
    set +e
    health_probe_main
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "starting: waiting for AsaApi cache"
  assert_output --partial "status=1"
}

@test "health_probe_main waits for the managed AsaApi success marker" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    API=TRUE
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    ASAAPI_STATE_DIR="$ASA_DIR/.pok-manager/asaapi"
    ASAAPI_WAIT_MARKER="$BATS_TEST_TMPDIR/no-wait-marker"
    ASAAPI_LAUNCH_MARKER="$BATS_TEST_TMPDIR/asaapi-launch-started"
    mkdir -p "$ASAAPI_STATE_DIR" "$ASA_DIR/ShooterGame/Saved/Logs" "$ASA_DIR/ShooterGame/Binaries/Win64/logs"
    printf "%s\n" "{\"source\":\"managed\",\"version\":\"2.01\"}" > "$ASAAPI_STATE_DIR/source.json"
    printf "%s\n" "Server has completed startup and is now advertising for join." > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    touch "$ASAAPI_LAUNCH_MARKER"
    printf "%s\n" "Loading..." > "$ASA_DIR/ShooterGame/Binaries/Win64/logs/AsaApi.log"
    is_process_running() { return 0; }
    health_probe_startup_timed_out() { return 1; }
    set +e
    health_probe_main
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "starting: waiting for AsaApi to confirm successful loading"
  assert_output --partial "status=1"
}

@test "health_probe_main accepts the managed AsaApi success marker" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    API=TRUE
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    ASAAPI_STATE_DIR="$ASA_DIR/.pok-manager/asaapi"
    ASAAPI_WAIT_MARKER="$BATS_TEST_TMPDIR/no-wait-marker"
    ASAAPI_LAUNCH_MARKER="$BATS_TEST_TMPDIR/asaapi-launch-started"
    mkdir -p "$ASAAPI_STATE_DIR" "$ASA_DIR/ShooterGame/Saved/Logs" "$ASA_DIR/ShooterGame/Binaries/Win64/logs"
    printf "%s\n" "{\"source\":\"managed\",\"version\":\"2.01\"}" > "$ASAAPI_STATE_DIR/source.json"
    printf "%s\n" "Server has completed startup and is now advertising for join." > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    touch "$ASAAPI_LAUNCH_MARKER"
    printf "%s\n" "API was successfully loaded" > "$ASA_DIR/ShooterGame/Binaries/Win64/logs/AsaApi.log"
    is_process_running() { return 0; }
    health_probe_main
  '

  assert_success
  assert_output --partial "ok: server ready (rcon disabled)"
}

@test "health_probe_main rejects an AsaApi success marker from a previous launch" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    API=TRUE
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    ASAAPI_STATE_DIR="$ASA_DIR/.pok-manager/asaapi"
    ASAAPI_WAIT_MARKER="$BATS_TEST_TMPDIR/no-wait-marker"
    ASAAPI_LAUNCH_MARKER="$BATS_TEST_TMPDIR/asaapi-launch-started"
    mkdir -p "$ASAAPI_STATE_DIR" "$ASA_DIR/ShooterGame/Saved/Logs" "$ASA_DIR/ShooterGame/Binaries/Win64/logs"
    printf "%s\n" "{\"source\":\"managed\",\"version\":\"2.01\"}" > "$ASAAPI_STATE_DIR/source.json"
    printf "%s\n" "Server has completed startup and is now advertising for join." > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    printf "%s\n" "API was successfully loaded" > "$ASA_DIR/ShooterGame/Binaries/Win64/logs/AsaApi.log"
    touch -d "2 seconds ago" "$ASA_DIR/ShooterGame/Binaries/Win64/logs/AsaApi.log"
    touch "$ASAAPI_LAUNCH_MARKER"
    is_process_running() { return 0; }
    health_probe_startup_timed_out() { return 1; }
    set +e
    health_probe_main
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "starting: waiting for AsaApi to confirm successful loading"
  assert_output --partial "status=1"
}

@test "health_probe_main returns unhealthy when startup takes too long without the startup marker" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    PID_FILE="$BATS_TEST_TMPDIR/server.pid"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    is_process_running() { return 0; }
    health_probe_server_pid() { echo 4321; }
    ps() {
      if [ "$1" = "-o" ] && [ "$2" = "etimes=" ] && [ "$3" = "-p" ] && [ "$4" = "4321" ]; then
        echo "901"
        return 0
      fi
      return 1
    }
    set +e
    health_probe_main
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "unhealthy: startup marker timed out"
  assert_output --partial "status=1"
}

@test "health_probe_main returns healthy when startup marker exists and rcon is disabled" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    printf "%s\n" "Server has completed startup and is now advertising for join." > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    is_process_running() { return 0; }
    health_probe_main
  '

  assert_success
  assert_output --partial "ok: server ready (rcon disabled)"
}

@test "health_probe_main keeps Full Startup without advertising in starting state" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    printf "%s\n" "Full Startup: 59.50 seconds" > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    UPDATE_MODE=FALSE
    RCON_ENABLED=FALSE
    is_process_running() { return 0; }
    set +e
    health_probe_main
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "starting: startup marker not reached"
  assert_output --partial "status=1"
}

@test "health_probe_main returns degraded when the rcon probe fails after startup" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    printf "%s\n" "Server has completed startup and is now advertising for join." > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    UPDATE_MODE=FALSE
    RCON_ENABLED=TRUE
    is_process_running() { return 0; }
    health_probe_run_rcon_command() {
      echo "Failed to connect"
      return 1
    }
    health_probe_main
  '

  assert_success
  assert_output --partial "degraded: rcon connection failed"
}

@test "health_probe_main returns healthy when the rcon probe succeeds" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/health_probe.sh"
    prepare_runtime_env() { :; }
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    printf "%s\n" "Server has completed startup and is now advertising for join." > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    UPDATE_MODE=FALSE
    RCON_ENABLED=TRUE
    is_process_running() { return 0; }
    health_probe_run_rcon_command() {
      echo "No Players Connected"
      return 0
    }
    health_probe_main
  '

  assert_success
  assert_output --partial "ok: server ready and responding to rcon"
}
