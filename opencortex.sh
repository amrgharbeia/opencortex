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

# --- Dependency Checker ---
check_dependencies() {
    local missing=()
    for dep in sbcl emacs git curl socat nc; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}--- Missing dependencies: ${missing[*]} ---${NC}"
        if command_exists apt-get; then
            echo "Attempting to install missing dependencies..."
            if sudo apt-get update && sudo apt-get install -y sbcl emacs-nox rlwrap netcat-openbsd curl git socat libssl-dev libncurses-dev libffi-dev zlib1g-dev libsqlite3-dev 2>/dev/null; then
                echo -e "${GREEN}✓ Dependencies installed successfully${NC}"
            else
                echo -e "${RED}✗ Could not install dependencies. Please run with sudo or install manually:${NC}"
                echo "  sudo apt-get install sbcl emacs-nox rlwrap netcat-openbsd curl git socat"
            fi
        else
            echo -e "${RED}✗ Cannot auto-install: apt-get not available${NC}"
            echo "Please install manually: sbcl emacs git curl socat netcat-openbsd"
        fi
    fi
}

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

    # Tangle the literate source from OC_DATA_DIR to OC_DATA_DIR (The Engine)
    echo -e "${YELLOW}--- Deploying Engine to $OC_DATA_DIR ---${NC}"
    cp "$SCRIPT_DIR/opencortex.asd" "$OC_DATA_DIR/"
    cp "$SCRIPT_DIR/harness"/*.org "$OC_DATA_DIR/harness/"
    cp "$SCRIPT_DIR/skills"/*.org "$OC_DATA_DIR/skills/"
    
    # Create tests directory before tangling (some org files write to tests/)
    mkdir -p "$OC_DATA_DIR/tests"

    export INSTALL_DIR="$OC_DATA_DIR"

    # Critical: Tangle manifest first to establish system structure (into root)
    echo "Tangling harness/manifest.org..."
    (cd "$OC_DATA_DIR" && emacs -Q --batch --eval "(require 'org)" --eval "(setq org-confirm-babel-evaluate nil)" --eval "(org-babel-tangle-file \"harness/manifest.org\")") >/dev/null 2>&1 || true

    # Tangle harness files into harness/
    for f in "$SCRIPT_DIR/harness"/*.org; do
        fname=$(basename "$f" .org)
        if [ "$fname" != "manifest" ]; then
            echo "Tangling harness/$fname.org..."
            (cd "$OC_DATA_DIR/harness" && emacs -Q --batch --eval "(require 'org)" --eval "(setq org-confirm-babel-evaluate nil)" --eval "(org-babel-tangle-file \"${fname}.org\")") >/dev/null 2>&1 || true
        fi
    done

    # Tangle skill files into skills/
    for f in "$SCRIPT_DIR/skills"/*.org; do
        fname=$(basename "$f" .org)
        echo "Tangling skills/$fname.org..."
        # Copy org to XDG first (skills need to be loaded from XDG path)
        cp "$f" "$OC_DATA_DIR/skills/"
        (cd "$OC_DATA_DIR/skills" && emacs -Q --batch --eval "(require 'org)" --eval "(setq org-confirm-babel-evaluate nil)" --eval "(org-babel-tangle-file \"${fname}.org\")") >/dev/null 2>&1 || true
    done

    # Special handling for tests that need to go into tests/
    # We'll just move them after tangling since many .org files tangle to both code and tests
    mkdir -p "$OC_DATA_DIR/tests"
    find "$OC_DATA_DIR/harness" "$OC_DATA_DIR/skills" -name "*-tests.lisp" -exec mv {} "$OC_DATA_DIR/tests/" \; 2>/dev/null || true
    
    # Also move run-all-tests.lisp if it landed in the wrong place
    [ -f "$OC_DATA_DIR/run-all-tests.lisp" ] && mv "$OC_DATA_DIR/run-all-tests.lisp" "$OC_DATA_DIR/harness/"

    # Cleanup: Remove .org files from XDG harness only (skills need .org for loader)
    echo "Cleaning up .org files from XDG harness..."
    rm -f "$OC_DATA_DIR/harness"/*.org

    cd "$SCRIPT_DIR"    # Create the bin shim
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
         --eval '(opencortex:initialize-all-skills)' \
         --eval '(funcall (find-symbol "RUN-SETUP-WIZARD" :opencortex))'
}

# --- Doctor Repair (Lightweight Fix) ---
doctor_repair() {
    echo -e "${BLUE}=== OpenCortex: Repair Mode ===${NC}"
    
    # 1. Fix system dependencies
    echo -e "${YELLOW}--- Fixing System Dependencies ---${NC}"
    check_dependencies
    
    # 2. Ensure XDG directories exist
    echo -e "${YELLOW}--- Fixing XDG Directories ---${NC}"
    mkdir -p "$OC_CONFIG_DIR" "$OC_DATA_DIR" "$OC_STATE_DIR" "$OC_BIN_DIR"
    mkdir -p "$OC_DATA_DIR/harness" "$OC_DATA_DIR/tests" "$OC_DATA_DIR/skills" "$OC_DATA_DIR/library"
    
    # 3. Re-tangle harness files that may be broken
    echo -e "${YELLOW}--- Re-tangling Harness Files ---${NC}"
    for f in "$SCRIPT_DIR/harness"/*.org; do
        if [ -f "$f" ]; then
            fname=$(basename "$f" .org)
            echo "  Checking harness/$fname..."
            # Try to load each harness file - if it fails, re-tangle
            if ! sbcl --non-interactive \
                 --eval "(load \"$OC_DATA_DIR/harness/${fname}.lisp\")" \
                 --eval "(format t \"OK~%\")" 2>/dev/null | grep -q "OK"; then
                echo "    Re-tangling $fname.org..."
                (cd "$OC_DATA_DIR/harness" && emacs -Q --batch \
                    --eval "(require 'org)" \
                    --eval "(setq org-confirm-babel-evaluate nil)" \
                    --eval "(org-babel-tangle-file \"$f\")" >/dev/null 2>&1) || true
            fi
        fi
    done
    
    # 4. Re-tangle skill files that may be broken
    echo -e "${YELLOW}--- Re-tangling Skill Files ---${NC}"
    for f in "$SCRIPT_DIR/skills"/*.org; do
        if [ -f "$f" ]; then
            fname=$(basename "$f" .org)
            echo "  Checking skill/$fname..."
            # Copy .org to XDG temporarily for tangle, then remove
            cp "$f" "$OC_DATA_DIR/skills/"
            if ! sbcl --non-interactive \
                 --eval "(load \"$OC_DATA_DIR/skills/${fname}.lisp\")" \
                 --eval "(format t \"OK~%\")" 2>/dev/null | grep -q "OK"; then
                echo "    Re-tangling $fname.org..."
                (cd "$OC_DATA_DIR/skills" && emacs -Q --batch \
                    --eval "(require 'org)" \
                    --eval "(setq org-confirm-babel-evaluate nil)" \
                    --eval "(org-babel-tangle-file \"$OC_DATA_DIR/skills/${fname}.org\")" >/dev/null 2>&1) || true
            fi
            rm -f "$OC_DATA_DIR/skills/${fname}.org"
        fi
    done
    
    # 5. Cleanup .org files
    rm -f "$OC_DATA_DIR/harness"/*.org "$OC_DATA_DIR/skills"/*.org 2>/dev/null || true
    
    echo -e "${GREEN}--- Repair Complete ---${NC}"
    echo "Run 'opencortex doctor' to verify the system."
}

# --- 3. COMMAND ROUTER ---
COMMAND=$1
[ -z "$COMMAND" ] && COMMAND="cli"
shift || true

case "$COMMAND" in
    link)
        PLATFORM=$1
        TOKEN=$2
        check_dependencies
        exec sbcl --non-interactive              --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))'              --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)"              --eval '(ql:quickload :opencortex)'              --eval '(opencortex:initialize-all-skills)'              --eval "(funcall (find-symbol \"GATEWAY-MANAGER-MAIN\" :opencortex) \"$PLATFORM\" \"$TOKEN\")"
        ;;

    doctor)
        check_dependencies
        if [ "$1" = "--watch" ]; then
            echo "Starting background health monitor (60s interval)..."
            echo "Press Ctrl+C to stop."
            echo ""
            while true; do
                echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
                sbcl --non-interactive \
                     --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                     --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                     --eval '(ql:quickload :opencortex)' \
                     --eval '(opencortex:initialize-all-skills)' \
                     --eval '(funcall (find-symbol "DOCTOR-RUN-ALL" :opencortex))' \
                     --eval '(uiop:quit 0)' 2>&1 | grep -E "(HEALTH|OK|FAIL|WARN|SYSTEM|===)" || true
                sleep 60
            done
        elif [ "$1" = "--fix" ]; then
            # Check if major harness files exist - if not, run full setup
            if [ ! -f "$OC_DATA_DIR/harness/package.lisp" ] || [ ! -f "$OC_DATA_DIR/harness/skills.lisp" ]; then
                echo "Core files missing. Running full setup..."
                setup_system "$@"
            else
                echo "Repairing system..."
                doctor_repair
            fi
        else
            exec sbcl --non-interactive \
                 --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                 --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                 --eval '(ql:quickload :opencortex)' \
                 --eval '(opencortex:initialize-all-skills)' \
                 --eval '(funcall (find-symbol "DOCTOR-MAIN" :opencortex))'
        fi
        ;;

    setup)
        check_dependencies
        if [ "$1" = "--add-provider" ]; then
            echo "Adding LLM provider..."
            sbcl --non-interactive \
                 --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                 --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                 --eval '(ql:quickload :opencortex)' \
                 --eval '(opencortex:initialize-all-skills)' \
                 --eval '(funcall (find-symbol "SETUP-ADD-PROVIDER" :opencortex))'
        elif [ "$1" = "--link" ]; then
            PLATFORM=$2
            TOKEN=$3
            if [ -z "$PLATFORM" ] || [ -z "$TOKEN" ]; then
                echo "Usage: opencortex setup --link <platform> <token>"
                echo "  platforms: slack, discord"
                exit 1
            fi
            echo "Linking $PLATFORM gateway..."
            $0 link "$PLATFORM" "$TOKEN"
        elif [ "$1" = "--non-interactive" ]; then
            setup_system "$@"
        else
            # Run interactive setup wizard
            echo "Starting interactive setup wizard..."
            sbcl --non-interactive \
                 --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                 --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                 --eval '(ql:quickload :opencortex)' \
                 --eval '(opencortex:initialize-all-skills)' \
                 --eval '(funcall (find-symbol "RUN-SETUP-WIZARD" :opencortex))'
        fi
        ;;

    boot|--boot)
        check_dependencies
        exec sbcl --non-interactive \
             --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
             --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
             --eval "(ql:quickload '(:opencortex :croatoan))" \
             --eval '(opencortex:main)'
        ;;

    daemon)
        check_dependencies
        echo "Starting OpenCortex daemon in background..."
        nohup sbcl --non-interactive \
             --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
             --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
             --eval "(ql:quickload '(:opencortex :croatoan))" \
             --eval '(opencortex:main)' \
             > "$OC_STATE_DIR/daemon.log" 2>&1 &
        echo "Daemon started. Waiting for port 9105..."
        for i in {1..20}; do
            if ss -tln | grep -q 9105; then
                echo "✓ Daemon ready on port 9105"
                exit 0
            fi
            sleep 1
        done
        echo "✗ Daemon failed to start. Check $OC_STATE_DIR/daemon.log"
        exit 1
        ;;

    tui)
        check_dependencies
        if ! ss -tln | grep -q 9105; then
            echo "Daemon not running. Starting daemon first..."
            $0 daemon
        fi
        if sbcl --non-interactive \
             --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
             --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
             --eval '(ql:quickload :opencortex/tui)' \
             --eval '(opencortex.tui:main)'; then
            true
        else
            EXIT_CODE=$?
            echo ""
            echo "TUI exited with error. Running diagnostics..."
            $0 doctor
            echo ""
            echo "Run 'opencortex doctor --fix' to repair, or 'opencortex setup' to reconfigure."
            exit $EXIT_CODE
        fi
        ;;

    cli|boot)
        check_dependencies
        if sbcl --non-interactive \
             --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
             --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
             --eval "(ql:quickload '(:opencortex :croatoan))" \
             --eval '(opencortex:main)'; then
            true
        else
            EXIT_CODE=$?
            echo ""
            echo "CLI exited with error. Running diagnostics..."
            $0 doctor
            echo ""
            echo "Run 'opencortex doctor --fix' to repair, or 'opencortex setup' to reconfigure."
            exit $EXIT_CODE
        fi
        ;;

    *)
        echo "Available commands: setup, link, doctor, boot, tui, cli, daemon"
        exit 1
        ;;
esac
