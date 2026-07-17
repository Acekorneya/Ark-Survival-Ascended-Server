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
      if [ "${1:-}" = "--version" ]; then
        echo "yq (https://github.com/mikefarah/yq/) version v4.9.8"
        return 0
      fi
      if [ "${1:-}" = "e" ] && [ "${2:-}" = "-n" ]; then
        echo "probe: ok"
        return 0
      fi
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

@test "read_docker_compose_config loads quoted Steam credentials without exposing them in config_order" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/compose-steam-read" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
      - '\''STEAM_USERNAME=steam_user'\''
      - '\''STEAM_PASSWORD=p@ss:wo#rd&x'\''
      - '\''STEAM_SHARED_SECRET=secret==value'\''
    mem_limit: 16G
EOF
    yq() {
      if [ "${1:-}" = "--version" ]; then
        echo "yq (https://github.com/mikefarah/yq/) version v4.9.8"
        return 0
      fi
      if [ "${1:-}" = "e" ] && [ "${2:-}" = "-n" ]; then
        echo "probe: ok"
        return 0
      fi
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
    printf "steam_user=%s\n" "${config_values["STEAM_USERNAME"]}"
    printf "steam_pass=%s\n" "${config_values["STEAM_PASSWORD"]}"
    if [ -n "${config_values["STEAM_SHARED_SECRET"]+set}" ]; then
      echo "steam_secret_present=yes"
    else
      echo "steam_secret_present=no"
    fi
    if printf "%s\n" "${config_order[@]}" | grep -qx "STEAM_PASSWORD"; then
      echo "steam_in_order=yes"
    else
      echo "steam_in_order=no"
    fi
  '

  assert_success
  assert_output --partial "steam_user=steam_user"
  assert_output --partial "steam_pass=p@ss:wo#rd&x"
  assert_output --partial "steam_secret_present=no"
  assert_output --partial "steam_in_order=no"
}

@test "_read_compose_environment_lines strips double-quoted yq output defensively" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/compose-double-quoted" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    touch "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
    yq() {
      if [ "${1:-}" = "--version" ]; then
        echo "yq (https://github.com/mikefarah/yq/) version v4.9.8"
        return 0
      fi
      if [ "${1:-}" = "e" ] && [ "${2:-}" = "-n" ]; then
        echo "probe: ok"
        return 0
      fi
      if [ "${1:-}" = "e" ] && [ "${2:-}" = ".services.asaserver.environment[]" ]; then
        echo "\"MAX_PLAYERS=70\""
        echo "\"STEAM_PASSWORD=p@ss:wo#rd&x\""
        return 0
      fi
      return 1
    }
    source "$REPO_ROOT/POK-manager.sh"
    _read_compose_environment_lines "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "MAX_PLAYERS=70"
  assert_output --partial "STEAM_PASSWORD=p@ss:wo#rd&x"
  refute_output --partial '"MAX_PLAYERS=70"'
}

@test "resolve_yq_bin prefers manager-owned Mike Farah yq over incompatible system yq" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/yq-managed-preferred" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/config/POK-manager/bin" "$BASE_DIR/fake-bin"
    cat > "$BASE_DIR/config/POK-manager/bin/yq" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "yq (https://github.com/mikefarah/yq/) version v4.9.8"
  exit 0
fi
if [ "${1:-}" = "e" ] && [ "${2:-}" = "-n" ]; then
  echo "probe: ok"
  exit 0
fi
exit 0
EOF
    chmod +x "$BASE_DIR/config/POK-manager/bin/yq"
    cat > "$BASE_DIR/fake-bin/yq" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "yq 3.4.3"
  exit 0
fi
exit 1
EOF
    chmod +x "$BASE_DIR/fake-bin/yq"
    PATH="$BASE_DIR/fake-bin:$PATH"
    source "$REPO_ROOT/POK-manager.sh"
    resolved="$(resolve_yq_bin)"
    printf "resolved=%s\n" "$resolved"
    "$resolved" --version
  '

  assert_success
  assert_output --partial "resolved=${BATS_TEST_TMPDIR}/yq-managed-preferred/config/POK-manager/bin/yq"
  assert_output --partial "mikefarah/yq"
}

@test "resolve_yq_bin keeps using an existing Mike Farah system yq when manager-owned yq is absent" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/yq-system-valid" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/fake-bin"
    cat > "$BASE_DIR/fake-bin/yq" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "yq (https://github.com/mikefarah/yq/) version v4.9.8"
  exit 0
fi
if [ "${1:-}" = "e" ] && [ "${2:-}" = "-n" ]; then
  echo "probe: ok"
  exit 0
fi
exit 0
EOF
    chmod +x "$BASE_DIR/fake-bin/yq"
    PATH="$BASE_DIR/fake-bin:$PATH"
    source "$REPO_ROOT/POK-manager.sh"
    resolved="$(resolve_yq_bin)"
    printf "resolved=%s\n" "$resolved"
  '

  assert_success
  assert_output --partial "resolved=${BATS_TEST_TMPDIR}/yq-system-valid/fake-bin/yq"
}

@test "require_yq_bin rejects incompatible yq and tells users to run setup" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/yq-wrong-clear-error" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/fake-bin"
    cat > "$BASE_DIR/fake-bin/yq" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "yq 3.4.3"
  exit 0
fi
exit 1
EOF
    chmod +x "$BASE_DIR/fake-bin/yq"
    PATH="$BASE_DIR/fake-bin:$PATH"
    source "$REPO_ROOT/POK-manager.sh"
    require_yq_bin
  '

  assert_failure
  assert_output --partial "Mike Farah"
  assert_output --partial "Run ./POK-manager.sh -setup"
}

@test "install_yq installs manager-owned Mike Farah yq when system yq is incompatible" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/yq-install-managed" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/fake-bin"
    cat > "$BASE_DIR/fake-bin/yq" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "yq 3.4.3"
  exit 0
fi
exit 1
EOF
    chmod +x "$BASE_DIR/fake-bin/yq"
    cat > "$BASE_DIR/fake-bin/wget" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
target=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -O)
      target="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[ -n "$target" ] || exit 1
cat > "$target" <<'"'"'YQEOF'"'"'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "yq (https://github.com/mikefarah/yq/) version v4.9.8"
  exit 0
fi
if [ "${1:-}" = "e" ] && [ "${2:-}" = "-n" ]; then
  echo "probe: ok"
  exit 0
fi
exit 0
YQEOF
EOF
    chmod +x "$BASE_DIR/fake-bin/wget"
    PATH="$BASE_DIR/fake-bin:$PATH"
    source "$REPO_ROOT/POK-manager.sh"
    install_yq
    managed="$(managed_yq_path)"
    printf "managed=%s\n" "$managed"
    "$managed" --version
  '

  assert_success
  assert_output --partial "incompatible yq"
  assert_output --partial "managed=${BATS_TEST_TMPDIR}/yq-install-managed/config/POK-manager/bin/yq"
  assert_output --partial "mikefarah/yq"
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
  assert_output --partial "save_wait=90"
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
    grep "stop_grace_period" "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "SAVE_WAIT_SECONDS=60"
  assert_output --partial "stop_grace_period: 210s"
}

@test "shutdown config sync preserves an existing five-second preference" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/save-wait-preserve" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
services:
  asaserver:
    restart: unless-stopped
    environment:
      - SAVE_WAIT_SECONDS=5
EOF
    source "$REPO_ROOT/POK-manager.sh"
    _start_instance_sync_save_wait_seconds_env "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
    grep -E "SAVE_WAIT_SECONDS|stop_grace_period" "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "SAVE_WAIT_SECONDS=5"
  assert_output --partial "stop_grace_period: 100s"
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
    grep "stop_grace_period" "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "SAVE_WAIT_SECONDS=11"
  assert_output --partial "stop_grace_period: 112s"
}

@test "add_steam_creds_to_compose writes YAML-safe quoted Steam credential lines and removes stale shared secrets" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/steam-compose-write" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<'"'"'EOF'"'"'
version: "2.4"
services:
  asaserver:
    environment:
      - INSTANCE_NAME=demo
      - CUSTOM_SERVER_ARGS=
      - '\''STEAM_SHARED_SECRET=legacy-secret'\''
    ports:
      - "7777:7777/tcp"
EOF
    source "$REPO_ROOT/POK-manager.sh"
    add_steam_creds_to_compose \
      "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" \
      "steam user" \
      "p@ss:wo#rd&x"
    cat "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "'STEAM_USERNAME=steam user'"
  assert_output --partial "'STEAM_PASSWORD=p@ss:wo#rd&x'"
  refute_output --partial "STEAM_SHARED_SECRET"
}

@test "write_docker_compose_file preserves Steam credentials from config_values" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/steam-compose-preserve" POK_MANAGER_TEST_MODE=1 bash -lc '
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
      ["Save Wait Seconds"]="5"
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
      ["STEAM_USERNAME"]="steam_user"
      ["STEAM_PASSWORD"]="secret#pass"
    )
    write_docker_compose_file demo
    cat "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "'STEAM_USERNAME=steam_user'"
  assert_output --partial "'STEAM_PASSWORD=secret#pass'"
  refute_output --partial "STEAM_SHARED_SECRET"
}

@test "write_docker_compose_file copies Steam credentials from existing instances for new configs" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/steam-compose-copy" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    TZ="UTC"
    PUID=7777
    PGID=7777
    chmod() { :; }
    chown() { :; }
    get_docker_image_tag() { echo "2_1_beta"; }
    find_existing_steam_creds() {
      local -n _user="$1"
      local -n _pass="$2"
      _user="copied_user"
      _pass="copied pass"
    }
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
      ["Save Wait Seconds"]="5"
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
    cat "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "'STEAM_USERNAME=copied_user'"
  assert_output --partial "'STEAM_PASSWORD=copied pass'"
  refute_output --partial "STEAM_SHARED_SECRET"
}

@test "write_docker_compose_file skips Steam credentials when none are available" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/steam-compose-skip" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    TZ="UTC"
    PUID=7777
    PGID=7777
    chmod() { :; }
    chown() { :; }
    get_docker_image_tag() { echo "2_1_beta"; }
    find_existing_steam_creds() { return 1; }
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
      ["Save Wait Seconds"]="5"
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
    if grep -q "STEAM_USERNAME" "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"; then
      echo "steam_present=yes"
    else
      echo "steam_present=no"
    fi
  '

  assert_success
  assert_output --partial "steam_present=no"
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
      if [ "${1:-}" = "--version" ]; then
        echo "yq (https://github.com/mikefarah/yq/) version v4.9.8"
        return 0
      fi
      if [ "${1:-}" = "e" ] && [ "${2:-}" = "-n" ]; then
        echo "probe: ok"
        return 0
      fi
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

@test "normalize_update_coordination_assignments disables shared auto updates when any configured instance opts out" {
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
    for instance in alpha beta gamma; do
      if grep -q UPDATE_COORDINATION_ROLE "$BASE_DIR/Instance_${instance}/docker-compose-${instance}.yaml"; then
        echo "${instance}_role=present"
      else
        echo "${instance}_role=absent"
      fi
    done
    echo "policy=$(grep POK_SHARED_AUTOMATIC_UPDATES "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" | head -1 | sed "s/.*=//")"
    echo "blockers=$(grep POK_SHARED_BLOCKING_INSTANCES "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" | head -1 | sed "s/.*=//")"
  '

  assert_success
  assert_output --partial "alpha_role=absent"
  assert_output --partial "beta_role=absent"
  assert_output --partial "gamma_role=absent"
  assert_output --partial "policy=FALSE"
  assert_output --partial "blockers=gamma:UPDATE_SERVER_FALSE"
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
