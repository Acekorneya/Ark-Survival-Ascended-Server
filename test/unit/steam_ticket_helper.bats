#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "steam_ticket helper uses createAuthSessionTicket and returns uppercase hex" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    modules_dir="$BATS_TEST_TMPDIR/modules"
    helper_copy="$BATS_TEST_TMPDIR/steam_ticket.js"
    mkdir -p "$modules_dir/steam-user"
    cp "$REPO_ROOT/scripts/helpers/steam_ticket.js" "$helper_copy"

    cat > "$modules_dir/steam-user/index.js" <<'"'"'EOF'"'"'
const fs = require("fs");
const {EventEmitter} = require("events");

module.exports = class SteamUser extends EventEmitter {
  logOn() {
    setImmediate(() => this.emit("loggedOn"));
  }

  gamesPlayed() {}

  getAuthSessionTicket() {
    fs.writeFileSync(process.env.TEST_MARKER, "wrong-api");
    throw new Error("getAuthSessionTicket should not be used");
  }

  createAuthSessionTicket(appId, callback) {
    fs.writeFileSync(process.env.TEST_MARKER, `create:${appId}`);
    callback(null, Buffer.alloc(64, 0xab));
  }

  logOff() {}
};
EOF

    TEST_MARKER="$BATS_TEST_TMPDIR/steam-ticket-marker"
    set +e
    output=$(NODE_PATH="$modules_dir" TEST_MARKER="$TEST_MARKER" STEAM_USERNAME="user" STEAM_PASSWORD="pass" STEAM_TICKET_REQUEST_DELAY_MS=0 timeout 5 node "$helper_copy")
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "output=%s\n" "$output"
    printf "marker=%s\n" "$(cat "$TEST_MARKER")"
  '

  assert_success
  assert_output --partial "status=0"
  assert_output --partial "marker=create:2399830"
  assert_output --partial "output=ABABABAB"
}

@test "steam_ticket helper rejects unexpectedly short tickets" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    modules_dir="$BATS_TEST_TMPDIR/modules"
    helper_copy="$BATS_TEST_TMPDIR/steam_ticket.js"
    mkdir -p "$modules_dir/steam-user"
    cp "$REPO_ROOT/scripts/helpers/steam_ticket.js" "$helper_copy"

    cat > "$modules_dir/steam-user/index.js" <<'"'"'EOF'"'"'
const {EventEmitter} = require("events");

module.exports = class SteamUser extends EventEmitter {
  logOn() {
    setImmediate(() => this.emit("loggedOn"));
  }

  gamesPlayed() {}

  createAuthSessionTicket(appId, callback) {
    callback(null, Buffer.alloc(21, 0xcd));
  }

  logOff() {}
};
EOF

    set +e
    NODE_PATH="$modules_dir" STEAM_USERNAME="user" STEAM_PASSWORD="pass" STEAM_TICKET_REQUEST_DELAY_MS=0 timeout 5 node "$helper_copy"
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Steam error: Steam session ticket is unexpectedly short (21 bytes)"
  assert_output --partial "status=1"
}

@test "steam_ticket helper shows a clear message when session ticket creation fails because the account is in use elsewhere" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    modules_dir="$BATS_TEST_TMPDIR/modules"
    helper_copy="$BATS_TEST_TMPDIR/steam_ticket.js"
    mkdir -p "$modules_dir/steam-user"
    cp "$REPO_ROOT/scripts/helpers/steam_ticket.js" "$helper_copy"

    cat > "$modules_dir/steam-user/index.js" <<'"'"'EOF'"'"'
const {EventEmitter} = require("events");

module.exports = class SteamUser extends EventEmitter {
  logOn() {
    setImmediate(() => this.emit("loggedOn"));
  }

  gamesPlayed() {}

  createAuthSessionTicket(appId, callback) {
    callback(new Error("LoggedInElsewhere"));
  }

  logOff() {}
};
EOF

    set +e
    output=$(NODE_PATH="$modules_dir" STEAM_USERNAME="user" STEAM_PASSWORD="pass" STEAM_TICKET_REQUEST_DELAY_MS=0 timeout 5 node "$helper_copy" 2>&1)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "%s\n" "$output"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "Steam error: LoggedInElsewhere. This Steam account is currently logged in on another device (e.g. you are playing a game). Close Steam or stop playing, then try -status again."
}

@test "steam_ticket helper requests Steam Guard only when Steam asks for it" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    modules_dir="$BATS_TEST_TMPDIR/modules"
    helper_copy="$BATS_TEST_TMPDIR/steam_ticket.js"
    mkdir -p "$modules_dir/steam-user"
    cp "$REPO_ROOT/scripts/helpers/steam_ticket.js" "$helper_copy"

    cat > "$modules_dir/steam-user/index.js" <<'"'"'EOF'"'"'
const {EventEmitter} = require("events");

module.exports = class SteamUser extends EventEmitter {
  logOn() {
    setImmediate(() => this.emit("steamGuard", null, () => {}));
  }

  gamesPlayed() {}
  createAuthSessionTicket() {}
  logOff() {}
};
EOF

    set +e
    output=$(NODE_PATH="$modules_dir" STEAM_USERNAME="user" STEAM_PASSWORD="pass" STEAM_TICKET_REQUEST_DELAY_MS=0 timeout 5 node "$helper_copy" 2>&1)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "%s\n" "$output"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "STEAM_GUARD_REQUIRED:mobile authenticator"
  assert_output --partial "Enter the current 5-digit code from your Steam app when prompted."
}

@test "steam_ticket helper shows a clear message when Steam rate-limits the account" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    modules_dir="$BATS_TEST_TMPDIR/modules"
    helper_copy="$BATS_TEST_TMPDIR/steam_ticket.js"
    mkdir -p "$modules_dir/steam-user"
    cp "$REPO_ROOT/scripts/helpers/steam_ticket.js" "$helper_copy"

    cat > "$modules_dir/steam-user/index.js" <<'"'"'EOF'"'"'
const {EventEmitter} = require("events");

module.exports = class SteamUser extends EventEmitter {
  logOn() {
    setImmediate(() => this.emit("error", new Error("RateLimitExceeded")));
  }

  gamesPlayed() {}
  createAuthSessionTicket() {}
  logOff() {}
};
EOF

    set +e
    output=$(NODE_PATH="$modules_dir" STEAM_USERNAME="user" STEAM_PASSWORD="pass" STEAM_TICKET_REQUEST_DELAY_MS=0 timeout 5 node "$helper_copy" 2>&1)
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "%s\n" "$output"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "Steam error: RateLimitExceeded. Steam is temporarily rate-limiting this account. Wait a few minutes and try -status again."
}
