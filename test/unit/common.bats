#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "common.sh source does not auto-clean MOD_IDS or validate password" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    MOD_IDS="123, 456"
    SERVER_PASSWORD="bad!pass"
    source "$REPO_ROOT/scripts/common.sh"
    printf "mod_ids=%s\n" "$MOD_IDS"
    printf "validator=%s\n" "$(type -t validate_server_password)"
  '

  assert_success
  assert_output --partial "mod_ids=123, 456"
  assert_output --partial "validator=function"
}

@test "prepare_runtime_env applies cleanup only when called" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    MOD_IDS="123, 456"
    SERVER_PASSWORD="goodpass"
    INSTANCE_NAME="alpha"
    source "$REPO_ROOT/scripts/common.sh"
    prepare_runtime_env
    printf "mod_ids=%s\n" "$MOD_IDS"
    printf "pid_file=%s\n" "$PID_FILE"
  '

  assert_success
  assert_output --partial "mod_ids=123,456"
  assert_output --partial "pid_file=/home/pok/alpha_ark_server.pid"
}

@test "prepare_runtime_env keeps only the EOS settings still used at runtime" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    INSTANCE_NAME="alpha"
    source "$REPO_ROOT/scripts/common.sh"
    prepare_runtime_env
    printf "deployment=%s\n" "$EOS_DEPLOYMENT_ID"
    printf "matchmaking=%s\n" "$EOS_MATCHMAKING_BASE"
    printf "client_id=%s\n" "${EOS_CLIENT_ID:-unset}"
    printf "client_secret=%s\n" "${EOS_CLIENT_SECRET:-unset}"
    printf "basic_auth=%s\n" "${EOS_BASIC_AUTH:-unset}"
  '

  assert_success
  assert_output --partial "deployment=ad9a8feffb3b4b2ca315546f038c3ae2"
  assert_output --partial "matchmaking=https://api.epicgames.dev/wildcard/matchmaking/v1"
  assert_output --partial "client_id=unset"
  assert_output --partial "client_secret=unset"
  assert_output --partial "basic_auth=unset"
}

@test "env_value_is_truthy recognizes supported true values" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/common.sh"
    for value in TRUE true YES yes 1; do
      env_value_is_truthy "$value"
    done
    echo "all=true"
  '

  assert_success
  assert_output --partial "all=true"
}

@test "resolve_pinned_proton accepts only the version recorded by the image" {
  run env REPO_ROOT="$PROJECT_ROOT" PROTON_ROOT="$BATS_TEST_TMPDIR/proton-valid" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/common.sh"
    mkdir -p "$PROTON_ROOT/GE-Proton10-34"
    printf "#!/bin/bash\n" > "$PROTON_ROOT/GE-Proton10-34/proton"
    chmod +x "$PROTON_ROOT/GE-Proton10-34/proton"
    ln -s "$PROTON_ROOT/GE-Proton10-34" "$PROTON_ROOT/GE-Proton-Current"
    printf "GE-Proton10-34\n" > "$PROTON_ROOT/.pok-proton-version"
    POK_PROTON_BASE_DIR="$PROTON_ROOT"
    resolve_pinned_proton
    printf "version=%s\n" "$POK_PROTON_VERSION"
    printf "executable=%s\n" "$POK_PROTON_EXECUTABLE"
  '

  assert_success
  assert_output --partial "version=GE-Proton10-34"
  assert_output --partial "/GE-Proton10-34/proton"
}

@test "resolve_pinned_proton rejects a mismatched canonical target" {
  run env REPO_ROOT="$PROJECT_ROOT" PROTON_ROOT="$BATS_TEST_TMPDIR/proton-mismatch" bash -lc '
    source "$REPO_ROOT/scripts/common.sh"
    mkdir -p "$PROTON_ROOT/GE-Proton8-21"
    printf "#!/bin/bash\n" > "$PROTON_ROOT/GE-Proton8-21/proton"
    chmod +x "$PROTON_ROOT/GE-Proton8-21/proton"
    ln -s "$PROTON_ROOT/GE-Proton8-21" "$PROTON_ROOT/GE-Proton-Current"
    printf "GE-Proton10-34\n" > "$PROTON_ROOT/.pok-proton-version"
    POK_PROTON_BASE_DIR="$PROTON_ROOT"
    if resolve_pinned_proton; then
      echo "result=unexpected-success"
    else
      echo "result=rejected"
    fi
  '

  assert_success
  assert_output --partial "result=rejected"
  refute_output --partial "result=unexpected-success"
}

@test "managed AsaApi cache failures expose the incompatible symbol while retrying" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/asaapi-cache-wait" bash -lc '
    set -e
    POK_SCRIPTS_DIR="$REPO_ROOT/scripts"
    source "$POK_SCRIPTS_DIR/common.sh"
    mkdir -p "$BATS_TMP"
    ASAAPI_WAIT_MARKER="$BATS_TMP/wait.marker"
    install_ark_server_api() { return 0; }
    asaapi_source_is_custom() { return 1; }
    prepare_ark_server_api_cache() {
      local count=0
      [ -f "$BATS_TMP/count" ] && count=$(cat "$BATS_TMP/count")
      count=$((count + 1))
      printf "%s\n" "$count" > "$BATS_TMP/count"
      if [ "$count" -eq 1 ]; then
        echo "[ERROR] AsaApi cache for ARK executable abc is unusable: Cache map is missing required AsaApi offsets: AShooterGameMode.Logout(AController*)"
        return 20
      fi
      echo "[INFO] corrected cache ready"
      return 0
    }
    sleep() {
      printf "marker=%s\n" "$(cat "$ASAAPI_WAIT_MARKER")"
    }
    ASAAPI_CACHE_RETRY_SECONDS=5
    ensure_ark_server_api_ready
    [ ! -e "$ASAAPI_WAIT_MARKER" ] && echo "marker-removed=yes"
  '

  assert_success
  assert_output --partial "marker=starting: AsaApi cache for ARK executable abc is unusable"
  assert_output --partial "AShooterGameMode.Logout(AController*)"
  assert_output --partial "corrected cache ready"
  assert_output --partial "marker-removed=yes"
}

@test "rollback protection retries only for a new Steam build or changed AsaApi cache" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/rollback-retry" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/common.sh"
    ASA_DIR="$BATS_TMP/server"
    DEPLOYMENT_STATE_DIR="$ASA_DIR/.pok-manager/deployments"
    ASAAPI_MANAGER_PATH="$REPO_ROOT/scripts/helpers/asaapi_manager.py"
    mkdir -p "$DEPLOYMENT_STATE_DIR" "$ASA_DIR/ShooterGame/Binaries/Win64"
    touch "$DEPLOYMENT_STATE_DIR/active_rollback.json"
    deployment_state_field() {
      case "$2" in
        failed_build_id) echo 100 ;;
        failed_executable_sha256) printf "%064d\n" 1 ;;
        failed_cache_last_modified) echo cache-v1 ;;
      esac
    }
    python3() { echo "${REMOTE_TIMESTAMP:-cache-v1}"; }
    if rollback_retry_is_available 100; then echo unchanged=yes; else echo unchanged=no; fi
    REMOTE_TIMESTAMP=cache-v2
    if rollback_retry_is_available 100; then echo cache_changed=yes; fi
    REMOTE_TIMESTAMP=cache-v1
    if rollback_retry_is_available 101; then echo build_changed=yes; fi
  '

  assert_success
  assert_output --partial "unchanged=no"
  assert_output --partial "cache_changed=yes"
  assert_output --partial "build_changed=yes"
}

@test "rollback-protected candidate cache failure never syncs staged files live" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/rollback-preflight" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/common.sh"
    ASA_DIR="$BATS_TMP/server"
    mkdir -p "$ASA_DIR"
    rollback_state_is_active() { return 0; }
    steamcmd_download_to_dir() { mkdir -p "$1"; echo downloaded; }
    prepare_staged_asaapi_cache() { echo incompatible; return 1; }
    record_failed_rollback_retry() { echo failure-recorded; }
    sync_temp_into_live_dir() { echo unexpected-sync; }
    if perform_staged_server_download "$BATS_TMP/staged"; then
      echo unexpected-success
    else
      echo safely-rejected
    fi
  '

  assert_success
  assert_output --partial "incompatible"
  assert_output --partial "failure-recorded"
  assert_output --partial "safely-rejected"
  refute_output --partial "unexpected-sync"
}

@test "shared update policy blocks automatic updates from manager-written aggregate env" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    source "$REPO_ROOT/scripts/common.sh"
    UPDATE_SERVER=TRUE
    API=FALSE
    POK_SHARED_AUTOMATIC_UPDATES=FALSE
    POK_SHARED_BLOCKING_INSTANCES="api_server:API_TRUE,manual:UPDATE_SERVER_FALSE"
    if shared_update_policy_allows_automatic_updates; then
      echo "result=unexpected-allowed"
    else
      echo "result=blocked"
    fi
    shared_update_policy_load
    echo "blockers=$SHARED_POLICY_BLOCKING_INSTANCES"
  '

  assert_success
  assert_output --partial "result=blocked"
  assert_output --partial "blockers=api_server:API_TRUE,manual:UPDATE_SERVER_FALSE"
}

@test "explicit manual shared update overrides the aggregate automatic policy" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    source "$REPO_ROOT/scripts/common.sh"
    POK_SHARED_AUTOMATIC_UPDATES=FALSE
    POK_MANUAL_SHARED_UPDATE=TRUE
    if shared_update_policy_allows_automatic_updates; then
      echo "result=allowed"
    fi
  '

  assert_success
  assert_output --partial "result=allowed"
}
