#!/usr/bin/env bash
# tests/fm-backend-tmux-smoke.test.sh - real tmux smoke test for the tmux
# session-provider adapter (bin/backends/tmux.sh), the P1 checklist item
# "run a real tmux smoke test (create session, send text + Enter, capture,
# list, kill)" from data/fm-backend-design-d7/report.md. Every other suite in
# this repo fakes tmux; this one is the one place that talks to a REAL tmux
# server, isolated on a private socket (`-L`) so it never touches the host's
# actual sessions.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'not ok - %s\n' "$1" >&2; cleanup_all; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

wait_for_capture_text() {  # <target> <text> [samples]
  local target=$1 text=$2 samples=${3:-100} out i=0
  while [ "$i" -lt "$samples" ]; do
    out=$(fm_backend_tmux_capture "$target" 200 2>/dev/null || true)
    case "$out" in
      *"$text"*) return 0 ;;
    esac
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

command -v tmux >/dev/null 2>&1 || { echo "skip: tmux not found"; exit 0; }
REAL_TMUX=$(command -v tmux)
SOCKET="fm-backend-smoke-$$"
SHIM_DIR=
trap cleanup_all EXIT

cleanup_all() {
  "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ -n "${SHIM_DIR:-}" ] && rm -rf "$SHIM_DIR"
}

# A `tmux` shim on PATH that transparently redirects every call to the private
# socket, so bin/backends/tmux.sh's bare `tmux ...` invocations never touch the
# host's real sessions.
SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-backend-smoke.XXXXXX")
cat > "$SHIM_DIR/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SH
chmod +x "$SHIM_DIR/tmux"
PATH="$SHIM_DIR:$PATH"
export PATH

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
fm_backend_source tmux || fail "fm_backend_source tmux failed"

SESSION="smoke"
WINDOW="fm-smoke1"
TARGET="$SESSION:$WINDOW"

# --- create session ----------------------------------------------------------

tmux new-session -d -s "$SESSION" -x 200 -y 50 \
  || fail "real tmux: new-session failed"
fm_backend_tmux_create_task "$SESSION" "$WINDOW" "$HOME" \
  || fail "fm_backend_tmux_create_task failed to create the task window"
tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -qx "$WINDOW" \
  || fail "created window is not visible in the real session"

# A second create for the SAME window name must refuse (mirrors fm-spawn.sh's
# duplicate-window guard).
if fm_backend_tmux_create_task "$SESSION" "$WINDOW" "$HOME" 2>/dev/null; then
  fail "fm_backend_tmux_create_task should refuse an existing window name"
fi
pass "real tmux: fm_backend_tmux_create_task creates a window and refuses a duplicate"

# --- send text + Enter -------------------------------------------------------

# A newly-created interactive shell can exist before its startup files and line
# editor are ready to accept Enter. Prove command execution with an output token
# that does not appear contiguously in the command, retrying the harmless probe
# until the shell acknowledges it.
SHELL_READY=false
for _ in $(seq 1 100); do
  tmux send-keys -t "$TARGET" C-c
  tmux send-keys -t "$TARGET" -l "printf 'shell-%s\\n' ready"
  tmux send-keys -t "$TARGET" Enter
  if wait_for_capture_text "$TARGET" "shell-ready" 10; then
    SHELL_READY=true
    break
  fi
done
[ "$SHELL_READY" = true ] || fail "the tmux task shell did not become ready"

tmux send-keys -t "$TARGET" "cd /tmp && PS1='smoke\$ ' && clear && printf 'setup-%s\\n' ready" Enter
wait_for_capture_text "$TARGET" "setup-ready" || fail "the tmux task shell did not complete setup"

fm_backend_tmux_send_text_line "$TARGET" "printf 'captain-on-deck-%s\\n' line" \
  || fail "fm_backend_tmux_send_text_line failed"
wait_for_capture_text "$TARGET" "captain-on-deck-line" \
  || fail "fm_backend_tmux_send_text_line did not execute"
out=$(fm_backend_tmux_capture "$TARGET" 20) || fail "fm_backend_tmux_capture failed after send_text_line"
case "$out" in
  *captain-on-deck-line*) : ;;
  *) fail "real tmux: fm_backend_tmux_send_text_line did not submit and echo the line"$'\n'"$out" ;;
esac
pass "real tmux: fm_backend_tmux_send_text_line sends literal text and submits with Enter"

# --- send_literal + send_key(Enter), the two-step form fm-spawn.sh uses for the
# harness launch command (literal send, settle, then a separate Enter) --------

fm_backend_tmux_send_literal "$TARGET" "printf 'literal-then-key-%s\\n' captain" \
  || fail "fm_backend_tmux_send_literal failed"
fm_backend_tmux_send_key "$TARGET" Enter || fail "fm_backend_tmux_send_key Enter failed"
wait_for_capture_text "$TARGET" "literal-then-key-captain" \
  || fail "fm_backend_tmux_send_literal + fm_backend_tmux_send_key Enter did not execute"
out=$(fm_backend_tmux_capture "$TARGET" 20) || fail "fm_backend_tmux_capture failed after send_literal+send_key"
case "$out" in
  *literal-then-key-captain*) : ;;
  *) fail "real tmux: send_literal + send_key(Enter) did not submit and echo the line"$'\n'"$out" ;;
esac
pass "real tmux: fm_backend_tmux_send_literal + fm_backend_tmux_send_key Enter submit as two separate steps"

# --- capture bounds -----------------------------------------------------------
# Print enough numbered lines to overflow the pane's visible height, then
# confirm a small capture window (-S -N) surfaces only the RECENT tail (the
# earliest lines scroll out of a small window) while a large one reaches back
# far enough to still see the earliest line - the same -S -N bounding fm-peek.sh
# and fm-watch.sh rely on for a bounded, cheap pane read.
fm_backend_tmux_send_text_line "$TARGET" "for i in \$(seq 1 80); do echo tag-line-\$i; done"
wait_for_capture_text "$TARGET" "tag-line-80" \
  || fail "the numbered output did not complete before capture"
small=$(fm_backend_tmux_capture "$TARGET" 3) || fail "fm_backend_tmux_capture (small window) failed"
case "$small" in
  *tag-line-1$'\n'*) fail "a 3-line capture should not still see the very first numbered line"$'\n'"$small" ;;
esac
case "$small" in
  *tag-line-80*) : ;;
  *) fail "a 3-line capture should still contain the most recent output"$'\n'"$small" ;;
esac
large=$(fm_backend_tmux_capture "$TARGET" 200) || fail "fm_backend_tmux_capture (large window) failed"
case "$large" in
  *tag-line-1$'\n'*) : ;;
  *) fail "a 200-line capture should reach back far enough to see the first numbered line"$'\n'"$large" ;;
esac
pass "real tmux: fm_backend_tmux_capture's -S -N bound trims old history for a small window and reaches it for a large one"

# --- resolve_bare_selector (live-window-listing) -----------------------------

resolved=$(fm_backend_tmux_resolve_bare_selector "$WINDOW") \
  || fail "fm_backend_tmux_resolve_bare_selector failed to find the live window"
[ "$resolved" = "$TARGET" ] || fail "fm_backend_tmux_resolve_bare_selector resolved to '$resolved', expected '$TARGET'"
pass "real tmux: fm_backend_tmux_resolve_bare_selector (list-live) finds the created window by name"

if fm_backend_tmux_resolve_bare_selector "no-such-window-xyz" 2>/dev/null; then
  fail "fm_backend_tmux_resolve_bare_selector should fail for a nonexistent window"
fi
pass "real tmux: fm_backend_tmux_resolve_bare_selector fails for a window that does not exist"

# --- resolve_bare_selector matches a hook-renamed window by its bare name -----
# A Claude hook renames each task window to "fm-<task>: <rich title>", so the
# bare fm-<task> selector must still resolve after the title lands.
tmux rename-window -t "$TARGET" "$WINDOW: shipping the thing" \
  || fail "could not rename the window to its rich title"
resolved=$(fm_backend_tmux_resolve_bare_selector "$WINDOW") \
  || fail "fm_backend_tmux_resolve_bare_selector failed to find the renamed window by its bare name"
[ "$resolved" = "$SESSION:$WINDOW: shipping the thing" ] \
  || fail "resolve after rename returned '$resolved', expected '$SESSION:$WINDOW: shipping the thing'"
pass "real tmux: fm_backend_tmux_resolve_bare_selector finds a 'fm-<task>: <title>' window by its bare name"
# tmux resolves a -t target by prefix, so $TARGET restores the bare name.
tmux rename-window -t "$TARGET" "$WINDOW" || fail "could not restore the window name"

# The prefix must not widen into a substring: only fm-orphan-2 exists, so the
# bare selector fm-orphan must not match it.
tmux new-window -d -t "$SESSION:" -n "fm-orphan-2" -c "$HOME" \
  || fail "could not create the suffixed sibling window"
if fm_backend_tmux_resolve_bare_selector "fm-orphan" 2>/dev/null; then
  fail "resolve must not match an unrelated fm-orphan-2 window from the bare selector fm-orphan"
fi
pass "real tmux: fm_backend_tmux_resolve_bare_selector does not over-match a suffixed sibling"
tmux kill-window -t "=$SESSION:=fm-orphan-2" 2>/dev/null || true

# --- kill and recovery-grade missing-window classification ------------------

fm_backend_tmux_kill "$TARGET"
if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$WINDOW"; then
  fail "fm_backend_tmux_kill did not remove the window"
fi
state=$(fm_backend_agent_state tmux "$TARGET")
[ "$state" = missing ] \
  || fail "a real missing window in a readable session should classify as missing, got '$state'"
# Best-effort contract: killing an already-gone window must not error.
fm_backend_tmux_kill "$TARGET" || fail "fm_backend_tmux_kill on an already-dead target must stay best-effort (never fail)"
pass "real tmux: kill removes the window and the readable session inventory authoritatively classifies it missing"

# --- container_ensure launches ghostty before creating a NEW session ---------
# The first window in a new session must have a ghostty terminal around it, so
# the new-session path launches ghostty (which creates the tmux session inside
# its shell) instead of a terminal-less detached session. A real ghostty binary
# is a GUI app, so this proves the behavior through an FM_GHOSTTY stub that
# records its invocation and stands the session up on the private socket.
GHOSTTY_MARKER="$SHIM_DIR/ghostty-invoked"
cat > "$SHIM_DIR/ghostty-stub" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GHOSTTY_MARKER"
# Emulate ghostty running its '-e tmux new-session -A -s <ses>' command, but
# detached so this headless test needs no controlling terminal.
exec "$REAL_TMUX" -L "$SOCKET" new-session -d -s "\${@: -1}"
SH
chmod +x "$SHIM_DIR/ghostty-stub"

tmux kill-session -t firstmate 2>/dev/null || true
ensured=$(TMUX='' FM_GHOSTTY="$SHIM_DIR/ghostty-stub" fm_backend_tmux_container_ensure) \
  || fail "container_ensure failed on the new-session path"
[ "$ensured" = firstmate ] || fail "container_ensure returned '$ensured', expected 'firstmate'"
[ -f "$GHOSTTY_MARKER" ] || fail "the new-session path did not launch ghostty first"
tmux has-session -t firstmate 2>/dev/null \
  || fail "container_ensure did not establish the tmux session inside the ghostty step"
pass "real tmux: container_ensure launches ghostty first, then the tmux session exists"

# An already-present session is only attached, never recreated: no second launch.
: > "$GHOSTTY_MARKER"
ensured=$(TMUX='' FM_GHOSTTY="$SHIM_DIR/ghostty-stub" fm_backend_tmux_container_ensure) \
  || fail "container_ensure failed when the session already exists"
[ "$ensured" = firstmate ] \
  || fail "container_ensure returned '$ensured' for an existing session, expected 'firstmate'"
[ ! -s "$GHOSTTY_MARKER" ] \
  || fail "container_ensure relaunched ghostty for an already-present session"
pass "real tmux: container_ensure reuses an existing session without relaunching ghostty"
tmux kill-session -t firstmate 2>/dev/null || true

# The new-session path falls back to a detached session when ghostty is absent,
# so session creation still succeeds on a headless host.
tmux kill-session -t firstmate 2>/dev/null || true
ensured=$(TMUX='' FM_GHOSTTY="no-such-ghostty-binary-xyz" fm_backend_tmux_container_ensure) \
  || fail "container_ensure failed to fall back when ghostty is absent"
[ "$ensured" = firstmate ] \
  || fail "container_ensure fallback returned '$ensured', expected 'firstmate'"
tmux has-session -t firstmate 2>/dev/null \
  || fail "container_ensure did not create the detached session when ghostty is absent"
pass "real tmux: container_ensure falls back to a detached session when ghostty is unavailable"
tmux kill-session -t firstmate 2>/dev/null || true

# A present ghostty that cannot open a window (a display-less or SSH host) exits
# without creating the session. The readiness poll must notice that exit and
# fall back at once, not wait out the whole budget. A large sample budget makes
# a stall obvious: with a 30s budget, a fast fallback proves the exit is caught.
cat > "$SHIM_DIR/ghostty-noshow" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SHIM_DIR/ghostty-noshow-invoked"
exit 1
SH
chmod +x "$SHIM_DIR/ghostty-noshow"
tmux kill-session -t firstmate 2>/dev/null || true
start=$(date +%s)
ensured=$(TMUX='' FM_GHOSTTY="$SHIM_DIR/ghostty-noshow" FM_GHOSTTY_SESSION_WAIT_SAMPLES=300 \
  fm_backend_tmux_container_ensure) \
  || fail "container_ensure failed when ghostty cannot open a window"
elapsed=$(( $(date +%s) - start ))
[ "$ensured" = firstmate ] \
  || fail "container_ensure returned '$ensured' after a ghostty that cannot open a window"
[ -f "$SHIM_DIR/ghostty-noshow-invoked" ] || fail "the ghostty step was not attempted"
tmux has-session -t firstmate 2>/dev/null \
  || fail "container_ensure did not fall back to a detached session after ghostty failed to open"
[ "$elapsed" -lt 10 ] \
  || fail "container_ensure stalled ${elapsed}s waiting out the poll budget instead of catching the ghostty exit"
pass "real tmux: container_ensure falls back at once when a present ghostty cannot open a window"
tmux kill-session -t firstmate 2>/dev/null || true

# --- container_ensure names the session after the project, ghostty-first -----
# One session per project: the name is the project directory basename,
# sanitized to tmux's allowed set ("." becomes "-"). The per-project NEW-session
# path must still go through ghostty first, so grouping and ghostty-first order
# hold together rather than one replacing the other.
: > "$GHOSTTY_MARKER"
tmux kill-session -t my-project 2>/dev/null || true
ensured=$(TMUX='' FM_GHOSTTY="$SHIM_DIR/ghostty-stub" fm_backend_tmux_container_ensure "/tmp/x/my.project") \
  || fail "container_ensure failed on the per-project new-session path"
[ "$ensured" = my-project ] \
  || fail "container_ensure returned '$ensured', expected the sanitized project slug 'my-project'"
grep -q 'my-project' "$GHOSTTY_MARKER" \
  || fail "the per-project new-session path did not launch ghostty for the project session"
tmux has-session -t my-project 2>/dev/null \
  || fail "container_ensure did not establish the project session inside the ghostty step"
pass "real tmux: container_ensure names the session after the project and creates it ghostty-first"
tmux kill-session -t my-project 2>/dev/null || true

cleanup_all
trap - EXIT
