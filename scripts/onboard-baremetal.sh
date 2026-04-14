#!/bin/bash
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=== org-agent: Baremetal Power-User Setup ===${NC}"

if ! command -v sbcl >/dev/null 2>&1; then
    echo -e "${RED}✗ SBCL not found. Please install it first.${NC}"
    exit 1
fi

if [ ! -d "$HOME/quicklisp" ] && [ ! -d "$HOME/.quicklisp" ]; then
    echo -e "${RED}✗ Quicklisp not found. Please install Quicklisp.${NC}"
    exit 1
fi

if [ ! -f .env ]; then cp .env.example .env; fi

read -p "What is your name? (default: User): " USER_NAME
USER_NAME=${USER_NAME:-User}
sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env

read -p "What shall we name your Assistant? (default: Agent): " AGENT_NAME
AGENT_NAME=${AGENT_NAME:-Agent}
sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

echo "Select primary neural provider:"
echo "1) Gemini"; echo "2) OpenRouter"; echo "3) Anthropic"; echo "4) OpenAI"
read -p "Choice [1-4]: " LLM_CHOICE
case $LLM_CHOICE in
    2) read -p "Enter OpenRouter Key: " INPUT; sed -i "s/OPENROUTER_API_KEY=.*/OPENROUTER_API_KEY=\"$INPUT\"/g" .env ;;
    3) read -p "Enter Anthropic Key: " INPUT; sed -i "s/ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=\"$INPUT\"/g" .env ;;
    4) read -p "Enter OpenAI Key: " INPUT; sed -i "s/OPENAI_API_KEY=.*/OPENAI_API_KEY=\"$INPUT\"/g" .env ;;
    *) read -p "Enter Gemini Key: " INPUT; sed -i "s/GEMINI_API_KEY=.*/GEMINI_API_KEY=\"$INPUT\"/g" .env ;;
esac

# Update baremetal paths based on current directory structure
PROJECT_ROOT=$(pwd)
PARENT_DIR=$(dirname "$PROJECT_ROOT")
sed -i "s|MEMEX_DIR=.*|MEMEX_DIR=\"$PARENT_DIR\"|g" .env
sed -i "s|ZETTELKASTEN_DIR=.*|ZETTELKASTEN_DIR=\"$PARENT_DIR/notes\"|g" .env
sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$PARENT_DIR/notes\"|g" .env

mkdir -p "$PARENT_DIR/notes"
cp -n skills/*.org "$PARENT_DIR/notes/" 2>/dev/null || true

echo -e "${GREEN}Baremetal setup complete. Run 'make run' to start.${NC}"
