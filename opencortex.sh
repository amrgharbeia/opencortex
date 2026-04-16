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

if [ ! -d ".git" ] && [[ ! "$(pwd)" =~ "opencortex" ]]; then 
    bootstrap_opencortex
fi

# --- Helper: Load Env ---
load_env() {
    if [ -f .env ]; then
        while IFS='=' read -r key value || [ -n "$key" ]; do
            # Remove whitespace and quotes
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
            if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                export "$key=$value"
            fi
        done < .env
    fi
}

# --- Force Boot ---
if [[ "$1" == "--boot" ]]; then
    load_env
    echo -e "${BLUE}Starting OpenCortex Brain...${NC}"
    # Use absolute path to the directory containing this script for ASDF
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    exec sbcl --non-interactive \
         --eval "(load \"~/quicklisp/setup.lisp\")" \
         --eval "(push \"$SCRIPT_DIR/\" asdf:*central-registry*)" \
         --eval "(ql:quickload :opencortex)" \
         --eval "(opencortex:main)"
fi

# --- Client Mode ---
if command_exists socat && socat - TCP:$HOST:$PORT,connect-timeout=1 2>/dev/null; then
    echo -e "${BLUE}Connected to autonomous brain at $HOST:$PORT...${NC}"
    socat READLINE,history=$HOME/.org_agent_history TCP:$HOST:$PORT
    exit 0
fi

# --- Auto-Boot Logic ---
if [ -f "opencortex.asd" ] || [ -f "$(dirname "$0")/opencortex.asd" ]; then
    echo -e "${YELLOW}Brain is offline. Starting it now...${NC}"
    # Use the absolute path to ourselves to ensure the right script boots
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    "$SELF" --boot > brain.log 2>&1 &
    sleep 10
    exec "$SELF" "$@"
fi
