#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} org-agent: Sovereign Intelligence Onboarding     ${NC}"
echo -e "${BLUE}==================================================${NC}"

# --- OS & Docker Detection ---
echo -e "\n${BLUE}[1/4] Verifying Environment...${NC}"

command_exists() { command -v "$1" >/dev/null 2>&1; }

install_docker() {
    echo -e "${YELLOW}Docker is required to run org-agent natively without messy dependencies.${NC}"
    read -p "Would you like me to attempt to install Docker? [Y/n]: " install_choice
    install_choice=${install_choice:-Y}
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command_exists apt-get; then
                echo "Installing Docker via apt..."
                sudo apt-get update
                sudo apt-get install -y docker.io docker-compose
            elif command_exists dnf; then
                echo "Installing Docker via dnf..."
                sudo dnf install -y docker docker-compose
                sudo systemctl start docker
                sudo systemctl enable docker
            else
                echo -e "${RED}Unsupported package manager. Please install Docker manually.${NC}"
                exit 1
            fi
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            if command_exists brew; then
                echo "Installing Docker Desktop via Homebrew..."
                brew install --cask docker
                echo -e "${YELLOW}Please start Docker Desktop from your Applications folder, then re-run this script.${NC}"
                exit 0
            else
                echo -e "${RED}Homebrew not found. Please install Docker Desktop for Mac manually.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Unsupported OS for automated Docker installation. Please install manually.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Docker is required. Aborting.${NC}"
        exit 1
    fi
}

if ! command_exists docker || ! command_exists docker-compose; then
    install_docker
else
    echo -e "${GREEN}✓ Docker and docker-compose detected.${NC}"
fi

# --- Repository Setup ---
echo -e "\n${BLUE}[2/4] Downloading Kernel...${NC}"
MEMEX_DEFAULT="$HOME/memex"
read -p "Where is your Memex located? (default: $MEMEX_DEFAULT): " MEMEX_TARGET
MEMEX_TARGET=${MEMEX_TARGET:-$MEMEX_DEFAULT}

mkdir -p "$MEMEX_TARGET/projects"
cd "$MEMEX_TARGET/projects"

if [ ! -d "org-agent" ]; then
    echo "Cloning org-agent..."
    git clone https://github.com/gharbeia/org-agent.git
    cd org-agent
else
    echo -e "${GREEN}✓ Repository already exists.${NC}"
    cd org-agent
    git pull origin main
fi

# --- Interactive Configuration ---
echo -e "\n${BLUE}[3/4] Neural & Identity Calibration...${NC}"
if [ ! -f .env ]; then
    cp .env.example .env
fi

# Ask for Name
read -p "What is your name? (default: User): " USER_NAME
USER_NAME=${USER_NAME:-User}
sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env

# Ask for Assistant Name
read -p "What shall we name your Assistant? (default: Agent): " AGENT_NAME
AGENT_NAME=${AGENT_NAME:-Agent}
sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

# Ask for LLM
echo -e "\nSelect your primary neural provider:"
echo "1) Google Gemini (Free Tier / Official)"
echo "2) OpenRouter (Unified / Paid)"
echo "3) Anthropic (Claude / API Key)"
echo "4) OpenAI (GPT / API Key)"
read -p "Choice [1-4]: " LLM_CHOICE

case $LLM_CHOICE in
    2) read -p "Enter OpenRouter API Key: " INPUT; sed -i "s/OPENROUTER_API_KEY=.*/OPENROUTER_API_KEY=\"$INPUT\"/g" .env ;;
    3) read -p "Enter Anthropic API Key: " INPUT; sed -i "s/ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=\"$INPUT\"/g" .env ;;
    4) read -p "Enter OpenAI API Key: " INPUT; sed -i "s/OPENAI_API_KEY=.*/OPENAI_API_KEY=\"$INPUT\"/g" .env ;;
    *) read -p "Enter Gemini API Key: " INPUT; sed -i "s/GEMINI_API_KEY=.*/GEMINI_API_KEY=\"$INPUT\"/g" .env ;;
esac

# Seed Core Skills
echo -e "\n${BLUE}[4/4] Seeding Skills...${NC}"
# In Docker, the host's memex maps to /memex. The skills should be saved in the host's memex notes folder.
SKILLS_DIR="$MEMEX_TARGET/notes"
mkdir -p "$SKILLS_DIR"
cp -n skills/*.org "$SKILLS_DIR/" 2>/dev/null || true
echo -e "${GREEN}✓ Core skills seeded to $SKILLS_DIR.${NC}"

# Ensure proper ownership if sudo was used for apt
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER" "$MEMEX_TARGET/projects/org-agent"
fi

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN} Onboarding Complete!                             ${NC}"
echo -e "${GREEN} Booting your sovereign brain in the background...${NC}"
echo -e "${GREEN}==================================================${NC}"

# Launch
docker-compose up -d --build
echo -e "\n${YELLOW}To view logs, run: cd $MEMEX_TARGET/projects/org-agent && docker-compose logs -f${NC}"
