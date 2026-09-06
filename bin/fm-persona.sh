#!/usr/bin/env bash
# Resolve firstmate's active persona and print its markdown to stdout.
# A persona is a voice-only overlay: it changes how firstmate addresses the user
# and its tone, never safety, accuracy, escalation, or the concise plain-language
# rules. bin/fm-session-start.sh emits the result in the context digest so
# firstmate adopts the voice every session.
#
# Usage: fm-persona.sh [name]
#
# Name source, in order: the [name] argument, else the first non-empty,
# non-comment line of config/persona, else "vader" (the shipped default).
# File resolution, in order: data/personas/<name>.md (the captain's own,
# gitignored), then docs/examples/personas/<name>.md (the shipped examples).
#
# Fail-safe for session start: an unknown, unsafe, or unreadable persona name
# falls back to "vader", then to a built-in one-line default. This never errors
# and always exits 0, so a missing persona means the default voice, never a
# broken digest.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"

DEFAULT_PERSONA=vader

# Print the first non-empty, non-comment line of config/persona (whitespace
# trimmed), or nothing when the file is absent or holds only blank/comment lines.
config_persona() {
  local line
  [ -f "$CONFIG/persona" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    case "$line" in '#'*) continue ;; esac
    printf '%s\n' "$line"
    return 0
  done < "$CONFIG/persona"
}

# Print the persona file for <name> from data/ then docs/examples/, else fail.
# The name must be a plain basename, so a path or traversal resolves nothing.
print_persona_file() {
  local name=$1
  case "$name" in ''|*/*|*..*) return 1 ;; esac
  if [ -r "$DATA/personas/$name.md" ]; then cat "$DATA/personas/$name.md"; return 0; fi
  if [ -r "$FM_ROOT/docs/examples/personas/$name.md" ]; then
    cat "$FM_ROOT/docs/examples/personas/$name.md"; return 0
  fi
  return 1
}

name="${1:-}"
[ -n "$name" ] || name=$(config_persona)
[ -n "$name" ] || name=$DEFAULT_PERSONA

if print_persona_file "$name"; then exit 0; fi
if [ "$name" != "$DEFAULT_PERSONA" ] && print_persona_file "$DEFAULT_PERSONA"; then exit 0; fi
printf 'Default professional voice. Address the user plainly. Keep the concise, plain Simplified Technical English and safety rules.\n'
exit 0
