#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "shutdown_server.sh can be sourced without executing a shutdown" {
  run env REPO_ROOT="$PROJECT_ROOT" ASA_ROOT="$BATS_TEST_TMPDIR/asa-source" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    printf "shutdown=%s\n" "$(type -t shutdown_handler)"
  '

  assert_success
  assert_output --partial "shutdown=function"
}

@test "save_complete_check detects completed saves from the server log" {
  run env REPO_ROOT="$PROJECT_ROOT" ASA_ROOT="$BATS_TEST_TMPDIR/asa-save" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    ASA_DIR="$ASA_ROOT"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    cat > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log" <<'"'"'EOF'"'"'
line one
World Save Complete
EOF
    save_complete_check
  '

  assert_success
  assert_output --partial "Save operation completed."
}

@test "server_stopped_check detects stopped servers from the server log" {
  run env REPO_ROOT="$PROJECT_ROOT" ASA_ROOT="$BATS_TEST_TMPDIR/asa-stop" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    ASA_DIR="$ASA_ROOT"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    cat > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log" <<'"'"'EOF'"'"'
line one
Server stopped
EOF
    server_stopped_check
  '

  assert_success
  assert_output --partial "Server stopped properly."
}

@test "safe_container_stop sets the shutdown flag immediately when no server process is running" {
  run env REPO_ROOT="$PROJECT_ROOT" ASA_ROOT="$BATS_TEST_TMPDIR/asa-safe-stop" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    SHUTDOWN_COMPLETE_FLAG="$BATS_TEST_TMPDIR/shutdown_complete.flag"
    pgrep() { return 1; }
    safe_container_stop
    printf "flag=%s\n" "$( [ -f "$SHUTDOWN_COMPLETE_FLAG" ] && echo yes || echo no )"
  '

  assert_success
  assert_output --partial "Server is not running, no need to save world before stopping container."
  assert_output --partial "flag=yes"
}

@test "shutdown_main_save_file uses exact MAP_NAME for modded and future maps" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/map-exact" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    ASA_DIR="$BATS_TMP/arkserver"
    MAP_NAME="GenesisFutureMod"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/SavedArks/GenesisFutureMod"
    : > "$ASA_DIR/ShooterGame/Saved/SavedArks/GenesisFutureMod/GenesisFutureMod.ark"
    shutdown_main_save_file
  '

  assert_success
  assert_output --partial "GenesisFutureMod/GenesisFutureMod.ark"
}

@test "shutdown_main_save_file falls back to launch-compatible MAP_NAME_WP" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/map-wp" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    ASA_DIR="$BATS_TMP/arkserver"
    MAP_NAME="TheIsland"
    mkdir -p "$ASA_DIR/ShooterGame/Saved/SavedArks/TheIsland"
    : > "$ASA_DIR/ShooterGame/Saved/SavedArks/TheIsland/TheIsland_WP.ark"
    shutdown_main_save_file
  '

  assert_success
  assert_output --partial "TheIsland/TheIsland_WP.ark"
}

@test "verified_saveworld requires a fresh completion marker" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/fresh-log" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    ASA_DIR="$BATS_TMP/arkserver"
    SAVE_WAIT_SECONDS=2
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    echo "World Save Complete. Took: old" > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    send_rcon_command() {
      echo "World Save Complete. Took: new" >> "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    }
    verified_saveworld
    echo "source=$SAVE_CONFIRMATION_SOURCE"
  '

  assert_success
  assert_output --partial "save confirmed by a new"
  assert_output --partial "source=log"
}

@test "verified_doexit_save cannot reuse the SaveWorld checkpoint" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/stale-doexit" bash -lc '
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    ASA_DIR="$BATS_TMP/arkserver"
    SAVE_WAIT_SECONDS=1
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs"
    echo "World Save Complete. Took: stage-one" > "$ASA_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    send_rcon_command() { return 0; }
    if verified_doexit_save; then
      echo "result=unexpected-success"
    else
      echo "result=failed"
    fi
  '

  assert_success
  assert_output --partial "result=failed"
  refute_output --partial "result=unexpected-success"
}

@test "verified save accepts changed stable main ark metadata as warned fallback" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/file-fallback" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    ASA_DIR="$BATS_TMP/arkserver"
    MAP_NAME="Astraeos_WP"
    SAVE_WAIT_SECONDS=2
    SAVE_FILE_STABLE_SECONDS=1
    mkdir -p "$ASA_DIR/ShooterGame/Saved/SavedArks/Astraeos_WP"
    save_file="$ASA_DIR/ShooterGame/Saved/SavedArks/Astraeos_WP/Astraeos_WP.ark"
    printf old > "$save_file"
    send_rcon_command() { printf newer-world-data >> "$save_file"; }
    verified_saveworld
    echo "source=$SAVE_CONFIRMATION_SOURCE"
  '

  assert_success
  assert_output --partial "accepting stable .ark metadata fallback"
  assert_output --partial "Astraeos_WP/Astraeos_WP.ark"
  assert_output --partial "source=file"
}

@test "safe_container_stop does not create completion flag when DoExit save is unverified" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/stage-two-flag" bash -lc '
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/shutdown_server.sh"
    SHUTDOWN_COMPLETE_FLAG="$BATS_TMP/shutdown.flag"
    shutdown_server_process_running() { return 0; }
    send_rcon_command() { return 0; }
    verified_saveworld() { echo "stage-one=ok"; return 0; }
    verified_doexit_save() { echo "stage-two=failed"; return 1; }
    if safe_container_stop; then
      echo "result=unexpected-success"
    else
      echo "result=failed"
    fi
    [ -f "$SHUTDOWN_COMPLETE_FLAG" ] && echo "flag=yes" || echo "flag=no"
  '

  assert_success
  assert_output --partial "stage-one=ok"
  assert_output --partial "stage-two=failed"
  assert_output --partial "result=failed"
  assert_output --partial "flag=no"
}
