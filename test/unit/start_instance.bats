#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "_start_instance_validate_compose_consistency auto-fixes mismatched compose names" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/start-consistency" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    exec </dev/null
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-wrong.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    container_name: "asa_wrong"
    environment:
      - INSTANCE_NAME=wrong
    volumes:
      - "/tmp/Instance_wrong/Saved:/home/pok/arkserver/ShooterGame/Saved"
      - "/tmp/Instance_wrong/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs"
EOF
    source "$REPO_ROOT/POK-manager.sh"
    _start_instance_apply_owner() { :; }
    instance_name="demo"
    instance_dir="$BASE_DIR/Instance_demo"
    docker_compose_file="$instance_dir/docker-compose-wrong.yaml"
    _start_instance_validate_compose_consistency instance_name "$instance_dir" docker_compose_file
    printf "compose=%s\n" "$(basename "$docker_compose_file")"
    printf "container=%s\n" "$(_compose_container_instance_name "$docker_compose_file")"
    printf "env=%s\n" "$(_compose_env_instance_name "$docker_compose_file")"
    cat "$docker_compose_file"
  '

  assert_success
  assert_output --partial "compose=docker-compose-demo.yaml"
  assert_output --partial "container=demo"
  assert_output --partial "env=demo"
  assert_output --partial "Instance_demo/Saved"
  assert_output --partial "Instance_demo/API_Logs"
}

@test "_start_instance_sync_api_logs_volume adds absolute API_Logs mapping when API is enabled" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/start-api-add" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo/Saved"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<EOF
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
      - API=TRUE
    volumes:
      - "$BASE_DIR/Instance_demo/Saved:/home/pok/arkserver/ShooterGame/Saved"
EOF
    source "$REPO_ROOT/POK-manager.sh"
    _start_instance_apply_owner() { :; }
    _start_instance_sync_api_logs_volume demo "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" 2_1_latest
    printf "logs_dir=%s\n" "$([ -d "$BASE_DIR/Instance_demo/API_Logs" ] && echo present || echo missing)"
    cat "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "logs_dir=present"
  assert_output --partial "$BATS_TEST_TMPDIR/start-api-add/Instance_demo/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs"
}

@test "_start_instance_sync_api_logs_volume removes API_Logs mapping when API is disabled" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/start-api-remove" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo/Saved" "$BASE_DIR/Instance_demo/API_Logs"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<EOF
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
      - API=FALSE
    volumes:
      - "$BASE_DIR/Instance_demo/Saved:/home/pok/arkserver/ShooterGame/Saved"
      - "$BASE_DIR/Instance_demo/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs"
EOF
    source "$REPO_ROOT/POK-manager.sh"
    _start_instance_apply_owner() { :; }
    _start_instance_sync_api_logs_volume demo "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" 2_1_latest
    if grep -q "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"; then
      echo "mapping=present"
    else
      echo "mapping=removed"
    fi
  '

  assert_success
  assert_output --partial "mapping=removed"
}

@test "start_instance repairs a renamed compose file before later validation steps" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/start-rename" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-other.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    container_name: "asa_other"
    environment:
      - INSTANCE_NAME=other
    volumes:
      - "/tmp/Instance_other/Saved:/home/pok/arkserver/ShooterGame/Saved"
EOF
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_image_tag() { echo "2_1_latest"; }
    check_volume_paths() { :; }
    ensure_volume_mount_directories() { return 1; }
    _start_instance_apply_owner() { :; }
    set +e
    start_instance demo <<< $'"'"'1\n'"'"'
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "compose=%s\n" "$(basename "$(echo "$BASE_DIR"/Instance_demo/docker-compose-*.yaml)")"
    cat "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "compose=docker-compose-demo.yaml"
  assert_output --partial "container_name: \"asa_demo\""
  assert_output --partial "INSTANCE_NAME=demo"
  assert_output --partial "Instance_demo/Saved"
}

@test "_coordination_wait_status_text formats plain progress updates for non-interactive waits" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/start-wait-text" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _coordination_wait_status_text demo leader_starting 75
  '

  assert_success
  assert_output "Waiting for coordination leader 'demo' (phase: leader_starting, elapsed: 1m 15s)"
}

@test "_start_instance_launch_container suppresses the per-instance log hint during coordinated all-start" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/start-launch-hint" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
EOF
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { DOCKER_COMPOSE_CMD="docker compose"; }
    get_docker_sudo_preference() { echo false; }
    check_vm_max_map_count() { :; }
    docker() { echo "docker:$*"; return 0; }
    _start_instance_launch_container demo "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" 2_1_latest coordinated_all
  '

  assert_success
  assert_output --partial "✅ Server demo started successfully with image tag 2_1_latest."
  refute_output --partial "You can view logs while container is running with: ./POK-manager.sh -logs -live demo"
}
