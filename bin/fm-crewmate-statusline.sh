#!/usr/bin/env bash
# Render the Claude status line for a firstmate crewmate or scout session.
# bin/fm-spawn.sh wires this as the "statusLine" command for ship and scout
# claude launches only, never for the primary firstmate session or a secondmate
# home (a secondmate is a firstmate in its own home). It prints one loud red
# banner so a worker window is never mistaken for the captain's own firstmate
# session, then a light branch context after it.
# Usage: fm-crewmate-statusline.sh <task-id>
# Claude sends the session JSON on stdin; this reader drains and ignores it.
set -euo pipefail

id=${1:-?}

# Drain and discard the session JSON Claude sends on stdin. The banner needs none
# of it, and an unread pipe can surface as a broken-pipe error in the harness.
cat >/dev/null 2>&1 || true

# Current branch as light context after the banner; silent outside a repo. The
# status-line command runs in the worker's project directory, so a bare git call
# reports that worktree's branch.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

esc=$(printf '\033')
# Bold bright-white text on a red background: unmistakable against the dark theme.
banner="${esc}[1;97;41m ⚠ CREWMATE ${id} ${esc}[0m"
if [ -n "$branch" ]; then
  printf '%s %s(%s)%s\n' "$banner" "${esc}[2m" "$branch" "${esc}[0m"
else
  printf '%s\n' "$banner"
fi
