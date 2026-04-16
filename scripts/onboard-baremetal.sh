#!/bin/bash
# OpenCortex Final-Mile Installer (Debug Edition)
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

echo -e "${BLUE}=== OpenCortex: Baremetal Power-User Setup ===${NC}"

# Robust Non-Blocking Prompt
prompt_user() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local result=""
    
    echo -n -e "${YELLOW}$prompt (default: $default): ${NC}" >&2
    
    # Check if we have a real terminal
    if [ -t 0 ]; then
        if read -t 10 result; then
            :
        else
            result="$default"
            echo -e "${BLUE} [Timeout: Using $default]${NC}" >&2
        fi
    else
        # If no terminal, try /dev/tty but don't hang
        if read -t 2 result < /dev/tty 2>/dev/null; then
            :
        else
            result="$default"
            echo -e "${BLUE} [Auto-Selected Default: $default]${NC}" >&2
        fi
    fi
    
    val=${result:-$default}
    eval "$var_name=\"$val\""
}

echo "DEBUG: Checking dependencies..."
if ! command -v sbcl >/dev/null 2>&1 || ! command -v emacs >/dev/null 2>&1; then
    echo -e "${YELLOW}! Missing dependencies (SBCL/Emacs).${NC}"
    # Just auto-install if we are in a non-interactive pipe
    if [ ! -t 0 ]; then
        DO_INSTALL="y"
        echo -e "${BLUE}[Auto-Pilot: Installing dependencies]${NC}"
    else
        prompt_user "Should I attempt to install them for you? [Y/n]" "y" "DO_INSTALL"
    fi
    
    if [[ "$DO_INSTALL" =~ ^[Yy]$ ]]; then
        if command -v apt-get >/dev/null; then
            sudo apt-get update && sudo apt-get install -y sbcl emacs git curl socat
        elif command -v pacman >/dev/null; then
            sudo pacman -S --noconfirm sbcl emacs git curl socat
        fi
    fi
fi

echo "DEBUG: Checking Quicklisp..."
if [ ! -d "$HOME/quicklisp" ] && [ ! -d "$HOME/.quicklisp" ]; then
    echo -e "${YELLOW}! Quicklisp not found.${NC}"
    if [ ! -t 0 ]; then
        DO_QL="y"
        echo -e "${BLUE}[Auto-Pilot: Installing Quicklisp]${NC}"
    else
        prompt_user "Install Quicklisp now? [Y/n]" "y" "DO_QL"
    fi
    if [[ "$DO_QL" =~ ^[Yy]$ ]]; then
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp \
             --eval "(quicklisp-quickstart:install)" \
             --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
    fi
fi

echo "DEBUG: Starting Tangle..."
mkdir -p src
for f in literate/*.org; do
    echo "  - DEBUG: Tangling $f"
    emacs --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1 || true
done

echo "DEBUG: Tangle Loop Finished."

if [ ! -f "src/package.lisp" ]; then
    echo -e "${RED}✗ Tangling failed. Essential files missing in src/.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Core tangled successfully.${NC}"

echo "DEBUG: Configuring Env..."
if [ ! -f .env ]; then cp .env.example .env; fi

# For environment variables, just use defaults if no terminal
if [ ! -t 0 ]; then
    USER_NAME="User"
    AGENT_NAME="OpenCortex"
    LLM_CHOICE="1"
    echo -e "${BLUE}[Auto-Pilot: Using default configuration]${NC}"
else
    prompt_user "What is your name?" "User" "USER_NAME"
    prompt_user "What shall we name your Assistant?" "OpenCortex" "AGENT_NAME"
    echo -e "\nSelect neural provider (1:Gemini, 2:OpenRouter, 3:Anthropic, 4:OpenAI)"
    prompt_user "Choice" "1" "LLM_CHOICE"
fi

sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env
sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

# Path Alignment (Automated)
PROJECT_ROOT=$(pwd)
PARENT_DIR=$(dirname "$PROJECT_ROOT")
sed -i "s|MEMEX_DIR=.*|MEMEX_DIR=\"$PARENT_DIR\"|g" .env
sed -i "s|ZETTELKASTEN_DIR=.*|ZETTELKASTEN_DIR=\"$PARENT_DIR/notes\"|g" .env
sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$PROJECT_ROOT/skills\"|g" .env

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}    OpenCortex Installation Complete!        ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "To start the brain: ./opencortex.sh"
