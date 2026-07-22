#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "launch_ASA.sh can be sourced without starting the server" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "Proton console filtering hides only the misleading direct-launch unit-test warning" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/proton-filter" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    mkdir -p "$BATS_TMP"
    PROTON_RUNTIME_LOG="$BATS_TMP/proton.log"
    printf "%s\n" \
      "ProtonFixes[324] WARN: Skipping fix execution. We are probably running a unit test." \
      "Proton: Upgrading prefix from None to GE-Proton10-34" \
      "wine: example actionable failure" | filter_proton_runtime_output
    printf "%s\n" "---raw-diagnostics---"
    cat "$PROTON_RUNTIME_LOG"
  '

  assert_success
  assert_line "Proton: Upgrading prefix from None to GE-Proton10-34"
  assert_line "wine: example actionable failure"
  assert_output --partial "---raw-diagnostics---"
  assert_output --partial "ProtonFixes[324] WARN: Skipping fix execution. We are probably running a unit test."
  [ "$(printf "%s\n" "$output" | grep -c "probably running a unit test")" -eq 1 ]
}

@test "AsaApi console filtering removes fixed startup boilerplate but keeps operational lines" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    printf "%s\n" \
      "07/16/26 10:25 [API][info] -----------------------------------------------" \
      "07/16/26 10:25 [API][info] ARK:SA Api V2.01" \
      "07/16/26 10:25 [API][info] Reading cached offsets" \
      "07/16/26 10:25 [API][info] Initialized hooks" \
      "07/16/26 10:25 [API][info] API was successfully loaded" \
      "07/16/26 10:25 [API][info] Loaded plugin Permissions V1.1" \
      "07/16/26 10:25 [API][critical] Failed to get an offset" |
      filter_asaapi_console_output
  '

  assert_success
  refute_output --partial "ARK:SA Api V2.01"
  refute_output --partial "Reading cached offsets"
  refute_output --partial "Initialized hooks"
  assert_line "07/16/26 10:25 [API][info] API was successfully loaded"
  assert_line "07/16/26 10:25 [API][info] Loaded plugin Permissions V1.1"
  assert_line "07/16/26 10:25 [API][critical] Failed to get an offset"
}

@test "determine_map_path maps official and custom map names" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    MAP_NAME=TheCenter
    determine_map_path
    printf "official=%s\n" "$MAP_PATH"
    MAP_NAME=CustomAdventure
    determine_map_path
    printf "custom=%s\n" "$MAP_PATH"
  '

  assert_success
  assert_output --partial "official=TheCenter_WP"
  assert_output --partial "custom=CustomAdventure_WP"
}

@test "get_server_process_id prefers the AsaApi loader when API mode is enabled" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    API=TRUE
    SERVER_PID=""
    ps() {
      if [ "$1" = "-p" ]; then
        return 1
      fi
      cat <<EOF
root 123 0.0 0.0 ? ? AsaApiLoader.exe
root 456 0.0 0.0 ? ? ArkAscendedServer.exe
EOF
    }
    get_server_process_id
    printf "pid=%s\n" "$SERVER_PID"
  '

  assert_success
  assert_output --partial "pid=123"
}

@test "launch_asa_detect_ready_marker accepts Full Startup and advertising markers" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    log_file="$BATS_TEST_TMPDIR/ShooterGame.log"
    printf "%s\n" "Full Startup: 59.50 seconds" > "$log_file"
    launch_asa_detect_ready_marker "$log_file"
    printf "first=%s\n" "$LAUNCH_ASA_READY_MARKER_TYPE"
    printf "%s\n" "Server has completed startup and is now advertising for join" > "$log_file"
    launch_asa_detect_ready_marker "$log_file"
    printf "second=%s\n" "$LAUNCH_ASA_READY_MARKER_TYPE"
  '

  assert_success
  assert_output --partial "first=full_startup"
  assert_output --partial "second=advertising"
}

@test "start_log_tail mirrors complete lines and follows log replacement" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    log_file="$BATS_TEST_TMPDIR/ShooterGame.log"
    captured="$BATS_TEST_TMPDIR/container.log"
    printf "%s\n" "Log file open" > "$log_file"

    start_log_tail "$log_file" GAME_TAIL_PID > "$captured" 2>&1
    printf "%s\n" "Commandline: Map?ServerPassword=joinSecret?ServerAdminPassword=adminSecret! -Port=7777" >> "$log_file"

    for _ in $(seq 1 50); do
      if grep -q "adminSecret" "$captured"; then
        break
      fi
      sleep 0.1
    done

    mv "$log_file" "$log_file.previous"
    printf "%s\n" "Server has completed startup and is now advertising for join" > "$log_file"
    for _ in $(seq 1 50); do
      if grep -q "advertising for join" "$captured"; then
        break
      fi
      sleep 0.1
    done

    kill "$GAME_TAIL_PID"
    wait "$GAME_TAIL_PID" 2>/dev/null || true
    if kill -0 "$GAME_TAIL_PID" 2>/dev/null; then
      printf "%s\n" "tail-still-running"
      exit 1
    fi
    cat "$captured"
    printf "%s\n" "tail-stopped"
  '

  assert_success
  assert_output --partial "Log file open"
  assert_output --partial "ServerPassword=joinSecret"
  assert_output --partial "ServerAdminPassword=adminSecret!"
  assert_output --partial "Server has completed startup and is now advertising for join"
  assert_output --partial "tail-stopped"
}

@test "update_game_user_settings updates the password and MOTD in GameUserSettings.ini" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    ini_file="$ASA_DIR/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini"
    mkdir -p "$(dirname "$ini_file")"
    cat > "$ini_file" <<EOF
[ServerSettings]
ServerPassword=oldpass

[MessageOfTheDay]
Message=old
Duration=20
EOF
    SERVER_PASSWORD=newpass
    ENABLE_MOTD=TRUE
    MOTD="Welcome survivors"
    MOTD_DURATION=45
    update_game_user_settings
    cat "$ini_file"
  '

  assert_success
  assert_output --partial "ServerPassword=newpass"
  assert_output --partial "[MessageOfTheDay]"
  assert_output --partial "Message=Welcome survivors"
  assert_output --partial "Duration=45"
}
