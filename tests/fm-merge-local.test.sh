#!/usr/bin/env bash
# Tests for bin/fm-merge-local.sh branch resolution.
#
# The approved local landing must fast-forward the project's default branch to the
# worker's branch. The branch name comes from branch= in state/<id>.meta (firstmate
# sets it at intake); a task whose meta has no branch= falls back to the legacy
# fm/<id> name so work already in flight keeps landing.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

MERGE_LOCAL="$ROOT/bin/fm-merge-local.sh"
TMP_ROOT=$(fm_test_tmproot fm-merge-local)

# Build a project on a clean default branch with <branch> one commit ahead, ready
# for a fast-forward landing.
make_merge_case() {
  local name=$1 branch=$2 case_dir
  case_dir="$TMP_ROOT/$name"
  mkdir -p "$case_dir/state"

  git init -q --bare "$case_dir/origin.git"
  git -C "$case_dir/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$case_dir/origin.git" "$case_dir/project"
  printf 'base\n' > "$case_dir/project/f.txt"
  git -C "$case_dir/project" add f.txt
  git -C "$case_dir/project" -c user.email=t@t -c user.name=t commit -qm baseline
  git -C "$case_dir/project" push -q origin main
  git -C "$case_dir/project" remote set-head origin main 2>/dev/null || true

  git -C "$case_dir/project" checkout -q -b "$branch"
  printf 'change\n' >> "$case_dir/project/f.txt"
  git -C "$case_dir/project" add f.txt
  git -C "$case_dir/project" -c user.email=t@t -c user.name=t commit -qm "ready change"
  git -C "$case_dir/project" checkout -q main

  touch "$case_dir/state/.last-watcher-beat"
  printf '%s\n' "$case_dir"
}

run_merge_local() {
  local case_dir=$1
  shift
  FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$case_dir/state" \
    "$MERGE_LOCAL" "$@"
}

# branch= in meta names a non-fm branch; the landing must resolve it.
test_meta_branch_is_resolved() {
  local case_dir out status
  case_dir=$(make_merge_case meta-branch jeffrydegrande/feat-x)
  fm_write_meta "$case_dir/state/task-m1.meta" \
    "project=$case_dir/project" \
    "mode=local-only" \
    "branch=jeffrydegrande/feat-x"

  out=$(run_merge_local "$case_dir" task-m1 2>&1); status=$?
  expect_code 0 "$status" "landing should fast-forward the recorded branch"$'\n'"$out"
  assert_contains "$out" "merged jeffrydegrande/feat-x into local main" \
    "landing did not merge the recorded branch"
  pass "fm-merge-local.sh resolves branch= from meta"
}

# No branch= in meta: fall back to the legacy fm/<id> name.
test_absent_branch_falls_back_to_fm_id() {
  local case_dir out status
  case_dir=$(make_merge_case fallback-branch fm/task-m2)
  fm_write_meta "$case_dir/state/task-m2.meta" \
    "project=$case_dir/project" \
    "mode=local-only"

  out=$(run_merge_local "$case_dir" task-m2 2>&1); status=$?
  expect_code 0 "$status" "landing should fall back to fm/<id> when meta has no branch="$'\n'"$out"
  assert_contains "$out" "merged fm/task-m2 into local main" \
    "landing did not fall back to the legacy fm/<id> branch"
  pass "fm-merge-local.sh falls back to fm/<id> when meta has no branch="
}

test_meta_branch_is_resolved
test_absent_branch_falls_back_to_fm_id
