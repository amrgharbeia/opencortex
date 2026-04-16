#!/bin/bash
# OpenCortex: The Unified Conductor v1.3
set -e

PORT=9105
HOST=${1:-localhost}
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

command_exists() { command -v "$1" >/dev/null 2>&1; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- 1. BOOTSTRAP (Clone) ---
if [ ! -d "$SCRIPT_DIR/.git" ] && [[ ! "$(pwd)" =~ "opencortex" ]]; then
    echo -e "${BLUE}=== OpenCortex: Zero-to-One Bootstrapper ===${NC}"
    TARGET_DIR="opencortex"
    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "Cloning repository..."
        git clone http://10.10.10.201:3001/amr/opencortex.git "$TARGET_DIR"
    fi
    cd "$TARGET_DIR"
    git submodule update --init --recursive
    exec ./opencortex.sh "$@"
fi

# --- 2. SETUP (Deps & Tangle) ---
prompt_user() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local result=""
    echo -n -e "${YELLOW}$prompt (default: $default): ${NC}" >&2
    # Use 10s timeout. If run via non-interactive pipe, it will use default.
    if read -t 10 result; then :; else result="$default"; echo -e "${BLUE} [Auto-Selected: $default]${NC}" >&2; fi
    val=${result:-$default}
    eval "$var_name=\"$val\""
}

if [ ! -f "$SCRIPT_DIR/src/package.lisp" ] || [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${BLUE}=== OpenCortex: Initializing System ===${NC}"
    cd "$SCRIPT_DIR"
    if ! command_exists sbcl; then
        echo -e "Installing dependencies..."
        sudo apt-get update && sudo apt-get install -y sbcl emacs git curl socat || true
    fi
    if [ ! -d "$HOME/quicklisp" ]; then
        echo -e "Installing Quicklisp..."
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
    fi
    if [ ! -f "src/package.lisp" ]; then
        echo -e "Tangling brain from literate source..."
        mkdir -p src
        for f in literate/*.org; do
            emacs --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1 || true
        done
    fi
    if [ ! -f .env ]; then
        cp .env.example .env
        prompt_user "What is your name?" "User" "U_NAME"
        sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$U_NAME\"/g" .env
        prompt_user "Enter Gemini API Key" "" "U_KEY"
        sed -i "s/GEMINI_API_KEY=.*/GEMINI_API_KEY=\"$U_KEY\"/g" .env
        sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$SCRIPT_DIR/skills\"|g" .env
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sf "$SCRIPT_DIR/opencortex.sh" "$HOME/.local/bin/opencortex"
    echo -e "${GREEN}✓ Setup complete.${NC}"
fi

# --- 3. BOOT (The Brain) ---
if [[ "$1" == "--boot" ]]; then
    echo -e "${BLUE}Starting OpenCortex Brain...${NC}"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        while IFS='=' read -r key value || [ -n "$key" ]; do
            if [[ $key =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                # Strip quotes and export
                val=$(echo "$value" | sed 's/^"//;s/"$//')
                export "$key=$val"
            fi
        done < "$SCRIPT_DIR/.env"
    fi
    exec sbcl --non-interactive \
         --eval "(load \"~/quicklisp/setup.lisp\")" \
         --eval "(push \"$SCRIPT_DIR/\" asdf:*central-registry*)" \
         --eval "(ql:quickload :opencortex)" \
         --eval "(opencortex:main)"
fi

# --- 4. INTERACT (The Client) ---
connect() {
    if command_exists socat && socat - TCP:$HOST:$PORT,connect-timeout=1 2>/dev/null; then
        socat - TCP:$HOST:$PORT
        return 0
    elif command_exists nc && nc -z $HOST $PORT 2>/dev/null; then
        nc $HOST $PORT
        return 0
    fi
    return 1
}

# 1. Try to connect immediately
if connect; then exit 0; fi

# 2. Not running? Boot once and poll.
echo -e "${YELLOW}Brain is offline. Awakening...${NC}"
"$SCRIPT_DIR/opencortex.sh" --boot > "$SCRIPT_DIR/brain.log" 2>&1 &

for i in {1..15}; do
    sleep 2
    if connect; then exit 0; fi
    echo -n "."
done

echo -e "${RED}\n✗ Connection failed.${NC}"
echo "Check logs: tail -n 20 $SCRIPT_DIR/brain.log"
exit 1
