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

# --- NEW: Bootstrap Mode ---
bootstrap_opencortex() {
    echo -e "${BLUE}=== OpenCortex: Zero-to-One Bootstrapper ===${NC}"
    if [ -d ".git" ]; then
        echo "Detected existing repository. Switching to local mode..."
        return
    fi

    read -p "Where should I install OpenCortex? (default: ./opencortex): " TARGET_DIR
    TARGET_DIR=${TARGET_DIR:-opencortex}

    if [ -d "$TARGET_DIR" ]; then
        echo -e "${RED}✗ Error: Directory '$TARGET_DIR' already exists.${NC}"
        exit 1
    fi

    echo -e "${BLUE}Cloning repository into $TARGET_DIR...${NC}"
    git clone http://10.10.10.201:3000/amr/opencortex.git "$TARGET_DIR"
    
    cd "$TARGET_DIR"
    git submodule update --init --recursive
    
    echo -e "${GREEN}✓ Repository prepared. Handing off to local setup...${NC}"
    exec ./scripts/onboard-baremetal.sh
}

# Check if we are piped via curl (no .git in current directory)
if [ ! -d ".git" ]; then
    bootstrap_opencortex
fi

update_opencortex() {
    echo -e "${BLUE}Updating OpenCortex...${NC}"
    if [ -d ".git" ]; then
        echo "Pulling latest changes from repository..."
        git pull origin main
    fi
    if [ -f .env ]; then
        SKILLS_DIR=$(grep "^SKILLS_DIR=" .env | cut -d"\"" -f2)
        SKILLS_DIR=${SKILLS_DIR:-$(pwd)/notes}
        echo "Synchronizing core skills to $SKILLS_DIR..."
        mkdir -p "$SKILLS_DIR"
        cp -n skills/*.org "$SKILLS_DIR/" 2>/dev/null || true
    fi
    if command_exists docker-compose && [ -f "docker-compose.yml" ]; then
        echo "Rebuilding Docker image..."
        docker-compose up -d --build
    fi
    echo -e "${GREEN}✓ Update complete.${NC}"
    exit 0
}

if [[ "$1" == "--update" ]]; then
    update_opencortex
fi

# 1. Try to drop straight into the CLI chat
if command_exists socat && socat - TCP:$HOST:$PORT,connect-timeout=1 2>/dev/null; then
    echo -e "${BLUE}Connected to autonomous brain at $HOST:$PORT...${NC}"
    socat READLINE,history=$HOME/.org_agent_history TCP:$HOST:$PORT
    exit 0
elif command_exists nc && nc -z $HOST $PORT 2>/dev/null; then
    echo -e "${YELLOW}socat not found. Falling back to nc (no line-editing).${NC}"
    echo -e "${BLUE}Connected to autonomous brain at $HOST:$PORT...${NC}"
    while true; do
        read -p "User: " MESSAGE
        if [ -z "$MESSAGE" ]; then continue; fi
        echo "$MESSAGE" | nc -N $HOST $PORT
    done
    exit 0
fi

# 2. Check if we have an existing installation we can boot
if [ -f "$HOME/.opencortex-path" ]; then
    INSTALL_DIR=$(cat "$HOME/.opencortex-path")
    if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        echo -e "${YELLOW}Daemon is offline. Booting from $INSTALL_DIR...${NC}"
        cd "$INSTALL_DIR"
        docker-compose up -d
        echo "Waiting for brain to initialize..."
        sleep 5
        exec "$0" "$@"
    fi
fi

# 3. If we are running this inside a cloned repo, configure and boot
if [ -f "opencortex.asd" ] || [ -d "literate" ]; then
    echo -e "${YELLOW}Local repository detected. Ensuring configuration...${NC}"
    INSTALL_DIR=$(pwd)
    echo "$INSTALL_DIR" > "$HOME/.opencortex-path"
    
    if [ ! -f .env ]; then
        ./scripts/onboard-baremetal.sh
    fi
    
    echo -e "${BLUE}Starting OpenCortex via SBCL...${NC}"
    sbcl --non-interactive \
         --eval "(load \"~/quicklisp/setup.lisp\")" \
         --eval "(ql:quickload :opencortex)" \
         --eval "(opencortex:main)"
fi
