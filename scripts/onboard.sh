#!/bin/bash

# org-agent Onboarding Script: The First Breath
# This script prepares your PSF environment for the Lisp Machine.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} org-agent: Personal Software Foundry Onboarding  ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. Environment Verification
echo -e "\n${BLUE}[1/5] Verifying Environment...${NC}"

if command -v sbcl >/dev/null 2>&1; then
    echo -e "${GREEN}✓ SBCL (Steel Bank Common Lisp) found.${NC}"
else
    echo -e "${RED}✗ SBCL not found. Please install it first.${NC}"
    exit 1
fi

if [ -d "$HOME/quicklisp" ] || [ -d "$HOME/.quicklisp" ]; then
    echo -e "${GREEN}✓ Quicklisp found.${NC}"
else
    echo -e "${RED}✗ Quicklisp not found. Please install Quicklisp to manage Lisp dependencies.${NC}"
    exit 1
fi

# 2. Configuration Setup
echo -e "\n${BLUE}[2/5] Setting up .env configuration...${NC}"

if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${GREEN}✓ Created .env from .env.example.${NC}"
else
    echo -e "${BLUE}! .env already exists. Loading existing values.${NC}"
fi

# Function to get value from .env without quotes
get_env_val() {
    local key=$1
    local val=$(grep "^${key}=" .env | cut -d'=' -f2- | sed 's/^"//;s/"$//;s/^\x27//;s/\x27$//')
    echo "$val"
}

# Load variables
MEMEX_DIR=$(get_env_val "MEMEX_DIR")
SKILLS_DIR=$(get_env_val "SKILLS_DIR")

# If MEMEX_DIR is still the default or empty, normalize it to the parent of the project
PROJECT_ROOT=$(pwd)
PARENT_DIR=$(dirname "$PROJECT_ROOT")

if [[ -z "$MEMEX_DIR" || "$MEMEX_DIR" == "/memex" ]]; then
    MEMEX_DIR="$PARENT_DIR"
    sed -i "s|MEMEX_DIR=.*|MEMEX_DIR=\"$MEMEX_DIR\"|g" .env
    sed -i "s|ZETTELKASTEN_DIR=.*|ZETTELKASTEN_DIR=\"$MEMEX_DIR/notes\"|g" .env
    sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$MEMEX_DIR/notes\"|g" .env
    sed -i "s|INBOX_DIR=.*|INBOX_DIR=\"$MEMEX_DIR/inbox\"|g" .env
    sed -i "s|DAILY_DIR=.*|DAILY_DIR=\"$MEMEX_DIR/daily\"|g" .env
    sed -i "s|PROJECTS_DIR=.*|PROJECTS_DIR=\"$MEMEX_DIR/projects\"|g" .env
    sed -i "s|SYSTEM_DIR=.*|SYSTEM_DIR=\"$MEMEX_DIR/system\"|g" .env
    echo -e "${GREEN}✓ Paths normalized to: $MEMEX_DIR${NC}"
    # Refresh SKILLS_DIR after normalization
    SKILLS_DIR=$(get_env_val "SKILLS_DIR")
fi

# 3. Model Strategy
echo -e "\n${BLUE}[3/5] Primary LLM Configuration...${NC}"
LLM_KEY=$(get_env_val "LLM_API_KEY")
OR_KEY=$(get_env_val "OPENROUTER_API_KEY")

if [[ ! -z "$LLM_KEY" && "$LLM_KEY" != "your_api_key_here" ]] || [[ ! -z "$OR_KEY" && "$OR_KEY" != "your_openrouter_key_here" ]]; then
    echo -e "${GREEN}✓ Neural provider already configured in .env.${NC}"
else
    echo "Select your primary neural provider:"
    echo "1) Google Gemini (Free Tier / Official)"
    echo "2) OpenRouter (Unified / Paid)"
    echo "3) Anthropic (Claude / API Key)"
    echo "4) OpenAI (GPT / API Key)"
    read -p "Choice [1-4]: " LLM_CHOICE

    case $LLM_CHOICE in
        2)
            read -p "Enter OpenRouter API Key: " OR_KEY_INPUT
            sed -i "s/OPENROUTER_API_KEY=.*/OPENROUTER_API_KEY=\"$OR_KEY_INPUT\"/g" .env
            echo -e "${GREEN}✓ OpenRouter configured.${NC}"
            ;;
        3)
            read -p "Enter Anthropic API Key: " ANTH_KEY
            sed -i "s/LLM_API_KEY=.*/LLM_API_KEY=\"$ANTH_KEY\"/g" .env
            sed -i "s|LLM_ENDPOINT=.*|LLM_ENDPOINT=\"https://api.anthropic.com/v1/messages\"|g" .env
            echo -e "${GREEN}✓ Anthropic configured.${NC}"
            ;;
        4)
            read -p "Enter OpenAI API Key: " OPENAI_KEY
            sed -i "s/LLM_API_KEY=.*/LLM_API_KEY=\"$OPENAI_KEY\"/g" .env
            sed -i "s|LLM_ENDPOINT=.*|LLM_ENDPOINT=\"https://api.openai.com/v1/chat/completions\"|g" .env
            echo -e "${GREEN}✓ OpenAI configured.${NC}"
            ;;
        *)
            read -p "Enter Gemini API Key (or leave blank for OAuth): " GEM_KEY
            if [ ! -z "$GEM_KEY" ]; then
                sed -i "s/LLM_API_KEY=.*/LLM_API_KEY=\"$GEM_KEY\"/g" .env
            fi
            echo -e "${GREEN}✓ Gemini selected.${NC}"
            ;;
    esac
fi

# 4. Identity
echo -e "\n${BLUE}[4/5] Identity Setup...${NC}"
CURRENT_USER=$(get_env_val "MEMEX_USER")
if [[ "$CURRENT_USER" == "YourName" || -z "$CURRENT_USER" ]]; then
    read -p "What is your name? (default: User): " USER_NAME
    USER_NAME=${USER_NAME:-User}
    read -p "What shall we name your Assistant? (default: Agent): " AGENT_NAME
    AGENT_NAME=${AGENT_NAME:-Agent}

    sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env
    sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env
else
    echo -e "${GREEN}✓ Identity already set: $CURRENT_USER${NC}"
fi

# 5. Skill Seeding
echo -e "\n${BLUE}[5/5] Seeding Skills...${NC}"
# Use SKILLS_DIR from .env, expanding $HOME if necessary
REAL_SKILLS_DIR=$(echo "$SKILLS_DIR" | sed "s|\$HOME|$HOME|g")
mkdir -p "$REAL_SKILLS_DIR"

echo -e "Installing Standard Library to $REAL_SKILLS_DIR..."
for skill_path in skills/*.org; do
    skill_name=$(basename "$skill_path")
    if [[ "$1" == "--dev" ]]; then
        ln -sf "$PROJECT_ROOT/$skill_path" "$REAL_SKILLS_DIR/$skill_name"
        echo -e "  Linked: $skill_name"
    else
        cp -n "$skill_path" "$REAL_SKILLS_DIR/$skill_name"
        echo -e "  Copied: $skill_name"
    fi
done

# Contrib skills
CONTRIB_DIR="$PROJECT_ROOT/../org-agent-contrib"
if [ -d "$CONTRIB_DIR" ]; then
    echo -e "\n${BLUE}Ecosystem Skills detected in $CONTRIB_DIR.${NC}"
    read -p "Would you like to install additional domain skills? [y/N]: " INSTALL_CONTRIB
    if [[ "$INSTALL_CONTRIB" =~ ^[Yy]$ ]]; then
        for skill_path in "$CONTRIB_DIR"/*.org; do
            skill_name=$(basename "$skill_path")
            if [[ "$1" == "--dev" ]]; then
                ln -sf "$skill_path" "$REAL_SKILLS_DIR/$skill_name"
                echo -e "  Linked: $skill_name"
            else
                cp -n "$skill_path" "$REAL_SKILLS_DIR/$skill_name"
                echo -e "  Copied: $skill_name"
            fi
        done
    fi
fi

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN} Onboarding Complete!                             ${NC}"
echo -e "${GREEN} Your sovereign brain is ready to boot.           ${NC}"
echo -e "${GREEN} Next: Start the daemon with 'make run'.          ${NC}"
echo -e "${GREEN}==================================================${NC}"
