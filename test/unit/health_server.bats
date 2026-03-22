#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "health_server.py returns 200 for a healthy probe" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    probe="$BATS_TEST_TMPDIR/probe-ok.sh"
    cat > "$probe" <<'\''EOF'\''
#!/bin/bash
echo "ok: stub healthy"
exit 0
EOF
    chmod +x "$probe"
    port=18080
    HEALTHCHECK_PORT="$port" HEALTHCHECK_PROBE_SCRIPT="$probe" python3 "$REPO_ROOT/scripts/health_server.py" &
    server_pid=$!
    trap "kill $server_pid 2>/dev/null || true" EXIT
    for _ in $(seq 1 20); do
      if curl -fsS "http://127.0.0.1:${port}/healthz" >/tmp/health_server_body 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    status=$(curl -s -o /tmp/health_server_body -w "%{http_code}" "http://127.0.0.1:${port}/healthz")
    printf "status=%s\n" "$status"
    printf "body=%s\n" "$(cat /tmp/health_server_body)"
  '

  assert_success
  assert_output --partial "status=200"
  assert_output --partial "body=ok: stub healthy"
}

@test "health_server.py returns 200 for a degraded probe" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    probe="$BATS_TEST_TMPDIR/probe-degraded.sh"
    cat > "$probe" <<'\''EOF'\''
#!/bin/bash
echo "degraded: rcon connection failed"
exit 0
EOF
    chmod +x "$probe"
    port=18081
    HEALTHCHECK_PORT="$port" HEALTHCHECK_PROBE_SCRIPT="$probe" python3 "$REPO_ROOT/scripts/health_server.py" &
    server_pid=$!
    trap "kill $server_pid 2>/dev/null || true" EXIT
    for _ in $(seq 1 20); do
      if curl -fsS "http://127.0.0.1:${port}/healthz" >/tmp/health_server_body 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    status=$(curl -s -o /tmp/health_server_body -w "%{http_code}" "http://127.0.0.1:${port}/healthz")
    printf "status=%s\n" "$status"
    printf "body=%s\n" "$(cat /tmp/health_server_body)"
  '

  assert_success
  assert_output --partial "status=200"
  assert_output --partial "body=degraded: rcon connection failed"
}

@test "health_server.py returns 503 for an unhealthy probe" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    probe="$BATS_TEST_TMPDIR/probe-fail.sh"
    cat > "$probe" <<'\''EOF'\''
#!/bin/bash
echo "unhealthy: stub failure"
exit 1
EOF
    chmod +x "$probe"
    port=18082
    HEALTHCHECK_PORT="$port" HEALTHCHECK_PROBE_SCRIPT="$probe" python3 "$REPO_ROOT/scripts/health_server.py" &
    server_pid=$!
    trap "kill $server_pid 2>/dev/null || true" EXIT
    for _ in $(seq 1 20); do
      if curl -s "http://127.0.0.1:${port}/healthz" >/tmp/health_server_body 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    status=$(curl -s -o /tmp/health_server_body -w "%{http_code}" "http://127.0.0.1:${port}/healthz")
    printf "status=%s\n" "$status"
    printf "body=%s\n" "$(cat /tmp/health_server_body)"
  '

  assert_success
  assert_output --partial "status=503"
  assert_output --partial "body=unhealthy: stub failure"
}
