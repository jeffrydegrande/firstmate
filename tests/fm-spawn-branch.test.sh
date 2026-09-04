#!/usr/bin/env bash
# Behavior tests for fm-spawn.sh branch recording.
#
# Firstmate sets each ship task's branch at intake. fm-brief.sh writes it into the
# brief's Setup step ("git checkout -b <name>"); the spawn records it as branch= in
# state/<id>.meta so the landing and review helpers resolve the real branch. Without
# --branch, the spawn reads the branch back from the brief. A --branch flag that
# disagrees with the brief is a refusal, and --branch is refused on scout spawns.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

TMP_ROOT=$(fm_test_tmproot fm-spawn-branch)

# Replace the scaffold's {TASK}/{FIRSTMATE_SPEC} placeholders with real content so
# the spawn's placeholder guard passes. Portable (no sed -i) for stock macOS Bash.
fill_brief_placeholders() {  # <brief>
  local brief=$1 tmp
  tmp="$brief.fill"
  sed -e 's/^{TASK}$/Exercise the branch behavior under test./' \
      -e 's/^{FIRSTMATE_SPEC}$/Verify the recorded branch matches the brief./' \
      "$brief" > "$tmp"
  mv "$tmp" "$brief"
}

# Build a home with a real worktree and a real ship brief scaffolded for <branch>.
# The brief carries the Delivery contract line and the Setup checkout the spawn
# reads. Echoes: case_dir|home|proj|wt|fakebin
make_branch_case() {
  local name=$1 id=$2 branch=$3 case_dir home proj wt fakebin
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" codex
  fm_git_worktree "$proj" "$wt" "wt-$name"
  if [ -n "$branch" ]; then
    FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" "$proj" --mode local-only --branch "$branch" >/dev/null 2>&1 \
      || { echo "make_branch_case: brief scaffold failed" >&2; return 1; }
  else
    FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" "$proj" --mode local-only >/dev/null 2>&1 \
      || { echo "make_branch_case: default brief scaffold failed" >&2; return 1; }
  fi
  fill_brief_placeholders "$home/data/$id/brief.md"
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin"
}

# Scaffold a scout brief so a scout spawn can be attempted.
make_scout_case() {
  local name=$1 id=$2 case_dir home proj wt fakebin
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" codex
  fm_git_worktree "$proj" "$wt" "wt-$name"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" "$proj" --scout >/dev/null 2>&1 \
    || { echo "make_scout_case: scout brief scaffold failed" >&2; return 1; }
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin"
}

read_case() {
  IFS='|' read -r CASE_DIR HOME_DIR PROJ_DIR WT_DIR FAKEBIN <<EOF
$1
EOF
}

# A spawn without --branch records the branch the brief tells the worker to create.
test_spawn_records_brief_branch_without_flag() {
  local rec out status meta
  rec=$(make_branch_case brief-branch spawn-br-a1 jeffrydegrande/feat-x) || fail "case setup failed"
  read_case "$rec"
  out=$(fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" spawn-br-a1 "$PROJ_DIR" --mode local-only --yolo off)
  status=$?
  expect_code 0 "$status" "spawn without --branch should succeed"$'\n'"$out"
  meta="$HOME_DIR/state/spawn-br-a1.meta"
  assert_grep "branch=jeffrydegrande/feat-x" "$meta" "spawn did not record the brief's branch in meta"
  pass "fm-spawn.sh: a spawn without --branch records the brief's branch"
}

# A spawn with --branch records that branch (the brief must agree).
test_spawn_flag_records_branch() {
  local rec out status meta
  rec=$(make_branch_case flag-branch spawn-br-b1 jeffrydegrande/feat-y) || fail "case setup failed"
  read_case "$rec"
  out=$(fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" spawn-br-b1 "$PROJ_DIR" \
    --mode local-only --yolo off --branch jeffrydegrande/feat-y)
  status=$?
  expect_code 0 "$status" "spawn with matching --branch should succeed"$'\n'"$out"
  meta="$HOME_DIR/state/spawn-br-b1.meta"
  assert_grep "branch=jeffrydegrande/feat-y" "$meta" "spawn did not record --branch in meta"
  pass "fm-spawn.sh: a spawn with --branch records that branch"
}

# The legacy default: a brief scaffolded without --branch names fm/<id>, and the
# spawn records that, so an old caller keeps working.
test_spawn_records_default_fm_branch() {
  local rec out status meta
  rec=$(make_branch_case default-branch spawn-br-c1 "") || fail "case setup failed"
  read_case "$rec"
  out=$(fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" spawn-br-c1 "$PROJ_DIR" --mode local-only --yolo off)
  status=$?
  expect_code 0 "$status" "spawn of a default-branch brief should succeed"$'\n'"$out"
  meta="$HOME_DIR/state/spawn-br-c1.meta"
  assert_grep "branch=fm/spawn-br-c1" "$meta" "spawn did not record the legacy fm/<id> branch"
  pass "fm-spawn.sh: a spawn records the brief's legacy fm/<id> branch"
}

# A --branch that disagrees with the brief's Setup branch is refused, the same
# drift guard the delivery-mode line uses.
test_spawn_branch_mismatch_is_refused() {
  local rec out status
  rec=$(make_branch_case mismatch-branch spawn-br-d1 jeffrydegrande/feat-x) || fail "case setup failed"
  read_case "$rec"
  out=$(fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" spawn-br-d1 "$PROJ_DIR" \
    --mode local-only --yolo off --branch jeffrydegrande/other)
  status=$?
  [ "$status" -ne 0 ] || fail "branch mismatch should refuse the spawn"$'\n'"$out"
  assert_contains "$out" "branch mismatch" "mismatch refusal did not explain the drift"
  assert_absent "$HOME_DIR/state/spawn-br-d1.meta" "refused spawn still wrote task meta"
  pass "fm-spawn.sh: a --branch disagreeing with the brief is refused"
}

# --branch applies only to ship spawns.
test_spawn_branch_refused_on_scout() {
  local rec out status
  rec=$(make_scout_case scout-branch spawn-br-e1) || fail "scout case setup failed"
  read_case "$rec"
  out=$(fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" spawn-br-e1 "$PROJ_DIR" --scout --branch foo)
  status=$?
  [ "$status" -ne 0 ] || fail "scout spawn with --branch should refuse"$'\n'"$out"
  assert_contains "$out" "--branch applies only to ship spawns" "scout refusal did not explain why"
  pass "fm-spawn.sh: --branch is refused on scout spawns"
}

test_spawn_records_brief_branch_without_flag
test_spawn_flag_records_branch
test_spawn_records_default_fm_branch
test_spawn_branch_mismatch_is_refused
test_spawn_branch_refused_on_scout
