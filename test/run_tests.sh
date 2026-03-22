#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
bash "${SCRIPT_DIR}/bats/bin/bats" "${SCRIPT_DIR}/unit/"*.bats "$@"
