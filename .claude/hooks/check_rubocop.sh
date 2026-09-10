#!/usr/bin/env bash
# Stop hook: runs rubocop against every .rb file changed this session and blocks
# the turn from ending if any offenses are reported.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi
cd "$REPO_ROOT"

EXISTING_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && EXISTING_FILES+=("$f")
done < <(git diff HEAD --name-only --diff-filter=ACMR -- '*.rb' 2>/dev/null || true)
if [ "${#EXISTING_FILES[@]}" -eq 0 ]; then
  exit 0
fi

set +e
RESULT="$(bundle exec rubocop --format simple "${EXISTING_FILES[@]}" 2>&1)"
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  exit 0
fi

jq -n --arg reason "Rubocop check found issues to fix before finishing:
$RESULT" '{decision: "block", reason: $reason}'
