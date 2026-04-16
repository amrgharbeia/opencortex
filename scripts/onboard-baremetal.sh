#!/bin/bash
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=== opencortex: Baremetal Power-User Setup ===${NC}"

# 1. Dependency Management
install_deps() {
    if command -v apt-get >/dev/null; then
        sudo apt-get update && sudo apt-get install -y sbcl emacs git curl socat
    elif command -v pacman >/dev/null; then
        sudo pacman -S --noconfirm sbcl emacs git curl socat
    elif command -v dnf >/dev/null; then
        sudo dnf install -y sbcl emacs git curl socat
    elif command -v brew >/dev/null; then
        brew install sbcl emacs git curl socat
    else
        echo -e "${RED}✗ Unknown package manager. Please install SBCL and Emacs manually.${NC}"
        exit 1
    fi
}

if ! command -v sbcl >/dev/null 2>&1 || ! command -v emacs >/dev/null 2>&1; then
    echo -e "${YELLOW}! Missing dependencies (SBCL/Emacs).${NC}"
    read -p "Should I attempt to install them for you? [Y/n]: " INSTALL_CHOICE < /dev/tty
    if [[ ! "$INSTALL_CHOICE" =~ ^[Nn]$ ]]; then
        install_deps
    else
        echo -e "${RED}✗ Dependencies required. Exiting.${NC}"
        exit 1
    fi
fi

# 2. Quicklisp Installation
if [ ! -d "$HOME/quicklisp" ] && [ ! -d "$HOME/.quicklisp" ]; then
    echo -e "${YELLOW}! Quicklisp not found.${NC}"
    read -p "Install Quicklisp now? [Y/n]: " QL_CHOICE < /dev/tty
    if [[ ! "$QL_CHOICE" =~ ^[Nn]$ ]]; then
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp \
             --eval "(quicklisp-quickstart:install)" \
             --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
        echo -e "${GREEN}✓ Quicklisp installed.${NC}"
    fi
fi

# 3. Literate Tangling
echo -e "${BLUE}Tangling Literate Org files into source code...${NC}"
# Use || true because Emacs might return non-zero on warnings, but we only care if src/ actually gets populated
emacs --batch --eval "(require 'org)" --eval "(mapc 'org-babel-tangle-file (file-expand-wildcards \"literate/*.org\"))" || echo -e "${YELLOW}! Emacs finished with warnings.${NC}"

if [ ! -f "src/package.lisp" ]; then
    echo -e "${RED}✗ Tangling failed. Source files not generated.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Core tangled.${NC}"

# 4. Environment Configuration
if [ ! -f .env ]; then cp .env.example .env; fi

read -p "What is your name? (default: User): " USER_NAME < /dev/tty
USER_NAME=${USER_NAME:-User}
sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env

read -p "What shall we name your Assistant? (default: OpenCortex): " AGENT_NAME < /dev/tty
AGENT_NAME=${AGENT_NAME:-OpenCortex}
sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

echo -e "\nSelect primary neural provider:"
echo "1) Gemini (Free/Official)"; echo "2) OpenRouter"; echo "3) Anthropic"; echo "4) OpenAI"
read -p "Choice [1-4]: " LLM_CHOICE < /dev/tty
case $LLM_CHOICE in
    2) read -p "Enter OpenRouter Key: " INPUT < /dev/tty; sed -i "s/OPENROUTER_API_KEY=.*/OPENROUTER_API_KEY=\"$INPUT\"/g" .env ;;
    3) read -p "Enter Anthropic Key: " INPUT < /dev/tty; sed -i "s/ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=\"$INPUT\"/g" .env ;;
    4) read -p "Enter OpenAI Key: " INPUT < /dev/tty; sed -i "s/OPENAI_API_KEY=.*/OPENAI_API_KEY=\"$INPUT\"/g" .env ;;
    *) read -p "Enter Gemini Key: " INPUT < /dev/tty; sed -i "s/GEMINI_API_KEY=.*/GEMINI_API_KEY=\"$INPUT\"/g" .env ;;
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
echo -e "\n${BLUE}=== Setup Complete ===${NC}"
echo -e "To start the harness: ${YELLOW}./opencortex.sh${NC}"
echo -e "To run tests: ${YELLOW}sbcl --eval '(ql:quickload :opencortex)' --eval '(asdf:test-system :opencortex)'${NC}"
