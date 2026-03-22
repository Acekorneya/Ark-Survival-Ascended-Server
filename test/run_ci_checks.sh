#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

echo "Running bash syntax checks..."
mapfile -t shell_files < <(git ls-files '*.sh' '*.bash')
for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "Running shell lint..."
  shellcheck_files=(
    scripts/*.sh
    test/run_ci_checks.sh
    test/run_tests.sh
    test/run_integration_checks.sh
    test/run_full_local_validation.sh
    test/integration/docker_smoke.sh
  )
  shellcheck -S error -x "${shellcheck_files[@]}"
else
  echo "Skipping shell lint (shellcheck not installed)."
fi

echo "Running BATS unit tests..."
bash "${SCRIPT_DIR}/run_tests.sh"
