#!/usr/bin/env bash
# Regression test for fm-spawn's tmux session target.
#
# A bare "-t <session>" is ambiguous: tmux resolves it to a WINDOW of that name
# when one exists, so in a session that holds a same-named window (a session
# "firstmate" whose window is also called "firstmate") new-window inherits that
# window's index and fails with "create window failed: index N in use" - the
# spawn dies before the agent ever launches. The session-scoped "$SES:" form
# appends at the next free index instead.
#
# Real tmux on a private socket, because this is tmux target-resolution
# semantics: a fake tmux would accept either form and prove nothing. The spawn
# runs the secondmate path, which reaches window creation without treehouse.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/secondmate-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/secondmate-helpers.sh"

command -v tmux >/dev/null 2>&1 || { echo "skip: tmux not found"; exit 0; }

REAL_TMUX=$(command -v tmux)
SOCKET="fm-spawn-target-$$"
TMP_ROOT=$(fm_test_tmproot fm-spawn-session-target)

cleanup_tmux() { "$REAL_TMUX" -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup_tmux EXIT

# Bare `tmux` must reach the private socket, never the developer's live server.
SHIM=$(fm_fakebin "$TMP_ROOT/shim")
cat > "$SHIM/tmux" <<SHIM_EOF
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SHIM_EOF
chmod +x "$SHIM/tmux"

# The trap: a session whose window carries the session's own name. tmux's
# base-index is configurable, so rename whichever index the window landed on.
"$REAL_TMUX" -L "$SOCKET" new-session -d -s firstmate -n placeholder
BASE_INDEX=$("$REAL_TMUX" -L "$SOCKET" list-windows -t firstmate: -F '#{window_index}' | head -1)
"$REAL_TMUX" -L "$SOCKET" rename-window -t "firstmate:$BASE_INDEX" firstmate

# A secondmate home is the shortest path to window creation: it skips
# `treehouse get`, so no project worktree machinery is involved.
HOME_DIR="$TMP_ROOT/home"
SUB="$TMP_ROOT/sub"
mkdir -p "$HOME_DIR/data" "$HOME_DIR/state" "$SUB"
seed_secondmate_home_marker "$SUB" design
printf 'charter: design supervisor\n' > "$SUB/data/charter.md"

# The session-name trap alone must not stop the spawn: assert on the window
# actually existing, which is what the agent needs to be launched into.
test_spawn_survives_session_named_window() {
  local out status
  out=$(PATH="$SHIM:$PATH" TMUX='' FM_HOME="$HOME_DIR" FM_SPAWN_NO_GUARD=1 \
    "$ROOT/bin/fm-spawn.sh" design "$SUB" codex --secondmate 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "spawn failed in a session holding a same-named window: $out"
  assert_not_contains "$out" 'index in use' "spawn hit the ambiguous bare-session target"

  "$REAL_TMUX" -L "$SOCKET" list-windows -t firstmate: -F '#{window_name}' | grep -qx 'fm-design' \
    || fail "spawn did not create window fm-design in session firstmate"
  pass "spawn creates its window in a session that holds a same-named window"
}

# Guard the mechanism itself, so a future refactor back to the bare form is
# caught rather than silently reintroducing the failure. Verified empirically:
# the bare form errors here, the scoped form does not.
test_bare_target_is_the_failure_mode() {
  local out status
  out=$("$REAL_TMUX" -L "$SOCKET" new-window -d -t firstmate -n fm-bare-probe 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "bare -t <session> unexpectedly succeeded; the trap no longer reproduces"
  assert_contains "$out" 'in use' "bare -t <session> failed for an unexpected reason: $out"
  pass "bare -t <session> still resolves to the same-named window and fails"
}

test_spawn_survives_session_named_window
test_bare_target_is_the_failure_mode
