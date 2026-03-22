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
