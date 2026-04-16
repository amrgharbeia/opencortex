#!/bin/bash
set -e

PORT=9105
HOST=${1:-localhost}

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- Bootstrap Mode ---
bootstrap_opencortex() {
    echo -e "${BLUE}=== OpenCortex: Zero-to-One Bootstrapper ===${NC}"
    if [ -d ".git" ]; then
        echo "Detected existing repository. Switching to local mode..."
        return
    fi

    TARGET_DIR="opencortex"
    if [ -d "$TARGET_DIR" ]; then
        if [ -d "$TARGET_DIR/.git" ]; then
            echo -e "${YELLOW}! Using existing repository in '$TARGET_DIR'...${NC}"
        else
            echo -e "${RED}! Directory '$TARGET_DIR' exists. Using it as-is...${NC}"
        fi
    else
        echo -e "${BLUE}Cloning repository into $TARGET_DIR...${NC}"
        git clone http://10.10.10.201:3001/amr/opencortex.git "$TARGET_DIR"
    fi
    
    cd "$TARGET_DIR"
    git submodule update --init --recursive
    
    echo -e "${GREEN}✓ Repository prepared. Handing off to local setup...${NC}"
    # Reconnect stdin to the TTY for the next script, or use /dev/null to avoid hang
    if [ -t 0 ]; then
        exec ./scripts/onboard-baremetal.sh
    else
        exec ./scripts/onboard-baremetal.sh < /dev/tty 2>/dev/null || exec ./scripts/onboard-baremetal.sh < /dev/null
    fi
}

if [ ! -d ".git" ]; then
    bootstrap_opencortex
fi

update_opencortex() {
    echo -e "${BLUE}Updating OpenCortex...${NC}"
    if [ -d ".git" ]; then
        git pull origin main
    fi
    echo -e "${GREEN}✓ Update complete.${NC}"
    exit 0
}

if [[ "$1" == "--update" ]]; then update_opencortex; fi

# 1. Try to drop straight into the CLI chat
if command_exists socat && socat - TCP:$HOST:$PORT,connect-timeout=1 2>/dev/null; then
    echo -e "${BLUE}Connected to autonomous brain at $HOST:$PORT...${NC}"
    socat READLINE,history=$HOME/.org_agent_history TCP:$HOST:$PORT
    exit 0
fi

# 2. Local repository detection and launch
if [ -f "opencortex.asd" ] || [ -d "literate" ]; then
    if [ ! -f .env ]; then
        ./scripts/onboard-baremetal.sh
    fi
    
    echo -e "${BLUE}Starting OpenCortex via SBCL...${NC}"
    sbcl --non-interactive \
         --eval "(load \"~/quicklisp/setup.lisp\")" \
         --eval "(ql:quickload :opencortex)" \
         --eval "(opencortex:main)"
fi
