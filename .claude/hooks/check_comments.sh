#!/usr/bin/env bash
# Stop hook: judges every comment line added during this session against this repo's
# CLAUDE.md comment-discipline rule (WHY only, never WHAT, 1-2 lines). Blocks the turn from
# ending if a fresh, context-free `claude -p` review finds anything to fix.
set -euo pipefail

# Guard against the nested `claude -p` judge call below re-triggering this same hook.
if [ -n "${CLAUDE_COMMENT_CHECK_RUNNING:-}" ]; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi
cd "$REPO_ROOT"

DIFF="$(git diff HEAD --unified=2 -- '*.rb' 2>/dev/null || true)"
if [ -z "$DIFF" ]; then
  exit 0
fi

# Fast pre-check: skip the (expensive) judge call entirely if nothing added is a comment.
# Excludes the standard two-line license header and the frozen_string_literal magic comment.
ADDED_COMMENTS="$(echo "$DIFF" | grep -E '^\+\s*#' \
  | grep -Ev '^\+\s*# This file is distributed|^\+\s*# See https://github|^\+\s*# frozen_string_literal: true' \
  || true)"
if [ -z "$ADDED_COMMENTS" ]; then
  exit 0
fi

PROMPT="Review ONLY the added lines (prefixed with +) in this git diff for Ruby comments.
Rule: a comment is only justified if it states a non-obvious WHY (a hidden constraint, a 
subtle invariant, a workaround, surprising behavior) that a reader could not get from the 
code itself. Never justified: restating WHAT the code does, referencing PR/issue numbers 
or task history, or exceeding 2 lines when a shorter version would do. If a comment doesn't 
need to be there, remove it. 
Ignore the standard 2-line license header and frozen_string_literal comment, and any yardoc 
comments for public documentation.

For each added comment that violates the rule, report file, line (from the diff hunk
header), the comment text, and a one-sentence reason. If every added comment is fine,
say so explicitly.

Respond with ONLY a JSON object, no markdown fences, no other text, matching exactly:
{\"violations\": [{\"file\": \"...\", \"line\": ..., \"comment\": \"...\", \"reason\": \"...\"}]}
An empty violations array means everything passed.

Diff:
$DIFF"

# --bare would skip auth (keychain/OAuth) along with hooks, so recursion is prevented by the
# CLAUDE_COMMENT_CHECK_RUNNING guard at the top of this script instead.
RESULT="$(CLAUDE_COMMENT_CHECK_RUNNING=1 claude -p "$PROMPT" 2>/dev/null || true)"
RESULT="$(echo "$RESULT" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//')"

VIOLATION_COUNT="$(echo "$RESULT" | jq -r '.violations | length' 2>/dev/null || echo "0")"

if ! echo "$VIOLATION_COUNT" | grep -qE '^[0-9]+$'; then
  # Judge call failed or returned unparseable output -- fail open rather than block forever.
  exit 0
fi

if [ "$VIOLATION_COUNT" -eq 0 ]; then
  exit 0
fi

REASON="$(echo "$RESULT" | jq -r '.violations[] | "- \(.file):\(.line) — \(.comment | tostring) — \(.reason)"' 2>/dev/null || true)"

jq -n --arg reason "Comment-discipline check found issues to fix before finishing:
$REASON" '{decision: "block", reason: $reason}'
