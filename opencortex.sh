#!/bin/bash
set -e

PORT=9105
HOST=${1:-localhost}

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

command_exists() { command -v "$1" >/dev/null 2>&1; }

# 1. Try to drop straight into the CLI chat
if command_exists socat && socat - TCP:$HOST:$PORT,connect-timeout=1 2>/dev/null; then
    echo -e "${BLUE}Connected to autonomous brain at $HOST:$PORT...${NC}"
    # Use socat with READLINE for history and arrow-key support.
    # It establishes a persistent bidirectional connection.
    socat READLINE,history=$HOME/.org_agent_history TCP:$HOST:$PORT
    exit 0
elif command_exists nc && nc -z $HOST $PORT 2>/dev/null; then
    echo -e "${YELLOW}socat not found. Falling back to nc (no line-editing).${NC}"
    echo -e "${BLUE}Connected to autonomous brain at $HOST:$PORT...${NC}"
    while true; do
        read -p "User: " MESSAGE
        if [ -z "$MESSAGE" ]; then continue; fi
        echo "$MESSAGE" | nc -N $HOST $PORT
    done
    exit 0
fi

# 2. Check if we have an existing installation we can boot
if [ -f "$HOME/.opencortex-path" ]; then
    INSTALL_DIR=$(cat "$HOME/.opencortex-path")
    if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        echo -e "${YELLOW}Daemon is offline. Booting from $INSTALL_DIR...${NC}"
        cd "$INSTALL_DIR"
        docker-compose up -d
        echo "Waiting for brain to initialize..."
        sleep 5
        # Re-run to enter chat
        exec "$0" "$@"
    fi
fi

# 3. If we are running this inside a cloned repo, configure and boot
if [ -f "docker-compose.yml" ] && [ -d "literate" ]; then
    echo -e "${YELLOW}Local repository detected. Ensuring configuration...${NC}"
    INSTALL_DIR=$(pwd)
    echo "$INSTALL_DIR" > "$HOME/.opencortex-path"
    
    if [ ! -f .env ]; then
        cp .env.example .env
        read -p "What is your name? (default: User): " USER_NAME
        USER_NAME=${USER_NAME:-User}
        sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env

        read -p "What shall we name your Assistant? (default: Agent): " AGENT_NAME
        AGENT_NAME=${AGENT_NAME:-Agent}
        sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

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
        echo -e "\n${BLUE}Seeding Skills...${NC}"
        MEMEX_TARGET=$(dirname $(dirname "$INSTALL_DIR"))
        SKILLS_DIR="$MEMEX_TARGET/notes"
        mkdir -p "$SKILLS_DIR"
        cp -n skills/*.org "$SKILLS_DIR/" 2>/dev/null || true
        echo -e "${GREEN}✓ Core skills seeded to $SKILLS_DIR.${NC}"
    fi
    
    docker-compose up -d --build
    echo "Waiting for brain to initialize..."
    sleep 5
    exec "$0" "$@"
fi

# 4. Zero-to-One Onboarding (No installation found)
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} opencortex: Autonomous Intelligence Onboarding     ${NC}"
echo -e "${BLUE}==================================================${NC}"

# --- OS & Docker Detection ---
echo -e "\n${BLUE}[1/2] Verifying Environment...${NC}"

install_docker() {
    echo -e "${YELLOW}Docker is required to run opencortex natively without messy dependencies.${NC}"
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
echo -e "\n${BLUE}[2/2] Downloading Kernel...${NC}"
MEMEX_DEFAULT="$HOME/memex"
read -p "Where is your Memex located? (default: $MEMEX_DEFAULT): " MEMEX_TARGET
MEMEX_TARGET=${MEMEX_TARGET:-$MEMEX_DEFAULT}

mkdir -p "$MEMEX_TARGET/projects"
cd "$MEMEX_TARGET/projects"

if [ ! -d "opencortex" ]; then
    echo "Cloning opencortex..."
    git clone https://github.com/gharbeia/opencortex.git
    cd opencortex
else
    echo -e "${GREEN}✓ Repository already exists.${NC}"
    cd opencortex
    git pull origin main
fi

mkdir -p "$HOME/.local/bin"
ln -sf "$(pwd)/opencortex.sh" "$HOME/.local/bin/opencortex"
echo -e "${GREEN}✓ Installed 'opencortex' command to ~/.local/bin${NC}"

# Ensure proper ownership if sudo was used for apt
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER" "$MEMEX_TARGET/projects/opencortex"
fi

# Execute the newly cloned script to run configuration (Step 3)
exec ./opencortex.sh
