#!/bin/bash
# OpenCortex Final-Mile Installer
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

echo -e "${BLUE}=== OpenCortex: Baremetal Power-User Setup ===${NC}"

# Robust Non-Blocking Prompt
prompt_user() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local result=""
    
    echo -n -e "${YELLOW}$prompt (default: $default): ${NC}" >&2
    
    # Try reading with a short timeout. Use defaults if piped/no-tty.
    if read -t 5 result; then
        :
    else
        result="$default"
        echo -e "${BLUE} [Auto-Selected: $default]${NC}" >&2
    fi
    
    val=${result:-$default}
    eval "$var_name=\"$val\""
}

# 1. Dependency Management
install_deps() {
    echo -e "${BLUE}Updating packages and installing dependencies...${NC}"
    if command -v apt-get >/dev/null; then
        sudo apt-get update && sudo apt-get install -y sbcl emacs git curl socat
    elif command -v pacman >/dev/null; then
        sudo pacman -S --noconfirm sbcl emacs git curl socat
    else
        echo -e "${RED}✗ Unknown package manager. Please install dependencies manually.${NC}"
    fi
}

if ! command -v sbcl >/dev/null 2>&1 || ! command -v emacs >/dev/null 2>&1; then
    echo -e "${YELLOW}! Missing dependencies (SBCL/Emacs).${NC}"
    prompt_user "Should I attempt to install them for you? [Y/n]" "y" "DO_INSTALL"
    if [[ "$DO_INSTALL" =~ ^[Yy]$ ]]; then
        install_deps
    fi
fi

# 2. Quicklisp Installation
if [ ! -d "$HOME/quicklisp" ] && [ ! -d "$HOME/.quicklisp" ]; then
    echo -e "${YELLOW}! Quicklisp not found.${NC}"
    prompt_user "Install Quicklisp now? [Y/n]" "y" "DO_QL"
    if [[ "$DO_QL" =~ ^[Yy]$ ]]; then
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp \
             --eval "(quicklisp-quickstart:install)" \
             --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
        echo -e "${GREEN}✓ Quicklisp installed.${NC}"
    fi
fi

# 3. Literate Tangling (The Transparent Version)
echo -e "${BLUE}Tangling Literate Org files into source code...${NC}"
mkdir -p src
for f in literate/*.org; do
    echo -e "  - Tangling $f..."
    emacs --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1 || echo -e "${RED}    ! Warning: Tangle issue in $f${NC}"
done

if [ ! -f "src/package.lisp" ]; then
    echo -e "${RED}✗ Tangling failed. Essential files missing in src/.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Core tangled successfully.${NC}"

# 4. Environment Configuration
echo -e "\n${BLUE}Configuring your environment...${NC}"
if [ ! -f .env ]; then cp .env.example .env; fi

prompt_user "What is your name?" "User" "USER_NAME"
sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env

prompt_user "What shall we name your Assistant?" "OpenCortex" "AGENT_NAME"
sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

echo -e "\nSelect neural provider (1:Gemini, 2:OpenRouter, 3:Anthropic, 4:OpenAI)"
prompt_user "Choice" "1" "LLM_CHOICE"

case $LLM_CHOICE in
    2) prompt_user "Enter OpenRouter Key" "" "INPUT"; sed -i "s/OPENROUTER_API_KEY=.*/OPENROUTER_API_KEY=\"$INPUT\"/g" .env ;;
    3) prompt_user "Enter Anthropic Key" "" "INPUT"; sed -i "s/ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=\"$INPUT\"/g" .env ;;
    4) prompt_user "Enter OpenAI Key" "" "INPUT"; sed -i "s/OPENAI_API_KEY=.*/OPENAI_API_KEY=\"$INPUT\"/g" .env ;;
    *) prompt_user "Enter Gemini Key" "" "INPUT"; sed -i "s/GEMINI_API_KEY=.*/GEMINI_API_KEY=\"$INPUT\"/g" .env ;;
esac

# 5. Path Alignment
PROJECT_ROOT=$(pwd)
PARENT_DIR=$(dirname "$PROJECT_ROOT")
sed -i "s|MEMEX_DIR=.*|MEMEX_DIR=\"$PARENT_DIR\"|g" .env
sed -i "s|ZETTELKASTEN_DIR=.*|ZETTELKASTEN_DIR=\"$PARENT_DIR/notes\"|g" .env
sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$PROJECT_ROOT/skills\"|g" .env

mkdir -p "$PARENT_DIR/notes"
echo -e "${GREEN}✓ Configuration complete.${NC}"

# 6. Final Instructions
echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}    OpenCortex Installation Complete!        ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Your brain is ready to boot."
echo -e "\nTo start the session: ${YELLOW}./opencortex.sh${NC}"
echo -e "To add API keys later, edit: ${YELLOW}$(pwd)/.env${NC}\n"
