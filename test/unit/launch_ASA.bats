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

@test "all server launch paths use the already-prepared pinned Proton prefix" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    launch_script="$REPO_ROOT/scripts/launch_ASA.sh"
    if grep -Fq "\"\$PROTON_EXECUTABLE\" run " "$launch_script"; then
      printf "%s\n" "unexpected Proton run entrypoint"
      exit 1
    fi
    count="$(grep -Fc "\"\$PROTON_EXECUTABLE\" runinprefix" "$launch_script")"
    printf "runinprefix_count=%s\n" "$count"
    [ "$count" -ge 1 ]
  '

  assert_success
  assert_output --partial "runinprefix_count="
  refute_output --partial "unexpected Proton run entrypoint"
}

@test "Proton console filtering hides routine noise while retaining complete diagnostics" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/proton-filter" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    mkdir -p "$BATS_TMP"
    PROTON_RUNTIME_LOG="$BATS_TMP/proton.log"
    console_log="$BATS_TMP/console.log"
    printf "%s\n" \
      "ProtonFixes[324] WARN: Skipping fix execution. We are probably running a unit test." \
      "09-14 09:48:04.646 204 708 I Info/GameAnalytics : Event queue: Sending 3 events." \
      "09-14 09:48:04.649 204 708 D Debug/GameAnalytics : Sending events URL" \
      "Proton: Upgrading prefix from None to GE-Proton10-34" \
      "wine: example actionable failure" | filter_proton_runtime_output > "$console_log"
    ! grep -Eq "(Info|Debug)/GameAnalytics" "$console_log"
    print_proton_runtime_diagnostics "$PROTON_RUNTIME_LOG" > "$BATS_TMP/failure-summary.log"
    ! grep -Eq "(Info|Debug)/GameAnalytics" "$BATS_TMP/failure-summary.log"
    grep -Fq "wine: example actionable failure" "$BATS_TMP/failure-summary.log"
    cat "$console_log"
    printf "%s\n" "---raw-diagnostics---"
    cat "$PROTON_RUNTIME_LOG"
  '

  assert_success
  assert_line "Proton: Upgrading prefix from None to GE-Proton10-34"
  assert_line "wine: example actionable failure"
  assert_output --partial "---raw-diagnostics---"
  assert_output --partial "ProtonFixes[324] WARN: Skipping fix execution. We are probably running a unit test."
  assert_output --partial "Info/GameAnalytics : Event queue: Sending 3 events."
  assert_output --partial "Debug/GameAnalytics : Sending events URL"
  [ "$(printf "%s\n" "$output" | grep -c "probably running a unit test")" -eq 1 ]
  [ "$(printf "%s\n" "$output" | grep -Ec "(Info|Debug)/GameAnalytics")" -eq 2 ]
}

@test "SDK multiline metrics are hidden while raw diagnostics and real messages survive" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/sdk-filter" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    mkdir -p "$BATS_TMP"
    PROTON_RUNTIME_LOG="$BATS_TMP/proton.log"
    cat > "$BATS_TMP/input.log" <<EOF
Info/GameAnalytics : Sending events {
    "MapName": "Aberration_WP",
    "PeakPlayers": 0,
    "PlayerHours": 0,
    "UtcTime": "2026-10-01T15:33:34.016Z"
}}
    "AvgFPS": 30.3843,
    "AvgGameThreadMs": 7.6753,
    "MinFPS": 46.1759,
    "UtcTime": "2026
World Save Complete. Took: 0.49
    "MapName": "Aberration_WP",
    "PeakPlayers": 0,
    "PlayerHours": 0
}}
    "GCMs": 0,
    "GCs": 0
}}
    "SaveFrames": 0,
    "SaveMs": 0
}}
    "IntervalSeconds": 60.0309,
    "MapName": "Aberration_WP"
}}
    "AvailablePhysicalMB": 45910.78,
    "UsedVirtualMB": 8531.
    "AvgDpcPct": 0,
    "WorstInterruptPct": 0
}}
    "BoxBusyPct": 38.8158,
    "NeighbourCores": 11.9406
}}
    "BoxHardFaults": 0,
    "ProcessPageFaultsPerSecond": 0
}}
    "Connections": 0,
    "PingP50": 0,
    "PingP
wine: example actionable failure
    "Kicks": 0,
    "Timeouts": 0
}}
    "HitchLostMsSum": 0,
    "ModerateHitches": 0
}}
Server has completed startup and is now advertising for join.
{
    "MapName": "unrelated diagnostic",
    "Error": "keep this JSON"
}
10-01 14:06:18.111   204   708 W Warning/GameAnalytics : Available resource currencies must be set before SDK is initialized
10-01 14:06:18.111   204   708 W Warning/GameAnalytics : Available resource item types must be set before SDK is initialized
10-01 14:06:18.111   204   708 W Warning/GameAnalytics : SDK already initialized. Can only be called once.
Error/GameAnalytics : upload failed
Error/OtherSubsystem : keep this failure
EOF
    filter_proton_runtime_output < "$BATS_TMP/input.log" > "$BATS_TMP/console.log"
    cmp "$BATS_TMP/input.log" "$PROTON_RUNTIME_LOG"
    print_proton_runtime_diagnostics "$PROTON_RUNTIME_LOG" > "$BATS_TMP/summary.log"
    cmp "$BATS_TMP/console.log" "$BATS_TMP/summary.log"
    cat "$BATS_TMP/console.log"
  '

  assert_success
  assert_line "World Save Complete. Took: 0.49"
  assert_line "wine: example actionable failure"
  assert_line "Server has completed startup and is now advertising for join."
  assert_output --partial "keep this JSON"
  assert_line "Error/OtherSubsystem : keep this failure"
  refute_output --partial "/GameAnalytics"
  refute_output --partial "AvgFPS"
  refute_output --partial "Aberration_WP"
  refute_output --partial "UtcTime"
  refute_output --partial "PingP"
  refute_output --partial "}}"
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

@test "start_log_tail filters SDK payloads and follows log replacement without changing raw logs" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/launch_ASA.sh"
    log_file="$BATS_TEST_TMPDIR/ShooterGame.log"
    captured="$BATS_TEST_TMPDIR/container.log"
    printf "%s\n" "Log file open" > "$log_file"

    start_log_tail "$log_file" GAME_TAIL_PID shootergame > "$captured" 2>&1
    printf "%s\n" \
      "09-14 09:47:40.547 204 708 I Info/GameAnalytics : Event queue: No events to send" \
      "09-14 09:48:04.649 204 708 D Debug/GameAnalytics : Sending events URL" \
      "    \"AvgGameThreadMs\": 7.6753," \
      "    \"UtcTime\": \"2026-10-01T15:33:34.016Z\"" \
      "}}" >> "$log_file"
    printf "%s\n" "Commandline: Map?ServerPassword=joinSecret?ServerAdminPassword=adminSecret! -Port=7777" >> "$log_file"

    for _ in $(seq 1 50); do
      if grep -q "adminSecret" "$captured"; then
        break
      fi
      sleep 0.1
    done

    grep -Fq "AvgGameThreadMs" "$log_file"
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
  refute_output --partial "Info/GameAnalytics"
  refute_output --partial "Debug/GameAnalytics"
  refute_output --partial "AvgGameThreadMs"
  refute_output --partial "UtcTime"
  refute_output --partial "}}"
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
