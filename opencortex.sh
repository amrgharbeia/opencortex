#!/bin/bash
set -e

PORT=9105
HOST=${1:-localhost}
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Resolve symlinks to find the actual repository location
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
export SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# Load environment variables if they exist
# Priority 1: $HOME/.local/share/opencortex/.env
# Priority 2: $SCRIPT_DIR/.env
if [ -f "$HOME/.local/share/opencortex/.env" ]; then
    ENV_PATH="$HOME/.local/share/opencortex/.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    ENV_PATH="$SCRIPT_DIR/.env"
fi

if [ -n "$ENV_PATH" ]; then
    while IFS="=" read -r key value || [ -n "$key" ]; do
        if [[ $key =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            val=$(echo "$value" | sed "s/^\"//;s/\"$//;s/^'//;s/'$//")
            export "$key=$val"
        fi
    done < "$ENV_PATH"
    [ -n "$HARNESS_PORT" ] && PORT=$HARNESS_PORT
    [ -n "$HARNESS_HOST" ] && HOST=$HARNESS_HOST
fi

# --- 1. BOOTSTRAP ---
if [ ! -d "$SCRIPT_DIR/.git" ] && [ ! -d "$HOME/.opencortex" ] && [[ ! "$(pwd)" =~ "opencortex" ]]; then
    echo -e "${BLUE}=== OpenCortex: Zero-to-One Bootstrapper ===${NC}"
    git clone http://10.10.10.201:3001/amr/opencortex.git ~/.opencortex
    cd ~/.opencortex && git submodule update --init --recursive
    exec ./opencortex.sh "$@"
fi

# --- 2. SETUP ---
setup_system() {
    echo -e "${BLUE}=== OpenCortex: Initializing System ===${NC}"
    
    echo -e "${YELLOW}--- Installing System Dependencies ---${NC}"
    if command_exists apt-get; then
        sudo apt-get update && sudo apt-get install -y sbcl emacs-nox rlwrap netcat-openbsd curl git socat libssl-dev libncurses-dev libffi-dev zlib1g-dev libsqlite3-dev
    fi
    if [ ! -d "$HOME/quicklisp" ]; then
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
    fi
    
    cd "$SCRIPT_DIR"
    if [ ! -f .env ] && [ ! -f "$HOME/.local/share/opencortex/.env" ]; then
        cp .env.example .env

        echo -e "\n${YELLOW}--- Identity Configuration ---${NC}"
        read -p "Your Name [User]: " user_name < /dev/tty
        user_name=${user_name:-User}
        sed -i "s|MEMEX_USER=.*|MEMEX_USER=\"$user_name\"|" .env

        read -p "Agent Name [OpenCortex]: " agent_name < /dev/tty
        agent_name=${agent_name:-OpenCortex}
        sed -i "s|MEMEX_ASSISTANT=.*|MEMEX_ASSISTANT=\"$agent_name\"|" .env

        echo -e "\n${YELLOW}--- LLM Configuration ---${NC}"
        read -p "Gemini API Key: " gemini_key < /dev/tty
        [ -n "$gemini_key" ] && sed -i "s|GEMINI_API_KEY=.*|GEMINI_API_KEY=\"$gemini_key\"|" .env
        read -p "Anthropic API Key: " anthropic_key < /dev/tty
        [ -n "$anthropic_key" ] && sed -i "s|ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=\"$anthropic_key\"|" .env
        read -p "OpenAI API Key: " openai_key < /dev/tty
        [ -n "$openai_key" ] && sed -i "s|OPENAI_API_KEY=.*|OPENAI_API_KEY=\"$openai_key\"|" .env
        read -p "OpenRouter API Key: " openrouter_key < /dev/tty
        [ -n "$openrouter_key" ] && sed -i "s|OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=\"$openrouter_key\"|" .env

        echo -e "\n${YELLOW}--- Memex Folder Structure ---${NC}"
        read -p "Memex Root [$HOME/memex]: " memex_root < /dev/tty
        memex_root=${memex_root:-$HOME/memex}
        sed -i "s|MEMEX_ROOT=.*|MEMEX_ROOT=\"$memex_root\"|" .env
    fi

    echo -e "\n${YELLOW}--- Warming Neural Cache ---${NC}"
    rm -rf "$HOME/.cache/common-lisp"
    sbcl --non-interactive --eval "(load (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))" \
         --eval "(push (truename \"$SCRIPT_DIR\") asdf:*central-registry*)" \
         --eval "(ql:quickload '(:opencortex :opencortex/tui :croatoan))"

    echo -e "\n${YELLOW}--- Finalizing: Awakening the Brain as a background daemon ---${NC}"
    > "$SCRIPT_DIR/brain.log"
    bash "$SCRIPT_DIR/opencortex.sh" --boot > "$SCRIPT_DIR/brain.log" 2>&1 &

    local success=false
    for i in {1..30}; do
        if nc -z localhost $PORT 2>/dev/null; then
            success=true
            break
        fi
        echo -n "."
        sleep 2
    done

    if [ "$success" = true ]; then
        echo -e "\n${GREEN}✓ Brain is alive and responsive on port $PORT.${NC}"
        echo -e "${GREEN}✓ Setup complete.${NC}"
        echo -e "${BLUE}To start, run:${NC} ${GREEN}opencortex tui${NC}"
        exit 0
    else
        echo -e "\n${RED}✗ Brain failed to wake up.${NC}"
        echo -e "${YELLOW}Full Log Path: $(realpath "$SCRIPT_DIR/brain.log")${NC}"
        cat "$SCRIPT_DIR/brain.log"
        exit 1
    fi
}

# --- 3. COMMAND ROUTER ---
COMMAND=${1:-"cli"}

if [ ! -f "$SCRIPT_DIR/src/package.lisp" ] || ([ ! -f "$SCRIPT_DIR/.env" ] && [ ! -f "$HOME/.local/share/opencortex/.env" ]); then
    COMMAND="setup"
fi

case "$COMMAND" in
    setup)
        setup_system
        ;;
        
    --boot|boot)
        # Prevent double-booting
        if nc -z localhost $PORT 2>/dev/null; then
            echo -e "${GREEN}Brain is already active on port $PORT.${NC}"
            exit 0
        fi
        
        echo -e "${YELLOW}--- Awakening OpenCortex Conducter ---${NC}"
        export SKILLS_DIR="${SCRIPT_DIR}/skills"
        [ -z "$MEMEX_DIR" ] && export MEMEX_DIR="$HOME/memex"
        
        # We don't purge cache here to avoid race conditions with TUI launch
        exec sbcl --eval "(load (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))" \
             --eval "(setf *debugger-hook* (lambda (c h) (declare (ignore h)) (format *error-output* \"FATAL LISP ERROR: ~a~%\" c) (uiop:print-backtrace :stream *error-output*) (uiop:quit 1)))" \
             --eval "(push (truename \"$SCRIPT_DIR\") asdf:*central-registry*)" \
             --eval "(ql:quickload '(:opencortex :croatoan))" \
             --eval "(opencortex:main)"
        ;;
        
    tui)
        if ! nc -z $HOST $PORT 2>/dev/null; then
            if [ -f "$SCRIPT_DIR/boot.lock" ]; then
                echo -e "${YELLOW}Brain is currently waking up. Waiting for initialization...${NC}"
            else
                echo -e "Brain is offline. Awakening..."
                touch "$SCRIPT_DIR/boot.lock"
                bash "$SCRIPT_DIR/opencortex.sh" --boot > "$SCRIPT_DIR/brain.log" 2>&1 &
            fi
            
            for i in {1..30}; do
                sleep 2
                if nc -z $HOST $PORT 2>/dev/null; then break; fi
                echo -n "."
            done
            echo ""
            rm -f "$SCRIPT_DIR/boot.lock"
        fi
        
        echo -e "Launching Croatoan TUI..."
        export SKILLS_DIR="${SCRIPT_DIR}/skills"
        [ -z "$MEMEX_DIR" ] && export MEMEX_DIR="$HOME/memex"
        exec sbcl --disable-debugger --eval "(load (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))" \
             --eval "(push (truename \"$SCRIPT_DIR\") asdf:*central-registry*)" \
             --eval "(ql:quickload :opencortex/tui)" \
             --eval "(opencortex.tui:main)"
        ;;
        
    cli)
        if ! nc -z $HOST $PORT 2>/dev/null; then
            echo -e "Brain is offline. Awakening..."
            bash "$SCRIPT_DIR/opencortex.sh" --boot > "$SCRIPT_DIR/brain.log" 2>&1 &
            for i in {1..15}; do
                sleep 2
                if nc -z $HOST $PORT 2>/dev/null; then break; fi
                echo -n "."
            done
            echo ""
        fi
        if command_exists socat; then
            exec socat - TCP:$HOST:$PORT
        else
            exec nc $HOST $PORT
        fi
        ;;
        
    *)
        echo -e "Unknown command: $COMMAND"
        echo "Available commands: setup, boot, tui, cli"
        exit 1
        ;;
esac
