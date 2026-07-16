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

@test "stop_instance uses two verified stages and derived compose timeout when a folder was renamed" {
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
    _instance_has_running_server_process() { return 0; }
    _run_parallel_shutdown_stage() { echo "stage:$1:$2:${*:3}"; return 0; }
    _wait_for_shutdown_server_processes() { return 0; }
    compose_cmd() { echo "compose:$*"; }
    docker() { echo "docker:$*"; }
    stop_instance demo
  '

  assert_success
  assert_output --partial "Using the found docker-compose file"
  assert_output --partial "Using container name from docker-compose file: asa_other_custom"
  assert_output --partial "Found running container for 'other' instead of 'demo'"
  assert_output --partial "stage:-verify-save"
  assert_output --partial "stage:-verify-doexit"
  assert_output --partial "compose:-f $BATS_TEST_TMPDIR/stop-renamed/Instance_demo/docker-compose-other.yaml down -t 108"
  assert_output --partial "Instance demo stopped successfully."
}

@test "stop_all_instances runs both save barriers once for all instances" {
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
    _instance_has_running_server_process() { return 0; }
    _run_parallel_shutdown_stage() { echo "stage:$1:${*:3}"; return 0; }
    _wait_for_shutdown_server_processes() { return 0; }
    stop_instance() { echo "stop:$1:$2"; }
    stop_all_instances
  '

  assert_success
  assert_output --partial "stage:-verify-save:alpha beta"
  assert_output --partial "stage:-verify-doexit:alpha beta"
  assert_output --partial "stop:alpha:skip_save"
  assert_output --partial "stop:beta:skip_save"
}

@test "stop_all_instances skips save barriers when no ASA processes are running" {
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
    _instance_has_running_server_process() { return 1; }
    _run_parallel_shutdown_stage() { echo "unexpected-stage"; return 1; }
    stop_instance() { echo "stop:$1:$2"; }
    stop_all_instances
  '

  assert_success
  assert_output --partial "alpha: no running ASA process; no world save is required."
  assert_output --partial "beta: no running ASA process; no world save is required."
  refute_output --partial "unexpected-stage"
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
  assert_output --partial "missing=60"
  assert_output --partial "nonnumeric=60"
  assert_output --partial "low=1"
  assert_output --partial "high=90"
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

@test "stop_instance removes a container without save stages when ASA is not running" {
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
    _instance_has_running_server_process() { return 1; }
    _run_parallel_shutdown_stage() { echo "unexpected-stage"; }
    _stop_instance_stop_container() { echo "stopped:$1:$2"; }
    stop_instance demo
  '

  assert_success
  assert_output --partial "demo: no running ASA process; no world save is required."
  refute_output --partial "unexpected-stage"
  assert_output --partial "stopped:$BATS_TEST_TMPDIR/stop-not-ready/Instance_demo/docker-compose-demo.yaml:asa_demo"
}

@test "rollback stages before the shared save barrier and restarts only previous instances" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rollback-manager" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
    touch "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml"
    touch "$BASE_DIR/Instance_beta/docker-compose-beta.yaml"
    source "$REPO_ROOT/POK-manager.sh"
    list_instances() { echo "alpha beta"; }
    list_running_instances() { echo "alpha"; }
    ensure_steam_credentials() { echo "credentials:$1:$2"; }
    _prompt_optional_rollback_steam_guard_code() { echo "guard-prompt:$1"; }
    _rollback_compose_run() {
      echo "worker:$1:$2:${3:-}" >&2
      [ "$2" = select ] && echo 681058914540629286
      return 0
    }
    _verified_shutdown_instances() { echo "barrier:$*"; }
    _coordination_start_instance_subset() { echo "restart:$*"; }
    rollback_shared_server_files -all false
  '

  assert_success
  assert_output --partial "credentials:alpha:rollback"
  assert_output --partial "guard-prompt:alpha"
  assert_output --partial "worker:alpha:stage:681058914540629286"
  assert_output --partial "barrier:false alpha"
  assert_output --partial "worker:alpha:activate:681058914540629286"
  assert_output --partial "restart:standard coordinated_subset alpha"
  assert_output --partial "Shared ASA rollback manifest 681058914540629286 is active."
}

@test "named rollback refuses noninteractive shared mutation when multiple instances exist" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/rollback-confirm" POK_MANAGER_TEST_MODE=1 bash -lc '
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
    touch "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml"
    touch "$BASE_DIR/Instance_beta/docker-compose-beta.yaml"
    source "$REPO_ROOT/POK-manager.sh"
    list_instances() { echo "alpha beta"; }
    validate_instance() { return 0; }
    rollback_shared_server_files alpha false
  '

  assert_failure
  assert_output --partial "-rollback -all"
  assert_output --partial "Rollback cancelled."
}

@test "rollback is a valid force-aware manager action" {
  run env REPO_ROOT="$PROJECT_ROOT" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _main_parse_cli_arguments -rollback -all --force
    printf "action=%s target=%s force=%s\n" "$_MAIN_ACTION" "$_MAIN_INSTANCE_NAME" "$_MAIN_FORCE_MODE"
    _main_action_is_valid "$_MAIN_ACTION"
  '

  assert_success
  assert_output --partial "action=-rollback target=-all force=true"
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

@test "two-stage shutdown aborts every container when any Stage 1 save fails" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stage-one-abort" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _instance_has_running_server_process() { return 0; }
    _run_parallel_shutdown_stage() {
      _SHUTDOWN_STAGE_FAILED_INSTANCES=(beta)
      echo "stage:$1:${*:3}"
      [ "$1" != "-verify-save" ]
    }
    _stop_verified_containers_in_parallel() { echo "unexpected-stop"; }
    if _verified_shutdown_instances false alpha beta; then
      echo "result=success"
    else
      echo "result=failed"
    fi
  '

  assert_success
  assert_output --partial "stage:-verify-save:alpha beta"
  assert_output --partial "No DoExit commands were sent and no containers were stopped."
  assert_output --partial "result=failed"
  refute_output --partial "-verify-doexit"
  refute_output --partial "unexpected-stop"
}

@test "two-stage shutdown leaves containers intact when DoExit save verification fails" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/stage-two-abort" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _instance_has_running_server_process() { return 0; }
    _run_parallel_shutdown_stage() {
      echo "stage:$1:${*:3}"
      if [ "$1" = "-verify-doexit" ]; then
        _SHUTDOWN_STAGE_FAILED_INSTANCES=(alpha)
        return 1
      fi
      return 0
    }
    _stop_verified_containers_in_parallel() { echo "unexpected-stop"; }
    if _verified_shutdown_instances false alpha beta; then
      echo "result=success"
    else
      echo "result=failed"
    fi
  '

  assert_success
  assert_output --partial "stage:-verify-doexit:alpha beta"
  assert_output --partial "Containers were left intact"
  assert_output --partial "result=failed"
  refute_output --partial "unexpected-stop"
}

@test "verified shutdown terminates lingering instances after five-second clean-exit window" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/verified-fast-termination" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _instance_has_running_server_process() { return 0; }
    _run_parallel_shutdown_stage() { echo "stage:$1:${*:3}"; return 0; }
    _wait_for_shutdown_server_processes() {
      echo "wait:$1:${*:2}"
      [ "$1" != 5 ]
    }
    _stop_verified_containers_in_parallel() { echo "stopped:$*"; }
    _verified_shutdown_instances false alpha beta
  '

  assert_success
  assert_output --partial "wait:5:alpha beta"
  assert_output --partial "stage:-terminate-verified:alpha beta"
  assert_output --partial "stopped:alpha beta"
  refute_output --partial "wait:55"
}

@test "failed verified termination retains the remaining safety wait" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/verified-termination-fallback" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _instance_has_running_server_process() { return 0; }
    _run_parallel_shutdown_stage() {
      echo "stage:$1:${*:3}"
      [ "$1" != "-terminate-verified" ]
    }
    _wait_for_shutdown_server_processes() { echo "wait:$1:${*:2}"; return 1; }
    _stop_verified_containers_in_parallel() { echo "stopped:$*"; }
    _verified_shutdown_instances false alpha beta
  '

  assert_success
  assert_output --partial "stage:-terminate-verified:alpha beta"
  assert_output --partial "wait:55:alpha beta"
  assert_output --partial "stopped:alpha beta"
}

@test "--force continues through failed verification with a data-loss warning" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/force-stop" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _instance_has_running_server_process() { return 0; }
    _run_parallel_shutdown_stage() {
      _SHUTDOWN_STAGE_FAILED_INSTANCES=(beta)
      echo "stage:$1:${*:3}"
      return 1
    }
    _wait_for_shutdown_server_processes() { return 0; }
    _stop_verified_containers_in_parallel() { echo "stopped:$*"; }
    _verified_shutdown_instances true alpha beta
  '

  assert_success
  assert_output --partial "--force requested"
  assert_output --partial "stopped:alpha beta"
}
