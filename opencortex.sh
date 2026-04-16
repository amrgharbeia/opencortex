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
    if [ -d ".git" ]; then return; fi
    TARGET_DIR="opencortex"
    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${BLUE}Cloning repository into $TARGET_DIR...${NC}"
        git clone http://10.10.10.201:3001/amr/opencortex.git "$TARGET_DIR"
    fi
    cd "$TARGET_DIR"
    git submodule update --init --recursive
    echo -e "${GREEN}✓ Repository prepared.${NC}"
    ./scripts/onboard-baremetal.sh
    echo -e "${GREEN}✓ Setup phase complete.${NC}"
    exit 0
}

if [ ! -d ".git" ]; then bootstrap_opencortex; fi

# 1. Try to drop straight into the CLI chat
if command_exists socat && socat - TCP:$HOST:$PORT,connect-timeout=1 2>/dev/null; then
    echo -e "${BLUE}Connected to autonomous brain at $HOST:$PORT...${NC}"
    socat READLINE,history=$HOME/.org_agent_history TCP:$HOST:$PORT
    exit 0
fi

# 2. Launch
if [ -f "opencortex.asd" ]; then echo -e "${YELLOW}Brain is offline. Starting it now...${NC}"; $0 --boot > brain.log 2>&1 & sleep 10; exec $0 "$@"; fi
        done < .env
    fi
    echo -e "${BLUE}Starting OpenCortex Brain...${NC}"
    sbcl --non-interactive \
         --eval "(load \"~/quicklisp/setup.lisp\")" \
         --eval "(push \"$(pwd)/\" asdf:*central-registry*)" \
         --eval "(ql:quickload :opencortex)" \
         --eval "(opencortex:main)"
fi
