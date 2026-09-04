#!/usr/bin/env bash
# tests/fm-crewmate-statusline.test.sh - a claude crewmate or scout launch must
# carry the dark-daltonized theme and the CREWMATE status-line banner so a worker
# window can never be mistaken for the captain's own firstmate session. A
# secondmate is a firstmate in its own home (primary there), so it must NOT get
# the banner. fm-spawn never launches the captain's primary firstmate at all, so
# the secondmate is the only fm-spawn kind that runs as a primary and is the
# correct negative for the "primary path does not" guarantee.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
STATUSLINE="$ROOT/bin/fm-crewmate-statusline.sh"
HELPER_BASENAME="fm-crewmate-statusline.sh"
TMP_ROOT=$(fm_test_tmproot fm-crewmate-statusline)

# --- launch-command settings injection (ship + scout) ----------------------

# Build a spawn world with a claude crew harness. Echoes home|proj|wt|fakebin|launchlog|id.
make_case() {
  local name=$1 case_dir home proj wt fakebin launchlog id
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  launchlog="$case_dir/launch.log"
  fakebin=$(make_spawn_fakebin "$case_dir/fake" gh-axi gh)
  id="$name-x1"
  fm_test_spawn_home "$home" claude
  printf '%s\n' "$$" > "$home/state/.lock"
  fm_test_spawn_brief "$home" "$id"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  printf '%s\n' "$home|$proj|$wt|$fakebin|$launchlog|$id"
}

# Grep the captured launch command (its `claude` line) into a variable.
claude_launch_line() {
  grep 'claude --dangerously-skip-permissions' "$1" | tail -1
}

test_ship_launch_carries_theme_and_banner() {
  local rec home proj wt fakebin launchlog id out line
  rec=$(make_case ship)
  IFS='|' read -r home proj wt fakebin launchlog id <<EOF
$rec
EOF
  : > "$launchlog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" \
    fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$proj" --mode no-mistakes --yolo off)
  assert_contains "$out" "spawned $id harness=claude kind=ship" "ship spawn did not report success"
  line=$(claude_launch_line "$launchlog")
  assert_contains "$line" '"theme":"dark-daltonized"' "a claude crewmate must launch with the dark-daltonized theme"
  assert_contains "$line" '"statusLine"' "a claude crewmate must launch with a statusLine banner"
  assert_contains "$line" "$HELPER_BASENAME" "the statusLine must run the crewmate banner helper"
  assert_contains "$line" "$id" "the statusLine banner must carry the task id"
  assert_contains "$line" '"feedbackDrafts":"off"' "a claude crewmate must keep the feedbackDrafts control"
  pass "a claude crewmate launch carries the theme and the CREWMATE banner"
}

test_scout_launch_carries_theme_and_banner() {
  local rec home proj wt fakebin launchlog id out line
  rec=$(make_case scout)
  IFS='|' read -r home proj wt fakebin launchlog id <<EOF
$rec
EOF
  : > "$launchlog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" \
    fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$proj" --scout)
  assert_contains "$out" "spawned $id harness=claude kind=scout" "scout spawn did not report success"
  line=$(claude_launch_line "$launchlog")
  assert_contains "$line" '"theme":"dark-daltonized"' "a claude scout must launch with the dark-daltonized theme"
  assert_contains "$line" '"statusLine"' "a claude scout must launch with a statusLine banner"
  assert_contains "$line" "$HELPER_BASENAME" "the scout statusLine must run the crewmate banner helper"
  assert_contains "$line" "$id" "the scout statusLine banner must carry the task id"
  pass "a claude scout launch carries the theme and the CREWMATE banner"
}

test_secondmate_launch_omits_theme_and_banner() {
  local w sm launchlog fakebin line rc
  w="$TMP_ROOT/secondmate"
  sm="$w/sm"
  launchlog="$w/launch.log"
  mkdir -p "$w/home/config" "$w/home/state" "$w/home/data" "$w/home/projects"
  printf 'claude\n' > "$w/home/config/secondmate-harness"
  printf '%s\n' "$$" > "$w/home/state/.lock"
  touch "$w/home/state/.last-watcher-beat"
  mkdir -p "$sm/bin" "$sm/data"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf 'sm\n' > "$sm/.fm-secondmate-home"
  printf 'charter\n' > "$sm/data/charter.md"
  fakebin=$(make_spawn_fakebin "$w/fake" gh-axi gh)
  : > "$launchlog"
  rc=0
  # CLAUDECODE=1 pins detect_own to claude so the harness resolves deterministically.
  PATH="$fakebin:$PATH" TMUX='fake,1,0' CLAUDECODE=1 \
    FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$w/home" \
    FM_STATE_OVERRIDE="$w/home/state" FM_DATA_OVERRIDE="$w/home/data" \
    FM_PROJECTS_OVERRIDE="$w/home/projects" FM_CONFIG_OVERRIDE="$w/home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_PATH="$sm" \
    "$SPAWN" sm "$sm" --secondmate >/dev/null 2>&1 || rc=$?
  expect_code 0 "$rc" "claude secondmate spawn should succeed"
  line=$(claude_launch_line "$launchlog")
  assert_contains "$line" '"feedbackDrafts":"off"' "a claude secondmate must still carry the feedbackDrafts control"
  assert_not_contains "$line" "dark-daltonized" "a secondmate is a primary in its own home and must keep the captain's own theme"
  assert_not_contains "$line" "statusLine" "a secondmate must not get the CREWMATE banner"
  assert_not_contains "$line" "$HELPER_BASENAME" "a secondmate must not wire the crewmate banner helper"
  pass "a claude secondmate launch omits the theme override and the CREWMATE banner"
}

# --- banner helper output ---------------------------------------------------

test_helper_prints_loud_red_banner_with_id() {
  local out
  out=$(printf '%s' '{"session":"x"}' | "$STATUSLINE" demo-task-id)
  assert_contains "$out" "CREWMATE demo-task-id" "the banner must name the task id"
  # Bold (1) bright-white (97) on red (41) background is the loud marker.
  assert_contains "$out" '[1;97;41m' "the banner must render bold white on a red background"
  pass "the banner helper prints a loud red CREWMATE marker with the task id"
}

test_helper_drains_stdin_and_shows_branch() {
  local repo out
  repo="$TMP_ROOT/helper-repo"
  fm_git_worktree "$repo/origin" "$repo/wt" statusline-branch
  # A large stdin payload proves the reader drains it without a broken pipe.
  out=$(head -c 200000 /dev/zero | tr '\0' 'x' | ( cd "$repo/wt" && "$STATUSLINE" branch-task ))
  assert_contains "$out" "CREWMATE branch-task" "the banner must survive a large stdin payload"
  assert_contains "$out" "(statusline-branch)" "the banner must show the worktree branch as context"
  pass "the banner helper drains stdin and appends the current branch"
}

test_ship_launch_carries_theme_and_banner
test_scout_launch_carries_theme_and_banner
test_secondmate_launch_omits_theme_and_banner
test_helper_prints_loud_red_banner_with_id
test_helper_drains_stdin_and_shows_branch
