#!/bin/bash
set -e

PORT=9105
HOST="localhost"
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

command_exists() { command -v "$1" >/dev/null 2>&1; }

# 1. XDG PATH RESOLUTION
# SCRIPT_DIR is the immutable source (where the git repo lives)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
export SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# XDG Defaults
export OC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencortex"
export OC_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/opencortex"
export OC_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/opencortex"
export OC_BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"

# Dynamic defaults for Skill Engine and Project Root
export SKILLS_DIR="${SKILLS_DIR:-$OC_DATA_DIR/skills}"
export MEMEX_DIR="${MEMEX_DIR:-$HOME/memex}"

# Load environment variables from the standard config location
if [ -f "$OC_CONFIG_DIR/.env" ]; then
    source "$OC_CONFIG_DIR/.env"
fi

# --- 2. SETUP ---
setup_system() {
    NON_INTERACTIVE=false
    for arg in "$@"; do
        if [ "$arg" == "--non-interactive" ]; then NON_INTERACTIVE=true; fi
    done

    echo -e "${BLUE}=== OpenCortex: Initializing XDG-Compliant System ===${NC}"
    
    # Create standard directories
    mkdir -p "$OC_CONFIG_DIR" "$OC_DATA_DIR" "$OC_STATE_DIR" "$OC_BIN_DIR"
    mkdir -p "$OC_DATA_DIR/harness" "$OC_DATA_DIR/tests" "$OC_DATA_DIR/skills" "$OC_DATA_DIR/library"

    echo -e "${YELLOW}--- Installing System Dependencies ---${NC}"
    if command_exists apt-get; then
        sudo apt-get update && sudo apt-get install -y sbcl emacs-nox rlwrap netcat-openbsd curl git socat libssl-dev libncurses-dev libffi-dev zlib1g-dev libsqlite3-dev
    fi
    if [ ! -d "$HOME/quicklisp" ]; then
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
    fi

    # Tangle the literate source from SCRIPT_DIR to OC_DATA_DIR (The Engine)
    echo -e "${YELLOW}--- Deploying Engine to $OC_DATA_DIR ---${NC}"
    cp "$SCRIPT_DIR/opencortex.asd" "$OC_DATA_DIR/"
    cp "$SCRIPT_DIR/harness"/*.org "$OC_DATA_DIR/harness/"
    cp "$SCRIPT_DIR/skills"/*.org "$OC_DATA_DIR/skills/"

    cd "$SCRIPT_DIR"
    export INSTALL_DIR="$OC_DATA_DIR"

    # Critical: Tangle manifest first to establish system structure
    echo "Tangling harness/manifest.org..."
    emacs -Q --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"harness/manifest.org\")" >/dev/null 2>&1 || true

    for f in harness/*.org skills/*.org; do
        if [ "$f" != "harness/manifest.org" ]; then
            echo "Tangling $f..."
            emacs -Q --batch --eval "(require 'org)" --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1 || true
        fi
    done
    # Create the bin shim
    echo -e "${YELLOW}--- Creating Bin Shim in $OC_BIN_DIR/opencortex ---${NC}"
    ln -sf "$SCRIPT_DIR/opencortex.sh" "$OC_BIN_DIR/opencortex"

    if [ "$NON_INTERACTIVE" = true ]; then
        echo "Setup complete (Non-interactive)."
        exit 0
    fi

    echo -e "${YELLOW}--- Launching Lisp Setup Wizard ---${NC}"
    # Use OC_DATA_DIR for the Lisp registry
    exec sbcl --non-interactive \
         --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
         --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
         --eval '(ql:quickload :opencortex)' \
         --eval '(opencortex:run-setup-wizard)'
}

# --- 3. COMMAND ROUTER ---
COMMAND=$1
[ -z "$COMMAND" ] && COMMAND="cli"
shift || true

case "$COMMAND" in
    link)
        PLATFORM=$1
        TOKEN=$2
        exec sbcl --non-interactive              --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))'              --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)"              --eval '(ql:quickload :opencortex)'              --eval "(opencortex:gateway-manager-main \"$PLATFORM\" \"$TOKEN\")"
        ;;

    doctor)
        exec sbcl --non-interactive \
             --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
             --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
             --eval '(ql:quickload :opencortex)' \
             --eval '(opencortex:initialize-all-skills)' \
             --eval '(opencortex:doctor-main)'
        ;;

    setup)
        setup_system "$@"
        ;;

    boot|--boot)
        exec sbcl --non-interactive \
             --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
             --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
             --eval "(ql:quickload '(:opencortex :croatoan))" \
             --eval '(opencortex:main)'
        ;;

    tui)
        exec sbcl \
             --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
             --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
             --eval '(ql:quickload :opencortex/tui)' \
             --eval '(opencortex.tui:main)'
        ;;

    *)
        echo "Available commands: setup, link, doctor, boot, tui"
        exit 1
        ;;
esac
