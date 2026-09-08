#!/usr/bin/env bash
# Behavior tests for the persona voice overlay: bin/fm-persona.sh resolution and
# its inclusion in the session-start context digest. Drives the executable
# interface only; never asserts source bytes.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PERSONA="$ROOT/bin/fm-persona.sh"
SESSION_START="$ROOT/bin/fm-session-start.sh"
TMP_ROOT=$(fm_test_tmproot fm-persona-resolve)
trap fm_test_cleanup EXIT

# A throwaway FM_ROOT git repo on main (so session-start's default-branch and
# worktree checks behave), carrying shipped example personas under
# docs/examples/personas/, plus an empty FM_HOME. Echoes "<root>|<home>".
new_world() {
  local name=$1 root home
  root="$TMP_ROOT/$name/root"
  home="$TMP_ROOT/$name/home"
  mkdir -p "$root/docs/examples/personas" "$home/state" "$home/data/personas" "$home/config"
  git init -q -b main "$root"
  git -C "$root" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m init
  printf '# Persona: plain\nSHIPPED_PLAIN_MARKER\n' > "$root/docs/examples/personas/plain.md"
  printf '# Persona: vader\nSHIPPED_VADER_MARKER\n' > "$root/docs/examples/personas/vader.md"
  printf '%s|%s\n' "$root" "$home"
}

resolve() {
  local root=$1 home=$2
  FM_HOME="$home" FM_ROOT_OVERRIDE="$root" "$PERSONA"
}

digest() {
  local root=$1 home=$2
  FM_HOME="$home" FM_ROOT_OVERRIDE="$root" PATH="/usr/bin:/bin" "$SESSION_START" 2>&1
}

test_resolution() {
  local world root home
  world=$(new_world resolution); root=${world%|*}; home=${world#*|}

  # Absent config/persona yields the default (vader).
  local out
  out=$(resolve "$root" "$home")
  assert_contains "$out" "SHIPPED_VADER_MARKER" "absent config/persona did not yield the default vader persona"

  # A named persona resolves the shipped example, distinct from the default.
  printf 'plain\n' > "$home/config/persona"
  out=$(resolve "$root" "$home")
  assert_contains "$out" "SHIPPED_PLAIN_MARKER" "named persona did not resolve the shipped example"

  # data/personas/<name>.md wins over the shipped example for the same name.
  printf 'LOCAL_PLAIN_MARKER\n' > "$home/data/personas/plain.md"
  out=$(resolve "$root" "$home")
  assert_contains "$out" "LOCAL_PLAIN_MARKER" "data/ persona did not override the shipped example"
  assert_not_contains "$out" "SHIPPED_PLAIN_MARKER" "shipped example leaked when data/ persona exists"

  # Comment and blank lines are skipped; an unknown name falls back to default.
  printf '# comment\n\n   no-such-persona  \n' > "$home/config/persona"
  rm -f "$home/data/personas/plain.md"
  out=$(resolve "$root" "$home")
  assert_contains "$out" "SHIPPED_VADER_MARKER" "unknown persona name did not fall back to the default"

  pass "persona resolution: data over docs/examples, default on absent/unknown"
}

test_digest_includes_active_persona() {
  local world root home out
  world=$(new_world digest); root=${world%|*}; home=${world#*|}

  # With no config, the digest carries the default persona (vader).
  out=$(digest "$root" "$home")
  assert_contains "$out" "SHIPPED_VADER_MARKER" "session-start digest did not include the default persona"

  # A selected persona reaches the digest through the resolver.
  printf 'plain\n' > "$home/config/persona"
  out=$(digest "$root" "$home")
  assert_contains "$out" "SHIPPED_PLAIN_MARKER" "session-start digest did not include the selected persona"

  pass "session-start digest includes the active persona"
}

test_resolution
test_digest_includes_active_persona
