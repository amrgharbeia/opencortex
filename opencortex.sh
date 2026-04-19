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
if [ -f "$SCRIPT_DIR/.env" ]; then
    while IFS="=" read -r key value || [ -n "$key" ]; do
        if [[ $key =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            val=$(echo "$value" | sed "s/^\"//;s/\"$//")
            export "$key=$val"
        fi
    done < "$SCRIPT_DIR/.env"
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
        sudo apt-get update && sudo apt-get install -y sbcl emacs-nox rlwrap netcat-openbsd curl git socat libssl-dev libncurses5-dev libffi-dev zlib1g-dev libsqlite3-dev
    fi
    if [ ! -d "$HOME/quicklisp" ]; then
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
    fi
    
    cd "$SCRIPT_DIR"
    if [ ! -f .env ]; then
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
        read -p "Memex Root [\$HOME/memex]: " memex_dir < /dev/tty
        memex_dir=${memex_dir:-\$HOME/memex}
        sed -i "s|MEMEX_DIR=.*|MEMEX_DIR=\"$memex_dir\"|" .env
        sed -i "s|\"/memex/|\"$memex_dir/|g" .env
        sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$SCRIPT_DIR/skills\"|" .env
        sed -i "s|ZETTELKASTEN_DIR=.*|ZETTELKASTEN_DIR=\"$memex_dir/notes\"|" .env

        read -p "Inbox Directory [\$memex_dir/inbox]: " inbox_dir < /dev/tty
        inbox_dir=${inbox_dir:-\$memex_dir/inbox}
        sed -i "s|INBOX_DIR=.*|INBOX_DIR=\"$inbox_dir\"|" .env

        read -p "Daily Directory [\$memex_dir/daily]: " daily_dir < /dev/tty
        daily_dir=${daily_dir:-\$memex_dir/daily}
        sed -i "s|DAILY_DIR=.*|DAILY_DIR=\"$daily_dir\"|" .env

        read -p "Projects Directory [\$memex_dir/projects]: " proj_dir < /dev/tty
        proj_dir=${proj_dir:-\$memex_dir/projects}
        sed -i "s|PROJECTS_DIR=.*|PROJECTS_DIR=\"$proj_dir\"|" .env
        
        mkdir -p "$memex_dir" "$inbox_dir" "$daily_dir" "$proj_dir"
        mkdir -p "$memex_dir/notes" "$memex_dir/areas" "$memex_dir/resources" "$memex_dir/archives" "$memex_dir/system"
    fi

    mkdir -p src
    for f in literate/*.org; do
        emacs --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1 || true
    done
    
    mkdir -p "$HOME/.local/bin"
    ln -sf "$SCRIPT_DIR/opencortex.sh" "$HOME/.local/bin/opencortex"

    for shell_config in "$HOME/.bashrc" "$HOME/.profile"; do
        if [ -f "$shell_config" ]; then
            if ! grep -q ".local/bin" "$shell_config"; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_config"
            fi
        fi
    done
    export PATH="$HOME/.local/bin:$PATH"

    echo -e "${YELLOW}--- Compiling and Loading OpenCortex (this may take a minute) ---${NC}"
    sbcl --non-interactive --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' --eval '(push (truename (uiop:getenv "SCRIPT_DIR")) asdf:*central-registry*)' --eval "(ql:quickload '(:opencortex :croatoan))"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Compilation or Loading failed.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}--- Finalizing: Awakening the Brain as a background daemon ---${NC}"
    > "$SCRIPT_DIR/brain.log"
    "$SCRIPT_DIR/opencortex.sh" --boot > "$SCRIPT_DIR/brain.log" 2>&1 &

    local success=false
    for i in {1..30}; do
        if nc -z localhost $PORT 2>/dev/null; then
            success=true
            break
        fi
        sleep 2
        echo -n "."
    done

    if [ "$success" = true ]; then
        echo -e "\n${GREEN}✓ Brain is alive and responsive on port $PORT.${NC}"
        echo -e "${GREEN}✓ Setup complete.${NC}"
        if command -v opencortex >/dev/null 2>&1; then
            echo -e "${BLUE}To start, run:${NC} ${GREEN}opencortex tui${NC}"
        else
            echo -e "${BLUE}To start, run:${NC} ${GREEN}exec bash && opencortex tui${NC}"
        fi
        exit 0
    else
        echo -e "\n${RED}✗ Brain failed to wake up.${NC}"
        echo -e "${YELLOW}Full Log Path: $(realpath "$SCRIPT_DIR/brain.log")${NC}"
        cat "$SCRIPT_DIR/brain.log"
        exit 1
    fi
}

# --- 3. COMMAND ROUTER ---
# By default, if no arguments are provided, we assume the user wants the CLI fallback.
COMMAND=${1:-"cli"}

# However, if the system is completely uninitialized, we force the 'setup' command.
if [ ! -f "$SCRIPT_DIR/src/package.lisp" ] || [ ! -f "$SCRIPT_DIR/.env" ]; then
    COMMAND="setup"
fi

case "$COMMAND" in
    setup)
        setup_system
        ;;
        
    --boot|boot)
        export SKILLS_DIR="${SCRIPT_DIR}/skills"
        [ -z "$MEMEX_DIR" ] && export MEMEX_DIR="$HOME/memex"
        exec sbcl --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' --eval '(setf *debugger-hook* (lambda (c h) (declare (ignore h)) (format *error-output* "FATAL LISP ERROR: ~a~%" c) (uiop:print-backtrace :stream *error-output*) (uiop:quit 1)))' --eval '(push (truename (uiop:getenv "SCRIPT_DIR")) asdf:*central-registry*)' --eval '(format t "--- Quickloading OpenCortex ---~%")' --eval "(ql:quickload '(:opencortex :croatoan))" --eval '(opencortex:main)'
        ;;
        
    tui)
        if ! nc -z $HOST $PORT 2>/dev/null; then
            echo -e "Brain is offline. Awakening..."
            "$SCRIPT_DIR/opencortex.sh" --boot > "$SCRIPT_DIR/brain.log" 2>&1 &
            for i in {1..15}; do
                sleep 2
                if nc -z $HOST $PORT 2>/dev/null; then break; fi
                echo -n "."
            done
            echo ""
        fi
        echo -e "Launching Croatoan TUI..."
        export SKILLS_DIR="${SCRIPT_DIR}/skills"
        [ -z "$MEMEX_DIR" ] && export MEMEX_DIR="$HOME/memex"
        exec sbcl --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' --eval '(push (truename (uiop:getenv "SCRIPT_DIR")) asdf:*central-registry*)' --eval '(ql:quickload :opencortex/tui)' --eval '(opencortex.tui:main)'
        ;;
        
    cli)
        if ! nc -z $HOST $PORT 2>/dev/null; then
            echo -e "Brain is offline. Awakening..."
            "$SCRIPT_DIR/opencortex.sh" --boot > "$SCRIPT_DIR/brain.log" 2>&1 &
            for i in {1..15}; do
                sleep 2
                if nc -z $HOST $PORT 2>/dev/null; then break; fi
                echo -n "."
            done
            echo ""
        fi
        if command_exists socat; then
            exec socat - TCP::
        else
            exec nc  
        fi
        ;;
        
    *)
        echo -e "Unknown command: $COMMAND"
        echo "Available commands: setup, boot, tui, cli"
        exit 1
        ;;
esac
