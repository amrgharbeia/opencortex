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
    echo -e "${BLUE}! .env already exists. Skipping creation.${NC}"
fi

# Set MEMEX_DIR automatically to current parent if not set
PROJECT_ROOT=$(pwd)
PARENT_DIR=$(dirname "$PROJECT_ROOT")

# Use a temporary file for editing .env to be safe
sed -i "s|MEMEX_DIR=\"/memex\"|MEMEX_DIR=\"$PARENT_DIR\"|g" .env
sed -i "s|ZETTELKASTEN_DIR=\"/memex/notes\"|ZETTELKASTEN_DIR=\"$PARENT_DIR/notes\"|g" .env
sed -i "s|SKILLS_DIR=\"/memex/notes\"|SKILLS_DIR=\"$PARENT_DIR/notes\"|g" .env
sed -i "s|INBOX_DIR=\"/memex/inbox\"|INBOX_DIR=\"$PARENT_DIR/inbox\"|g" .env
sed -i "s|DAILY_DIR=\"/memex/daily\"|DAILY_DIR=\"$PARENT_DIR/daily\"|g" .env
sed -i "s|PROJECTS_DIR=\"/memex/projects\"|PROJECTS_DIR=\"$PARENT_DIR/projects\"|g" .env
sed -i "s|SYSTEM_DIR=\"/memex/system\"|SYSTEM_DIR=\"$PARENT_DIR/system\"|g" .env

echo -e "${GREEN}✓ Absolute paths normalized to: $PARENT_DIR${NC}"

# 3. Model Strategy
echo -e "\n${BLUE}[3/5] Primary LLM Configuration...${NC}"
echo "Select your primary neural provider:"
echo "1) Google Gemini (Free Tier / Official)"
echo "2) OpenRouter (Unified / Paid)"
echo "3) Anthropic (Claude / API Key)"
echo "4) OpenAI (GPT / API Key)"
read -p "Choice [1-4]: " LLM_CHOICE

case $LLM_CHOICE in
    2)
        read -p "Enter OpenRouter API Key: " OR_KEY
        sed -i "s/OPENROUTER_API_KEY=\"your_openrouter_key_here\"/OPENROUTER_API_KEY=\"$OR_KEY\"/g" .env
        echo -e "${GREEN}✓ OpenRouter configured.${NC}"
        ;;
    3)
        read -p "Enter Anthropic API Key: " ANTH_KEY
        sed -i "s/LLM_API_KEY=\"your_api_key_here\"/LLM_API_KEY=\"$ANTH_KEY\"/g" .env
        sed -i "s|LLM_ENDPOINT=.*|LLM_ENDPOINT=\"https://api.anthropic.com/v1/messages\"|g" .env
        echo -e "${GREEN}✓ Anthropic configured.${NC}"
        ;;
    4)
        read -p "Enter OpenAI API Key: " OPENAI_KEY
        sed -i "s/LLM_API_KEY=\"your_api_key_here\"/LLM_API_KEY=\"$OPENAI_KEY\"/g" .env
        sed -i "s|LLM_ENDPOINT=.*|LLM_ENDPOINT=\"https://api.openai.com/v1/chat/completions\"|g" .env
        echo -e "${GREEN}✓ OpenAI configured.${NC}"
        ;;
    *)
        read -p "Enter Gemini API Key (or leave blank for OAuth): " GEM_KEY
        if [ ! -z "$GEM_KEY" ]; then
            sed -i "s/LLM_API_KEY=\"your_api_key_here\"/LLM_API_KEY=\"$GEM_KEY\"/g" .env
        fi
        echo -e "${GREEN}✓ Gemini primary selected.${NC}"
        ;;
esac

# 4. Identity & Channels
echo -e "\n${BLUE}[4/5] Identity & Delivery Channels...${NC}"
read -p "What is your name? (default: User): " USER_NAME
USER_NAME=${USER_NAME:-User}
read -p "What shall we name your Assistant? (default: Agent): " AGENT_NAME
AGENT_NAME=${AGENT_NAME:-Agent}

sed -i "s/MEMEX_USER=\"YourName\"/MEMEX_USER=\"$USER_NAME\"/g" .env
sed -i "s/MEMEX_ASSISTANT=\"AgentName\"/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

echo "Configure primary delivery channel (optional):"
echo "1) Signal"
echo "2) Telegram"
echo "3) Discord"
echo "4) None / Local Only"
read -p "Choice [1-4]: " CHANNEL_CHOICE

if [ "$CHANNEL_CHOICE" != "4" ]; then
    read -p "Enter Recipient ID (e.g. phone number or handle): " RECIPIENT
    sed -i "s/RECIPIENT_ID=\"+1...\"/RECIPIENT_ID=\"$RECIPIENT\"/g" .env
    echo -e "${GREEN}✓ Delivery channel configured for $RECIPIENT.${NC}"
fi

# 5. Skill Seeding
echo -e "\n${BLUE}[5/5] Seeding Core Skills...${NC}"
NOTES_DIR="$PARENT_DIR/notes"
mkdir -p "$NOTES_DIR"

# Core skills (The Standard Library)
echo -e "Installing Standard Library from projects/org-agent/skills/..."
for skill_path in skills/*.org; do
    skill_name=$(basename "$skill_path")
    if [[ "$1" == "--dev" ]]; then
        ln -sf "$PROJECT_ROOT/$skill_path" "$NOTES_DIR/$skill_name"
        echo -e "  Linked: $skill_name"
    else
        cp -n "$skill_path" "$NOTES_DIR/$skill_name"
        echo -e "  Copied: $skill_name"
    fi
done

# Contrib skills (The Ecosystem)
CONTRIB_DIR="$PARENT_DIR/projects/org-agent-contrib"
if [ -d "$CONTRIB_DIR" ]; then
    echo -e "\n${BLUE}Ecosystem Skills detected in projects/org-agent-contrib/.${NC}"
    read -p "Would you like to install additional domain skills? [y/N]: " INSTALL_CONTRIB
    if [[ "$INSTALL_CONTRIB" =~ ^[Yy]$ ]]; then
        for skill_path in "$CONTRIB_DIR"/*.org; do
            skill_name=$(basename "$skill_path")
            if [[ "$1" == "--dev" ]]; then
                ln -sf "$skill_path" "$NOTES_DIR/$skill_name"
                echo -e "  Linked: $skill_name"
            else
                cp -n "$skill_path" "$NOTES_DIR/$skill_name"
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
