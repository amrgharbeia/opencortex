#!/bin/bash
# OpenCortex Final-Mile Installer
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'
echo -e "${BLUE}=== OpenCortex: Baremetal Power-User Setup ===${NC}"

prompt_user() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local result=""
    echo -n -e "${YELLOW}$prompt (default: $default): ${NC}" >&2
    if read -t 5 result; then :; else result="$default"; echo -e "${BLUE} [Auto-Selected: $default]${NC}" >&2 fi
    val=${result:-$default}
    eval "$var_name=\"$val\""
}

if ! command -v sbcl >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y sbcl emacs git curl socat || true
fi

if [ ! -d "$HOME/quicklisp" ]; then
    curl -O https://beta.quicklisp.org/quicklisp.lisp
    sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" --eval "(ql-util:without-prompting (ql:add-to-init-file))"
    rm quicklisp.lisp
fi

echo -e "${BLUE}Tangling source files...${NC}"
mkdir -p src
for f in literate/*.org; do
    emacs --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1
done

if [ ! -f .env ]; then cp .env.example .env; fi
prompt_user "What is your name?" "User" "USER_NAME"
prompt_user "What shall we name your Assistant?" "OpenCortex" "AGENT_NAME"
prompt_user "Select provider (1:Gemini, 2:OpenRouter)" "1" "LLM_CHOICE"

sed -i "s/MEMEX_USER=.*/MEMEX_USER=\"$USER_NAME\"/g" .env
sed -i "s/MEMEX_ASSISTANT=.*/MEMEX_ASSISTANT=\"$AGENT_NAME\"/g" .env

ROOT_DIR=$(pwd)
sed -i "s|MEMEX_DIR=.*|MEMEX_DIR=\"$(dirname $ROOT_DIR)\"|g" .env
sed -i "s|SKILLS_DIR=.*|SKILLS_DIR=\"$ROOT_DIR/skills\"|g" .env

mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT_DIR/opencortex.sh" "$HOME/.local/bin/opencortex"
echo -e "${GREEN}✓ Installed 'opencortex' command to ~/.local/bin${NC}"

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}    OpenCortex Installation Complete!        ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "To start: opencortex"
