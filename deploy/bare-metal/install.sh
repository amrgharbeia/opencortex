#!/bin/bash
# org-agent: Bare Metal Installation Script
# This script sets up the org-agent daemon on a Linux host (Debian/Fedora).

set -e

echo "--- org-agent: Bare Metal Installation ---"

# 1. Check Dependencies
echo "[1/4] Checking dependencies..."
for cmd in sbcl curl git ripgrep; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it first."
        exit 1
    fi
done

# 2. Setup Quicklisp
if [ ! -d "$HOME/quicklisp" ]; then
    echo "[2/4] Quicklisp not found. Installing..."
    curl -O https://beta.quicklisp.org/quicklisp.lisp
    sbcl --non-interactive --load quicklisp.lisp --eval '(quicklisp-quickstart:install)'
    rm quicklisp.lisp
    echo "Quicklisp installed."
else
    echo "[2/4] Quicklisp already installed."
fi

# 3. Build standalone binary
echo "[3/4] Building standalone binary..."
PROJECT_ROOT=$(pwd)/../..
sbcl --non-interactive \
     --eval "(push \"$PROJECT_ROOT/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :org-agent)" \
     --eval "(asdf:make :org-agent)"

echo "Binary built: $PROJECT_ROOT/org-agent-server"

# 4. Instructions for Systemd
echo "[4/4] Installation complete."
echo ""
echo "To run as a systemd service:"
echo "1. Edit org-agent.service to set correct paths."
echo "2. sudo cp org-agent.service /etc/systemd/system/"
echo "3. sudo systemctl daemon-reload"
echo "4. sudo systemctl enable --now org-agent"
