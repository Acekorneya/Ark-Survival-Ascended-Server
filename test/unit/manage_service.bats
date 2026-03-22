#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "manage_service routes -start -all through perform_action_on_all_instances" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-start-all" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    adjust_docker_permissions() { echo "docker-adjusted"; }
    perform_action_on_all_instances() { echo "all:$1"; }
    start_instance() { echo "unexpected-start:$1"; }
    manage_service -start -all
  '

  assert_success
  assert_output --partial "docker-adjusted"
  assert_output --partial "all:-start"
  refute_output --partial "unexpected-start"
}

@test "manage_service promotes an explicitly started instance before dispatching start_instance" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-start-one" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    adjust_docker_permissions() { echo "docker-adjusted"; }
    start_instance() { echo "start:$1:$2:$3"; }
    manage_service -start demo
  '

  assert_success
  assert_output --partial "docker-adjusted"
  assert_output --partial "start:demo:promote_single:"
}

@test "manage_service runs setup precheck before delegating to setup handler" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-setup" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    PUID=7777
    PGID=7777
    get_docker_compose_cmd() { :; }
    check_puid_pgid_user() { echo "checked:$1:$2"; }
    _manage_service_handle_setup() { echo "setup-handler"; }
    manage_service -setup
  '

  assert_success
  assert_output --partial "checked:7777:7777"
  assert_output --partial "setup-handler"
}

@test "manage_service defaults backup to all instances when no target is provided" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-backup" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    adjust_docker_permissions() { :; }
    backup_instance() { echo "backup:$1"; }
    manage_service -backup
  '

  assert_success
  assert_output --partial "Defaulting to backing up all instances."
  assert_output --partial "backup:-all"
}

@test "manage_service passes live log arguments through the logs handler" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-logs" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    adjust_docker_permissions() { echo "docker-adjusted"; }
    _manage_service_handle_logs() { echo "logs:$1:$2"; }
    manage_service -logs -live demo
  '

  assert_success
  assert_output --partial "docker-adjusted"
  assert_output --partial "logs:-live:demo"
}

@test "manage_service prompts for a running instance when -logs targets -all" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-logs-all" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    adjust_docker_permissions() { :; }
    list_running_instances() { echo "POK_WORD"; }
    display_logs() { echo "logs:$1:$2"; }
    _manage_service_handle_logs -all "" <<< $'"'"'1\n'"'"'
  '

  assert_success
  assert_output --partial "Available running instances:"
  assert_output --partial "1. POK_WORD"
  assert_output --partial "logs:POK_WORD:"
  refute_output --partial "logs:Available running instances:"
}

@test "manage_service routes delete through the delete handler" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-delete" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    adjust_docker_permissions() { echo "docker-adjusted"; }
    _manage_service_handle_delete() { echo "delete:$1"; }
    manage_service -delete demo
  '

  assert_success
  assert_output --partial "docker-adjusted"
  assert_output --partial "delete:demo"
}

@test "_coordination_start_all_instances starts the persisted master before followers" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-start-ordered" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta" "$BASE_DIR/Instance_gamma"
    cat > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=alpha
      - TZ=UTC
      - UPDATE_SERVER=TRUE
      - UPDATE_COORDINATION_ROLE=MASTER
      - UPDATE_COORDINATION_PRIORITY=1
EOF
    cat > "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=beta
      - TZ=UTC
      - UPDATE_SERVER=TRUE
      - UPDATE_COORDINATION_ROLE=FOLLOWER
      - UPDATE_COORDINATION_PRIORITY=2
EOF
    cat > "$BASE_DIR/Instance_gamma/docker-compose-gamma.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=gamma
      - TZ=UTC
      - UPDATE_SERVER=FALSE
EOF
    source "$REPO_ROOT/POK-manager.sh"
    start_instance() { echo "start:$1:$2:$3"; }
    _coordination_wait_for_instance_ready() { echo "wait:$1"; }
    _coordination_start_all_instances
  '

  assert_success
  assert_line --index 0 "Coordinated startup in progress. Waiting for leader readiness before starting followers."
  assert_line --index 1 "Performing '-start' on coordination leader first: alpha"
  assert_line --index 2 "start:alpha:preserve:coordinated_all"
  assert_line --index 3 "wait:alpha"
  assert_line --index 4 "Performing '-start' on instance: beta"
  assert_line --index 5 "start:beta:preserve:coordinated_all"
  assert_line --index 6 "Performing '-start' on instance: gamma"
  assert_line --index 7 "start:gamma:preserve:coordinated_all"
  assert_line --index 8 "All coordinated instances have started. You can now use ./POK-manager.sh -logs -live <instance_name> or ./POK-manager.sh -status <instance_name|-all>."
}

@test "_coordination_start_instance_subset promotes an eligible restart instance when the persisted master is outside the subset" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-start-subset" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta" "$BASE_DIR/Instance_gamma"
    cat > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=alpha
      - TZ=UTC
      - UPDATE_SERVER=TRUE
      - UPDATE_COORDINATION_ROLE=MASTER
      - UPDATE_COORDINATION_PRIORITY=1
EOF
    cat > "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=beta
      - TZ=UTC
      - UPDATE_SERVER=TRUE
      - UPDATE_COORDINATION_ROLE=FOLLOWER
      - UPDATE_COORDINATION_PRIORITY=2
EOF
    cat > "$BASE_DIR/Instance_gamma/docker-compose-gamma.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=gamma
      - TZ=UTC
      - UPDATE_SERVER=TRUE
      - UPDATE_COORDINATION_ROLE=FOLLOWER
      - UPDATE_COORDINATION_PRIORITY=3
EOF
    source "$REPO_ROOT/POK-manager.sh"
    start_instance() { echo "start:$1:$2:$3"; }
    _coordination_wait_for_instance_ready() { echo "wait:$1"; }
    _coordination_start_instance_subset coordinated_all coordinated_all beta gamma
    echo "beta-role=$(grep UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" | head -1 | sed "s/.*=//")"
  '

  assert_success
  assert_line --index 0 "Coordinated startup in progress. Waiting for leader readiness before starting followers."
  assert_line --index 1 "Performing '-start' on coordination leader first: beta"
  assert_line --index 2 "start:beta:preserve:coordinated_all"
  assert_line --index 3 "wait:beta"
  assert_line --index 4 "Performing '-start' on instance: gamma"
  assert_line --index 5 "start:gamma:preserve:coordinated_all"
  assert_output --partial "beta-role=MASTER"
}

@test "manage_service passes API toggle values through the API handler" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-api" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    _manage_service_handle_api() { echo "api:$1:$2"; }
    manage_service -API TRUE demo
  '

  assert_success
  assert_output --partial "api:TRUE:demo"
}

@test "manage_service routes rename through the rename handler" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/manage-rename" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    _manage_service_handle_rename() { echo "rename:$1"; }
    manage_service -rename demo
  '

  assert_success
  assert_output --partial "rename:demo"
}
