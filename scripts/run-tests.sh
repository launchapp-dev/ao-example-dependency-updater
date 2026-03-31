#!/usr/bin/env bash
# run-tests.sh — Runs the test suite for the target repo after dependency updates
# Writes stdout/stderr to data/test-output.txt and exit code to data/test-result.json

set -uo pipefail

TARGETS_FILE="config/targets.json"
if [ ! -f "$TARGETS_FILE" ]; then
  echo "ERROR: config/targets.json not found" >&2
  exit 1
fi

TARGET_PATH=$(jq -r '.repos[0].path' "$TARGETS_FILE")
TEST_CMD=$(jq -r '.repos[0].test_command // "npm test"' "$TARGETS_FILE")

mkdir -p data

if [ ! -d "$TARGET_PATH" ]; then
  echo "ERROR: Target repo path '$TARGET_PATH' does not exist." >&2
  echo '{"exit_code": 1, "error": "target_repo_not_found"}' > data/test-result.json
  echo "Target repo not found: $TARGET_PATH" > data/test-output.txt
  exit 0
fi

cd "$TARGET_PATH"

# Install dependencies first (after package.json was updated by the updater agent)
echo "Installing dependencies..."
npm install 2>&1 | tee "$OLDPWD/data/install-output.txt" || {
  echo "npm install failed" >&2
  echo '{"exit_code": 1, "error": "npm_install_failed"}' > "$OLDPWD/data/test-result.json"
  echo "npm install failed. See data/install-output.txt" > "$OLDPWD/data/test-output.txt"
  cat "$OLDPWD/data/install-output.txt" >> "$OLDPWD/data/test-output.txt"
  exit 0
}

# Run the test command, capturing all output
echo "Running: $TEST_CMD"
set +e
$TEST_CMD 2>&1 | tee "$OLDPWD/data/test-output.txt"
EXIT_CODE=${PIPESTATUS[0]}
set -e

echo "Test exit code: $EXIT_CODE"
echo "{\"exit_code\": $EXIT_CODE, \"test_command\": \"$TEST_CMD\", \"ran_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$OLDPWD/data/test-result.json"

echo "Test output written to data/test-output.txt"
echo "Test result written to data/test-result.json"

# Exit 0 even if tests failed — the analyze-test-results agent handles classification
exit 0
