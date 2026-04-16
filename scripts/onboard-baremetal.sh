#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

echo -e "${BLUE}=== OpenCortex: Baremetal Power-User Setup ===${NC}"

# Robust Non-Blocking Prompt
prompt_user() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local result=""
    
    echo -n -e "${YELLOW}$prompt (default: $default): ${NC}" >&2
    
    # Try reading from stdin with a 2-second timeout
    if read -t 2 result; then
        :
    else
        result="$default"
        echo -e "${BLUE} [Defaulting to $default]${NC}" >&2
    fi
    
    val=${result:-$default}
    eval "$var_name=\"$val\""
}

# 1. Dependency Management
if ! command -v sbcl >/dev/null 2>&1 || ! command -v emacs >/dev/null 2>&1; then
    echo -e "${BLUE}Installing dependencies...${NC}"
    if command -v apt-get >/dev/null; then
        sudo apt-get update && sudo apt-get install -y sbcl emacs git curl socat
    fi
fi

# 2. Quicklisp
if [ ! -d "$HOME/quicklisp" ]; then
    echo -e "${BLUE}Installing Quicklisp...${NC}"
    curl -O https://beta.quicklisp.org/quicklisp.lisp
    sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" --eval "(ql-util:without-prompting (ql:add-to-init-file))"
    rm quicklisp.lisp
fi

# 3. Tangling
echo -e "${BLUE}Tangling source files...${NC}"
mkdir -p src
for f in literate/*.org; do
    echo "  - $f"
    emacs --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1
done

if [ -f "src/package.lisp" ]; then
    echo -e "${GREEN}✓ Core tangled successfully.${NC}"
else
    echo -e "${RED}✗ Tangle failed!${NC}"
    exit 1
fi

# 4. Configuration
if [ ! -f .env ]; then cp .env.example .env; fi

prompt_user "What is your name?" "User" "USER_NAME"
prompt_user "What shall we name your Assistant?" "OpenCortex" "AGENT_NAME"
prompt_user "Select provider (1:Gemini, 2:OpenRouter)" "1" "LLM_CHOICE"

sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env
sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

# Path Alignment
sed -i "s|MEMEX_DIR=.*|MEMEX_DIR=\"$(dirname $(pwd))\"|g" .env
sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$(pwd)/skills\"|g" .env

echo -e "\n${GREEN}=== OpenCortex Ready ===${NC}"
