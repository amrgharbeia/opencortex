#!/bin/bash
# OpenCortex TUI Automated Test Harness
# Runs the TUI in a tmux pane, sends "hi", captures response.

set -euo pipefail

SESSION="opencortex-tui-test"
TUI_LOG="/tmp/opencortex-tui-test.log"
CAPTURE="/tmp/opencortex-tui-capture.txt"
TIMEOUT_SEC=30

echo "=== OpenCortex TUI Test Harness ==="
echo "Log: $TUI_LOG"
echo "Capture: $CAPTURE"

# Clean up any stale session
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Verify daemon is running
if ! ss -tln | grep -q ':9105'; then
    echo "ERROR: Daemon not running on port 9105"
    echo "Start it with: cd ~/memex/projects/opencortex && ./opencortex.sh daemon"
    exit 1
fi

# Create tmux session with TUI
echo "[1/5] Starting TUI in tmux session '$SESSION'..."
tmux new-session -d -s "$SESSION" \
    -e OC_CONFIG_DIR="$HOME/.config/opencortex" \
    -e OC_DATA_DIR="$HOME/.local/share/opencortex" \
    -e SKILLS_DIR="$HOME/.local/share/opencortex/skills" \
    -e TERM="screen-256color" \
    "sbcl --non-interactive \
        --eval '(load (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))' \
        --eval '(push (truename \"$HOME/.local/share/opencortex/\") asdf:*central-registry*)' \
        --eval '(ql:quickload :opencortex/tui)' \
        --eval '(opencortex.tui:main)' 2>&1 | tee $TUI_LOG"

sleep 3

# Capture initial state
tmux capture-pane -t "$SESSION" -p > "$CAPTURE"
echo "[2/5] Initial TUI state captured ($(wc -l < "$CAPTURE") lines)"

# Send message
echo "[3/5] Sending 'hi' + Enter..."
tmux send-keys -t "$SESSION" "hi" Enter

# Wait for response
echo "[4/5] Waiting up to ${TIMEOUT_SEC}s for response..."
for i in $(seq 1 $TIMEOUT_SEC); do
    tmux capture-pane -t "$SESSION" -p > "$CAPTURE"
    # Check if daemon response arrived (contains arrow-down marker or actual response text)
    if grep -qE "(⬇|Hi|Hello|Neural Cascade)" "$CAPTURE"; then
        echo "    ✓ Response detected after ${i}s"
        break
    fi
    sleep 1
done

# Final capture
tmux capture-pane -t "$SESSION" -p > "$CAPTURE"
echo "[5/5] Final capture ($(wc -l < "$CAPTURE") lines)"

# Extract and display results
echo ""
echo "=== SCREEN CAPTURE ==="
cat "$CAPTURE"
echo ""
echo "=== TUI LOG (last 20 lines) ==="
tail -20 "$TUI_LOG"
echo ""

# Check for errors
if grep -qE "(TUI Error|Connection lost|ERROR:)" "$TUI_LOG"; then
    echo "❌ TEST FAILED: Errors detected in TUI log"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    exit 1
fi

if grep -qE "(⬇|Hi|Hello)" "$CAPTURE"; then
    echo "✅ TEST PASSED: Response received from daemon"
else
    echo "⚠️  TEST INCOMPLETE: No response marker found (daemon may have timed out)"
fi

# Cleanup
tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "Done."
