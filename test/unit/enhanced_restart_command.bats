#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "_countdown_build_notification_points keeps five-minute and final countdown checkpoints" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/restart-points" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _countdown_build_notification_points 6
    printf "points=%s\n" "${_RESTART_NOTIFICATION_POINTS[*]}"
  '

  assert_success
  assert_output --partial "points=300 180 60 30 10 9 8 7 6 5 4 3 2 1"
}

@test "enhanced_restart_command returns an error when all-instance restart has no running servers" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/restart-empty" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { :; }
    set +e
    enhanced_restart_command 0 -all
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "No running instances found."
  assert_output --partial "status=1"
}

@test "enhanced_restart_command skips server updates for single-instance restarts" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/restart-single" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<EOF
services:
  asaserver:
    environment:
      - API=FALSE
EOF
    source "$REPO_ROOT/POK-manager.sh"
    docker() { return 0; }
    sleep() { :; }
    run_in_container_background() { :; }
    run_in_container() { echo "save:$1:$2"; }
    stop_instance() { echo "stop:$1"; }
    start_instance() { echo "start:$1"; }
    update_server_files_and_docker() { echo "unexpected-update"; }
    enhanced_restart_command 0 demo
  '

  assert_success
  assert_output --partial "Restarting specific instance: Updates will be skipped to minimize downtime"
  assert_output --partial "Processing instance for restart: demo"
  assert_output --partial "Skipping server updates as a specific instance was selected"
  assert_output --partial "save:demo:-saveworld"
  assert_output --partial "stop:demo"
  assert_output --partial "start:demo"
  refute_output --partial "unexpected-update"
}

@test "enhanced_restart_command keeps coordinated mixed-mode restarts for all instances" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/restart-mixed" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
    cat > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" <<EOF
services:
  asaserver:
    environment:
      - API=TRUE
EOF
    cat > "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" <<EOF
services:
  asaserver:
    environment:
      - API=FALSE
EOF
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { echo "alpha beta"; }
    docker() { return 0; }
    sleep() { :; }
    run_in_container_background() { :; }
    run_in_container() { echo "save:$1:$2"; }
    stop_instance() { echo "stop:$1"; }
    _coordination_start_instance_subset() { echo "coord-start:$1:$2:${*:3}"; }
    update_server_files_and_docker() { echo "updated-server-files"; }
    enhanced_restart_command 0 -all
  '

  assert_success
  assert_output --partial "Processing all running instances for restart: alpha beta"
  assert_output --partial "⚠️ Mixed API modes detected. Using coordinated restart approach for all instances."
  assert_output --partial "updated-server-files"
  assert_output --partial "save:alpha:-saveworld"
  assert_output --partial "save:beta:-saveworld"
  assert_output --partial "stop:alpha"
  assert_output --partial "stop:beta"
  assert_output --partial "coord-start:coordinated_all:coordinated_all:alpha beta"
}

@test "enhanced_shutdown_command uses the shared countdown renderer and shared save wait helper" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/shutdown-shared-countdown" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { echo "alpha beta"; }
    run_in_container_background() { echo "chat:$1:$2:$3"; }
    stop_instance() { echo "stop:$1:$2"; }
    sleep() { :; }
    _run_enhanced_countdown() { echo "shared-countdown:$1:$2:$3:$4"; }
    _save_instances_then_wait() { echo "savewait:$1:$2:${*:3}"; }
    enhanced_shutdown_command 0 -all
  '

  assert_success
  assert_output --partial "Processing all running instances for shutdown: alpha beta"
  assert_output --partial "shared-countdown:0:Shutting down:_shutdown_countdown_notify:🛑 Beginning coordinated shutdown process..."
  assert_output --partial "savewait:Attempting quick saves on all running instances..."
  assert_output --partial "stop:alpha:skip_save"
  assert_output --partial "stop:beta:skip_save"
}
