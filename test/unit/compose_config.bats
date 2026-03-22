#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "read_docker_compose_config maps CPU_OPTIMIZATION and SAVE_WAIT_SECONDS into config_values" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/compose-read" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
      - API=FALSE
      - CPU_OPTIMIZATION=TRUE
      - SAVE_WAIT_SECONDS=9
    mem_limit: 12G
EOF
    yq() {
      local expr="$2"
      local file="$3"
      case "$expr" in
        ".services.asaserver.environment[]")
          grep "^      - " "$file" | sed "s/^      - //"
          ;;
        ".services.asaserver.mem_limit")
          awk "/mem_limit:/ { print \$2 }" "$file"
          ;;
      esac
    }
    source "$REPO_ROOT/POK-manager.sh"
    declare -A config_values=()
    read_docker_compose_config demo
    printf "cpu=%s\n" "${config_values["CPU Optimization"]}"
    printf "api=%s\n" "${config_values["API"]}"
    printf "save_wait=%s\n" "${config_values["Save Wait Seconds"]}"
    printf "memory=%s\n" "${config_values["Memory Limit"]}"
  '

  assert_success
  assert_output --partial "cpu=TRUE"
  assert_output --partial "api=FALSE"
  assert_output --partial "save_wait=9"
  assert_output --partial "memory=12G"
}

@test "prompt_for_input validates API and CPU Optimization as booleans" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/prompt-bool" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"

    {
      declare -A config_values=(["API"]="FALSE")
      prompt_for_input "API" <<< $'\''maybe\nTRUE\n'\''
      printf "api=%s\n" "${config_values["API"]}"
    }

    {
      declare -A config_values=(["CPU Optimization"]="FALSE")
      prompt_for_input "CPU Optimization" <<< $'\''nope\nFALSE\n'\''
      printf "cpu=%s\n" "${config_values["CPU Optimization"]}"
    }
  '

  assert_success
  assert_output --partial "api=TRUE"
  assert_output --partial "cpu=FALSE"
}

@test "prompt_for_input validates Save Wait Seconds within the allowed bounds" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/prompt-save-wait" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    declare -A config_values=(["Save Wait Seconds"]="5")
    prompt_for_input "Save Wait Seconds" <<< $'\''90\n0\n12\n'\''
    printf "save_wait=%s\n" "${config_values["Save Wait Seconds"]}"
  '

  assert_success
  assert_output --partial "save_wait=12"
}

@test "_start_instance_sync_save_wait_seconds_env backfills SAVE_WAIT_SECONDS into existing managed compose files" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/save-wait-backfill" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
      - TZ=UTC
      - RESTART_NOTICE_MINUTES=30
EOF
    source "$REPO_ROOT/POK-manager.sh"
    _start_instance_sync_save_wait_seconds_env "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
    grep "SAVE_WAIT_SECONDS" "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "SAVE_WAIT_SECONDS=5"
}

@test "write_docker_compose_file writes SAVE_WAIT_SECONDS from config_values" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/save-wait-write" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    TZ="UTC"
    PUID=7777
    PGID=7777
    chmod() { :; }
    chown() { :; }
    get_docker_image_tag() { echo "2_1_beta"; }
    declare -A config_values=(
      ["Memory Limit"]="16G"
      ["BattleEye"]="FALSE"
      ["API"]="FALSE"
      ["RCON Enabled"]="TRUE"
      ["POK Monitor Message"]="FALSE"
      ["Random Startup Delay"]="TRUE"
      ["CPU Optimization"]="FALSE"
      ["Update Server"]="TRUE"
      ["Update Interval"]="24"
      ["Update Window Start"]="12:00 AM"
      ["Update Window End"]="11:59 PM"
      ["Restart Notice"]="30"
      ["Save Wait Seconds"]="11"
      ["MOTD Enabled"]="FALSE"
      ["MOTD"]=""
      ["MOTD Duration"]="30"
      ["Map Name"]="TheIsland"
      ["Session Name"]="Demo"
      ["Admin Password"]="secret"
      ["Server Password"]=""
      ["ASA Port"]="7777"
      ["RCON Port"]="27020"
      ["Max Players"]="70"
      ["Show Admin Commands In Chat"]="FALSE"
      ["Cluster ID"]="cluster"
      ["Mod IDs"]=""
      ["Passive Mods"]=""
      ["Custom Server Args"]=""
    )
    write_docker_compose_file demo
    grep "SAVE_WAIT_SECONDS" "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "SAVE_WAIT_SECONDS=11"
}

@test "generate_docker_compose loads existing compose values before review" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/generate-existing" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
      - API=FALSE
      - CPU_OPTIMIZATION=TRUE
      - SESSION_NAME=LoadedSession
    mem_limit: 14G
EOF
    yq() {
      local expr="$2"
      local file="$3"
      case "$expr" in
        ".services.asaserver.environment[]")
          grep "^      - " "$file" | sed "s/^      - //"
          ;;
        ".services.asaserver.mem_limit")
          awk "/mem_limit:/ { print \$2 }" "$file"
          ;;
      esac
    }
    source "$REPO_ROOT/POK-manager.sh"
    _init
    check_puid_pgid_user() { :; }
    prompt_for_instance_copy() { echo "copy=not-called"; }
    review_and_modify_configuration() {
      printf "review_cpu=%s\n" "${config_values["CPU Optimization"]}"
      printf "review_session=%s\n" "${config_values["Session Name"]}"
    }
    set_timezone() { :; }
    adjust_ownership_and_permissions() { :; }
    copy_default_configs() { :; }
    write_docker_compose_file() { :; }
    prompt_for_final_edit() { :; }
    generate_docker_compose demo
  '

  assert_success
  refute_output --partial "copy=not-called"
  assert_output --partial "review_cpu=TRUE"
  assert_output --partial "review_session=LoadedSession"
}

@test "normalize_update_coordination_assignments picks the oldest auto-updating instance as master" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/coord-normalize" POK_MANAGER_TEST_MODE=1 bash -lc '
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
EOF
    sleep 1
    cat > "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=beta
      - TZ=UTC
      - UPDATE_SERVER=TRUE
EOF
    cat > "$BASE_DIR/Instance_gamma/docker-compose-gamma.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=gamma
      - TZ=UTC
      - UPDATE_SERVER=FALSE
      - UPDATE_COORDINATION_ROLE=FOLLOWER
      - UPDATE_COORDINATION_PRIORITY=3
EOF
    source "$REPO_ROOT/POK-manager.sh"
    normalize_update_coordination_assignments
    echo "alpha=$(grep UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" | head -1)"
    echo "beta=$(grep UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" | head -1)"
    echo "alpha_priority=$(grep UPDATE_COORDINATION_PRIORITY "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" | head -1)"
    echo "beta_priority=$(grep UPDATE_COORDINATION_PRIORITY "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" | head -1)"
    if grep -q UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_gamma/docker-compose-gamma.yaml"; then
      echo "gamma_role=present"
    else
      echo "gamma_role=absent"
    fi
  '

  assert_success
  assert_output --partial "alpha=      - UPDATE_COORDINATION_ROLE=MASTER"
  assert_output --partial "beta=      - UPDATE_COORDINATION_ROLE=FOLLOWER"
  assert_output --partial "alpha_priority=      - UPDATE_COORDINATION_PRIORITY=1"
  assert_output --partial "beta_priority=      - UPDATE_COORDINATION_PRIORITY=2"
  assert_output --partial "gamma_role=absent"
}

@test "normalize_update_coordination_assignments strips coordination envs when only one auto-updating instance exists" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/coord-single" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
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
      - UPDATE_SERVER=FALSE
      - UPDATE_COORDINATION_ROLE=FOLLOWER
      - UPDATE_COORDINATION_PRIORITY=2
EOF
    source "$REPO_ROOT/POK-manager.sh"
    normalize_update_coordination_assignments
    if grep -q UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml"; then
      echo "alpha_role=present"
    else
      echo "alpha_role=absent"
    fi
    if grep -q UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_beta/docker-compose-beta.yaml"; then
      echo "beta_role=present"
    else
      echo "beta_role=absent"
    fi
  '

  assert_success
  assert_output --partial "alpha_role=absent"
  assert_output --partial "beta_role=absent"
}

@test "normalize_update_coordination_assignments can promote an explicitly selected instance to master" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/coord-preferred-master" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
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
    source "$REPO_ROOT/POK-manager.sh"
    normalize_update_coordination_assignments beta
    echo "alpha=$(grep UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" | head -1)"
    echo "alpha_priority=$(grep UPDATE_COORDINATION_PRIORITY "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" | head -1)"
    echo "beta=$(grep UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" | head -1)"
    echo "beta_priority=$(grep UPDATE_COORDINATION_PRIORITY "$BASE_DIR/Instance_beta/docker-compose-beta.yaml" | head -1)"
  '

  assert_success
  assert_output --partial "alpha=      - UPDATE_COORDINATION_ROLE=FOLLOWER"
  assert_output --partial "alpha_priority=      - UPDATE_COORDINATION_PRIORITY=2"
  assert_output --partial "beta=      - UPDATE_COORDINATION_ROLE=MASTER"
  assert_output --partial "beta_priority=      - UPDATE_COORDINATION_PRIORITY=1"
}
