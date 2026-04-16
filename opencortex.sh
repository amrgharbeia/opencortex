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
        return
    fi

    TARGET_DIR="opencortex"
    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${BLUE}Cloning repository into $TARGET_DIR...${NC}"
        git clone http://10.10.10.201:3001/amr/opencortex.git "$TARGET_DIR"
    fi
    
    cd "$TARGET_DIR"
    git submodule update --init --recursive
    
    echo -e "${GREEN}✓ Repository prepared.${NC}"
    
    # Run the setup script. We don't use exec here so we can stay in control.
    # We try to give it a TTY, but fallback to /dev/null if that causes a hang.
    if [ -t 0 ]; then
        ./scripts/onboard-baremetal.sh
    else
        ./scripts/onboard-baremetal.sh < /dev/tty 2>/dev/null || ./scripts/onboard-baremetal.sh < /dev/null
    fi
    
    echo -e "${GREEN}✓ Setup phase complete.${NC}"
    exit 0
}

if [ ! -d ".git" ]; then
    bootstrap_opencortex
fi

# ... (rest of local mode)
if [ -f "opencortex.asd" ] || [ -d "literate" ]; then
    if [ ! -f .env ]; then ./scripts/onboard-baremetal.sh; fi
    sbcl --non-interactive --eval "(load \"~/quicklisp/setup.lisp\")" --eval "(ql:quickload :opencortex)" --eval "(opencortex:main)"
fi
