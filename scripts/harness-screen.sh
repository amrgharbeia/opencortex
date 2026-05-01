#!/bin/bash
# OpenCortex TUI Harness via GNU Screen
# Provides a persistent PTY for Croatoan/ncurses TUI testing.

set -euo pipefail

SESSION="oct-tui"
LOG="$HOME/.local/state/opencortex/tui-screen.log"

function cleanup() {
    screen -S "$SESSION" -X quit 2>/dev/null || true
}

case "${1:-start}" in
    start)
        cleanup
        mkdir -p "$(dirname "$LOG")"
        export TERM=screen-256color
        export SKILLS_DIR="$HOME/.local/share/opencortex/skills"
        screen -dmS "$SESSION" bash -c '
            sbcl --non-interactive \
                --eval "(load (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))" \
                --eval "(push (truename \"$HOME/.local/share/opencortex/\") asdf:*central-registry*)" \
                --eval "(ql:quickload :opencortex/tui :silent t)" \
                --eval "(opencortex.tui:main)" \
                2>&1 | tee '"$LOG"'
            echo "[TUI exited with code $?]"
            sleep 3600
        '
        sleep 2
        echo "TUI started in screen session '$SESSION'"
        echo "Logs: $LOG"
        ;;
    
    send)
        shift
        screen -S "$SESSION" -X stuff "$*"
        ;;
    
    enter)
        screen -S "$SESSION" -X stuff "$(printf '\r')"
        ;;
    
    capture)
        screen -S "$SESSION" -X hardcopy -h /tmp/oct-tui-capture.txt
        cat /tmp/oct-tui-capture.txt
        ;;
    
    log)
        tail -f "$LOG"
        ;;
    
    kill)
        cleanup
        echo "TUI session killed."
        ;;
    
    *)
        echo "Usage: $0 {start|send <text>|enter|capture|log|kill}"
        exit 1
        ;;
esac
