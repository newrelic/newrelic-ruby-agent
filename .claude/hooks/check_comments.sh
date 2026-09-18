#!/usr/bin/env bash
# Stop hook: judges every comment line added during this session against this repo's
# CLAUDE.md comment-discipline rule (WHY only, never WHAT, 1-2 lines), defaulting to removal
# rather than rewording. Blocks the turn from ending if a fresh, context-free `claude -p`
# review finds anything to fix.
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

The default verdict is REMOVE. Deletion is the preferred fix; shortening is a distant second
and is right only for a comment that genuinely must stay but is wordy. Begin from the
assumption that every added comment should go, and spare one only if deleting it would
plausibly lead a competent reader of this code to make a mistake.

A comment survives only if it states a non-obvious WHY the code cannot state itself: a hidden
constraint, a cross-file or ordering dependency, a subtle invariant, a workaround for specific
behavior, or something whose breakage would be silent. \"Useful context\", \"helps the reader
follow along\", and \"explains the design\" are NOT survival reasons -- those are removals.

Report REMOVE (never merely shortening) when the comment:
- restates WHAT the code does, or narrates the obvious
- explains or justifies a change, or reads as commit-message, PR, issue, or task-history content
- repeats what a nearby existing comment, a method name, a constant name, or a test name says
- explains why code is defensive, redundant, or belt-and-braces
- labels or introduces the lines beneath it
- needs more than 2 lines to make its point -- treat the length as evidence it is narrating
  rather than constraining, and remove it instead of compressing it

Ignore the standard 2-line license header, the frozen_string_literal comment, and yardoc
comments for public documentation.

For each added comment that should change, report file, line (from the diff hunk header), the
comment text, and a one-sentence reason that starts with the action: \"remove -- \" plus why it
fails, or, for the rare must-stay-but-wordy case, \"shorten -- \" plus what constraint makes it
load-bearing. When torn between the two, say remove. If every added comment is justified,
return an empty violations array.

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

jq -n --arg reason "Comment-discipline check found comments to fix before finishing. Prefer
deleting a flagged comment over rewording it; only shorten one that is genuinely load-bearing:
$REASON" '{decision: "block", reason: $reason}'
