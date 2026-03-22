#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "_stop_instance_resolve_compose_context discovers renamed compose files and container names" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-resolve" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-other.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    container_name: "asa_other_custom"
    environment:
      - INSTANCE_NAME=other
EOF
    source "$REPO_ROOT/POK-manager.sh"
    docker_compose_file="$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
    container_name="asa_demo"
    found_instance_name=""
    _stop_instance_resolve_compose_context demo "$BASE_DIR/Instance_demo" docker_compose_file container_name found_instance_name
    printf "compose=%s\n" "$(basename "$docker_compose_file")"
    printf "container=%s\n" "$container_name"
    printf "found=%s\n" "$found_instance_name"
  '

  assert_success
  assert_output --partial "compose=docker-compose-other.yaml"
  assert_output --partial "container=asa_other_custom"
  assert_output --partial "found=other"
}

@test "stop_instance uses fallback instance lookup and compose down when a folder was renamed" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-renamed" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-other.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    container_name: "asa_other_custom"
    environment:
      - INSTANCE_NAME=other
      - SAVE_WAIT_SECONDS=9
EOF
    source "$REPO_ROOT/POK-manager.sh"
    DOCKER_COMPOSE_CMD=compose_cmd
    get_docker_sudo_preference() { echo false; }
    get_instance_container_id() {
      if [ "$1" = "other" ]; then
        echo "container-123"
      fi
    }
    _instance_quick_save_policy() { echo "attempt|ok: server ready and responding to rcon"; }
    timeout() { shift; "$@"; }
    sleep() { :; }
    compose_cmd() { echo "compose:$*"; }
    docker() { echo "docker:$*"; }
    stop_instance demo
  '

  assert_success
  assert_output --partial "Using the found docker-compose file"
  assert_output --partial "Using container name from docker-compose file: asa_other_custom"
  assert_output --partial "Found running container for 'other' instead of 'demo'"
  assert_output --partial "Save command sent successfully"
  assert_output --partial "Waiting up to 9 seconds for save to complete..."
  assert_output --partial "compose:-f $BATS_TEST_TMPDIR/stop-renamed/Instance_demo/docker-compose-other.yaml down"
  assert_output --partial "Instance demo stopped successfully."
}

@test "stop_all_instances waits once using the longest configured save wait and skips duplicate saves" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-all-save-wait" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
    cat > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=alpha
      - SAVE_WAIT_SECONDS=7
EOF
    cat > "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=beta
      - SAVE_WAIT_SECONDS=3
EOF
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { echo "alpha beta"; }
    _instance_quick_save_policy() { echo "attempt|ok: server ready and responding to rcon"; }
    timeout() { shift; "$@"; }
    docker() { echo "docker:$*"; }
    _save_completion_logged_since() { return 0; }
    sleep() { :; }
    stop_instance() { echo "stop:$1:$2"; }
    stop_all_instances
  '

  assert_success
  assert_output --partial "Attempting quick saves on all running instances..."
  assert_output --partial "Save command sent successfully to alpha"
  assert_output --partial "Save command sent successfully to beta"
  assert_output --partial "Waiting 7 seconds for save operations to complete..."
  assert_output --partial "stop:alpha:skip_save"
  assert_output --partial "stop:beta:skip_save"
}

@test "stop_all_instances skips save dispatch when servers have not reached startup yet" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-all-no-startup" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
    cat > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=alpha
      - SAVE_WAIT_SECONDS=7
EOF
    cat > "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=beta
      - SAVE_WAIT_SECONDS=3
EOF
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { echo "alpha beta"; }
    _instance_quick_save_policy() { echo "skip|Skipping quick save for $1; server health is starting."; }
    stop_instance() { echo "stop:$1:$2"; }
    stop_all_instances
  '

  assert_success
  assert_output --partial "Skipping quick save for alpha; server health is starting."
  assert_output --partial "Skipping quick save for beta; server health is starting."
  assert_output --partial "No instances are save-ready for a quick save. Proceeding with stop."
  refute_output --partial "Waiting "
  assert_output --partial "stop:alpha:skip_save"
  assert_output --partial "stop:beta:skip_save"
}

@test "_save_completion_logged_since only matches new ShooterGame.log entries after the checkpoint" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/save-log-check" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo/Saved/Logs"
    cat > "$BASE_DIR/Instance_demo/Saved/Logs/ShooterGame.log" <<'"'"'EOF'"'"'
old line
World Save Complete. Took: 0.11
EOF
    source "$REPO_ROOT/POK-manager.sh"
    checkpoint=$(_instance_save_log_line_count demo)
    cat >> "$BASE_DIR/Instance_demo/Saved/Logs/ShooterGame.log" <<'"'"'EOF'"'"'
new line
World Save Complete. Took: 0.22
EOF
    if _save_completion_logged_since demo "$checkpoint"; then
      echo "detected=yes"
    else
      echo "detected=no"
    fi
  '

  assert_success
  assert_output --partial "detected=yes"
}

@test "_sanitize_save_wait_seconds bounds invalid compose values safely" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/save-wait-sanitize" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    printf "missing=%s\n" "$(_sanitize_save_wait_seconds "" demo)"
    printf "nonnumeric=%s\n" "$(_sanitize_save_wait_seconds "abc" demo)"
    printf "low=%s\n" "$(_sanitize_save_wait_seconds "0" demo)"
    printf "high=%s\n" "$(_sanitize_save_wait_seconds "90" demo)"
  '

  assert_success
  assert_output --partial "missing=5"
  assert_output --partial "nonnumeric=5"
  assert_output --partial "low=1"
  assert_output --partial "high=60"
}

@test "_stop_instance_stop_without_sudo falls back to sudo on compose permission errors" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-sudo-fallback" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver: {}
EOF
    source "$REPO_ROOT/POK-manager.sh"
    DOCKER_COMPOSE_CMD=compose_cmd
    compose_cmd() {
      echo "permission denied"
      return 1
    }
    sudo() {
      echo "sudo:$*"
      return 0
    }
    _stop_instance_stop_without_sudo "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" asa_demo
  '

  assert_success
  assert_output --partial "Permission denied error occurred. Falling back to sudo..."
  assert_output --partial "sudo:compose_cmd -f $BATS_TEST_TMPDIR/stop-sudo-fallback/Instance_demo/docker-compose-demo.yaml down"
}

@test "stop_instance skip_save bypasses the quick save helper" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-skip-save" POK_MANAGER_TEST_MODE=1 bash -lc '
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
    get_instance_container_id() { echo "container-123"; }
    _stop_instance_attempt_quick_save() { echo "unexpected-save"; }
    _stop_instance_stop_container() { echo "stopped:$1:$2"; }
    stop_instance demo skip_save
  '

  assert_success
  refute_output --partial "unexpected-save"
  assert_output --partial "stopped:$BATS_TEST_TMPDIR/stop-skip-save/Instance_demo/docker-compose-demo.yaml:asa_demo"
}

@test "stop_instance skips quick save when startup is not complete yet" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-not-ready" POK_MANAGER_TEST_MODE=1 bash -lc '
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
    get_instance_container_id() { echo "container-123"; }
    _instance_quick_save_policy() { echo "skip|Skipping quick save for demo; server health is starting."; }
    _dispatch_quick_save_command() { echo "unexpected-dispatch"; }
    _stop_instance_stop_container() { echo "stopped:$1:$2"; }
    stop_instance demo
  '

  assert_success
  assert_output --partial "Skipping quick save for demo; server health is starting."
  refute_output --partial "unexpected-dispatch"
  assert_output --partial "stopped:$BATS_TEST_TMPDIR/stop-not-ready/Instance_demo/docker-compose-demo.yaml:asa_demo"
}

@test "_instance_quick_save_policy skips save when health is ok but RCON is disabled" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-rcon-disabled" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _instance_stop_health_probe() { echo "ok|ok: server ready (rcon disabled)"; }
    _compose_rcon_enabled() { return 1; }
    printf "%s\n" "$(_instance_quick_save_policy demo asa_demo "$BASE_DIR/Instance_demo/docker-compose-demo.yaml")"
  '

  assert_success
  assert_output --partial "skip|Skipping quick save for demo; server health is ok but RCON is disabled."
}

@test "_instance_quick_save_policy attempts save when health is degraded" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stop-degraded" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _instance_stop_health_probe() { echo "degraded|degraded: rcon connection failed"; }
    printf "%s\n" "$(_instance_quick_save_policy demo asa_demo "$BASE_DIR/Instance_demo/docker-compose-demo.yaml")"
  '

  assert_success
  assert_output --partial "attempt|Instance demo is degraded; attempting quick save anyway before stop."
}
