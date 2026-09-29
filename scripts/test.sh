#!/bin/sh
# CCPM Test Launcher
#
# Runs the Lua specs inside a throwaway headless CraftOS-PC computer and prints the results.
#
# Usage: scripts/test.sh [spec filter]
# Set `CRAFTOS` to the CraftOS-PC console executable when it is not on the `PATH` as `craftos`.

set -eu

# MARK: Constants
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
CRAFTOS="${CRAFTOS:-craftos}"
TIMEOUT_SECONDS=300

# MARK: Functions
# Converts a path to the native form CraftOS-PC expects on Windows
native_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

# MARK: Execution
# Create a throwaway computer and output folder
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/data" "$WORK_DIR/out"

# Run the specs, discarding the headless screen output
FILTER="${1:-}"
timeout "$TIMEOUT_SECONDS" "$CRAFTOS" --headless \
    -d "$(native_path "$WORK_DIR/data")" \
    --mount-ro "/src=$(native_path "$REPO_ROOT/src")" \
    --mount-ro "/tests=$(native_path "$REPO_ROOT/tests")" \
    --mount-rw "/out=$(native_path "$WORK_DIR/out")" \
    --exec "shell.run('/tests/run.lua', '/out', '$FILTER') os.shutdown()" \
    >/dev/null 2>&1 || true

# Report the results
if [ ! -f "$WORK_DIR/out/status" ]; then
    echo "CraftOS-PC exited without reporting results." >&2
    exit 1
fi
cat "$WORK_DIR/out/results.txt"
[ "$(cat "$WORK_DIR/out/status")" = "pass" ]
