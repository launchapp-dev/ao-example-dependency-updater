#!/usr/bin/env bash
# scan-outdated.sh — Scans the target repo for outdated packages and security vulnerabilities
# Writes results to data/scan-results.json and data/audit-results.json

set -euo pipefail

# Load target repo config
TARGETS_FILE="config/targets.json"
if [ ! -f "$TARGETS_FILE" ]; then
  echo "ERROR: config/targets.json not found" >&2
  exit 1
fi

TARGET_PATH=$(jq -r '.repos[0].path' "$TARGETS_FILE")
PACKAGE_MANAGER=$(jq -r '.repos[0].package_manager // "npm"' "$TARGETS_FILE")
INCLUDE_DEV=$(jq -r '.scan_options.include_dev // true' "$TARGETS_FILE")

mkdir -p data

echo "Scanning dependencies in: $TARGET_PATH"
echo "Package manager: $PACKAGE_MANAGER"

if [ ! -d "$TARGET_PATH" ]; then
  echo "ERROR: Target repo path '$TARGET_PATH' does not exist." >&2
  echo "Update config/targets.json with the correct path to your repository." >&2
  # Write empty scan results so classify-updates can detect the issue
  echo '{"error": "target_repo_not_found", "path": "'"$TARGET_PATH"'", "packages": {}}' > data/scan-results.json
  echo '{"error": "target_repo_not_found", "vulnerabilities": {}}' > data/audit-results.json
  exit 0
fi

cd "$TARGET_PATH"

# Run npm outdated (exits non-zero when outdated packages exist — capture output regardless)
echo "Running npm outdated..."
if [ "$INCLUDE_DEV" = "true" ]; then
  npm outdated --json 2>/dev/null > "$OLDPWD/data/scan-results.json" || true
else
  npm outdated --json --prod 2>/dev/null > "$OLDPWD/data/scan-results.json" || true
fi

# If outdated returned nothing, write empty object
if [ ! -s "$OLDPWD/data/scan-results.json" ]; then
  echo '{}' > "$OLDPWD/data/scan-results.json"
fi

# Run npm audit (exits non-zero when vulnerabilities exist — capture regardless)
echo "Running npm audit..."
npm audit --json 2>/dev/null > "$OLDPWD/data/audit-results.json" || true

if [ ! -s "$OLDPWD/data/audit-results.json" ]; then
  echo '{"vulnerabilities": {}, "metadata": {"vulnerabilities": {"total": 0}}}' > "$OLDPWD/data/audit-results.json"
fi

OUTDATED_COUNT=$(jq 'keys | length' "$OLDPWD/data/scan-results.json" 2>/dev/null || echo 0)
echo "Scan complete. Found $OUTDATED_COUNT outdated packages."
echo "Scan results written to data/scan-results.json"
echo "Audit results written to data/audit-results.json"
