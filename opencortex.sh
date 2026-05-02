#!/bin/bash
set -e

PORT=9105
HOST="localhost"
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- XDG PATH RESOLUTION ---
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
export SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

export OC_CONFIG_DIR="$(realpath -m "${XDG_CONFIG_HOME:-$HOME/.config}/opencortex")"
export OC_DATA_DIR="$(realpath -m "${XDG_DATA_HOME:-$HOME/.local/share}/opencortex")"
export OC_STATE_DIR="$(realpath -m "${XDG_STATE_HOME:-$HOME/.local/state}/opencortex")"
export OC_BIN_DIR="$(realpath -m "${XDG_BIN_HOME:-$HOME/.local/bin}")"
export MEMEX_DIR="${MEMEX_DIR:-$HOME/memex}"

if [ -f "$OC_CONFIG_DIR/.env" ]; then
    set -a; source "$OC_CONFIG_DIR/.env"; set +a
fi

# --- DISTRO DETECTION ---
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint|pop|elementary|zorin) echo "debian" ;;
            fedora|rhel|centos|rocky|almalinux) echo "fedora" ;;
            *) echo "unknown" ;;
        esac
    elif command_exists apt-get; then echo "debian"
    elif command_exists dnf; then echo "fedora"
    else echo "unknown"; fi
}

distro_install() {
    local distro=$(detect_distro); shift
    case "$distro" in
        debian) sudo apt-get update && sudo apt-get install -y "$@" ;;
        fedora) sudo dnf install -y "$@" ;;
        *) echo "Unsupported distro. Install manually: sbcl emacs git curl socat"; return 1 ;;
    esac
}

# --- DEPENDENCY CHECK ---
check_dependencies() {
    local missing=()
    for dep in sbcl git curl socat nc; do
        if ! command_exists "$dep"; then missing+=("$dep"); fi
    done
    if ! command_exists emacs; then missing+=("emacs-nox"); fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}--- Installing missing dependencies: ${missing[*]} ---${NC}"
        local distro=$(detect_distro)
        case "$distro" in
            debian)
                distro_install "${missing[@]}" libssl-dev libncurses-dev libffi-dev zlib1g-dev libsqlite3-dev 2>/dev/null || true
                if ! command_exists rlwrap; then distro_install rlwrap 2>/dev/null || true; fi
                if ! command_exists nc; then distro_install netcat-openbsd 2>/dev/null || true; fi
                ;;
            fedora)
                distro_install "${missing[@]}" openssl-devel ncurses-devel libffi-devel zlib-devel sqlite-devel 2>/dev/null || true
                if ! command_exists rlwrap; then distro_install rlwrap 2>/dev/null || true; fi
                if ! command_exists nc; then distro_install nmap-ncat 2>/dev/null || true; fi
                ;;
        esac
    fi
}

# --- SETUP ---
setup_system() {
    NON_INTERACTIVE=false; WITH_FIREWALL=false
    for arg in "$@"; do
        case "$arg" in
            --non-interactive) NON_INTERACTIVE=true ;;
            --with-firewall) WITH_FIREWALL=true ;;
        esac
    done

    echo -e "${BLUE}=== OpenCortex: Configure ===${NC}"
    mkdir -p "$OC_CONFIG_DIR" "$OC_DATA_DIR" "$OC_STATE_DIR" "$OC_BIN_DIR"
    mkdir -p "$OC_DATA_DIR/harness" "$OC_DATA_DIR/tests" "$OC_DATA_DIR/skills"

    check_dependencies

    if [ ! -d "$HOME/quicklisp" ]; then
        echo -e "${YELLOW}--- Installing Quicklisp ---${NC}"
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive --load quicklisp.lisp \
             --eval "(quicklisp-quickstart:install)" \
             --eval "(ql-util:without-prompting (ql:add-to-init-file))"
        rm quicklisp.lisp
    fi

    echo -e "${YELLOW}--- Deploying Engine to $OC_DATA_DIR ---${NC}"
    cp "$SCRIPT_DIR/opencortex.asd" "$OC_DATA_DIR/"
    mkdir -p "$OC_DATA_DIR/harness" "$OC_DATA_DIR/tests" "$OC_DATA_DIR/skills"
    export INSTALL_DIR="$OC_DATA_DIR"

    cp "$SCRIPT_DIR/harness"/*.org "$OC_DATA_DIR/harness/"
    (cd "$OC_DATA_DIR/harness" && emacs -Q --batch \
        --eval "(require 'org)" \
        --eval "(setq org-confirm-babel-evaluate nil)" \
        --eval "(org-babel-tangle-file \"manifest.org\")") >/dev/null 2>&1 || true
    for f in "$OC_DATA_DIR/harness"/*.org; do
        fname=$(basename "$f" .org)
        [ "$fname" = "manifest" ] && continue
        echo "Tangling harness/$fname.org..."
        (cd "$OC_DATA_DIR/harness" && emacs -Q --batch \
            --eval "(require 'org)" \
            --eval "(setq org-confirm-babel-evaluate nil)" \
            --eval "(org-babel-tangle-file \"${fname}.org\")") >/dev/null 2>&1 || true
    done
    find "$OC_DATA_DIR/harness" -name "*-tests.lisp" -exec mv {} "$OC_DATA_DIR/tests/" \; 2>/dev/null || true
    rm -f "$OC_DATA_DIR/harness"/*.org

    for f in "$SCRIPT_DIR/skills"/*.org; do
        fname=$(basename "$f" .org)
        echo "Tangling skills/$fname.org..."
        cp "$f" "$OC_DATA_DIR/skills/"
        (cd "$OC_DATA_DIR/skills" && emacs -Q --batch \
            --eval "(require 'org)" \
            --eval "(setq org-confirm-babel-evaluate nil)" \
            --eval "(org-babel-tangle-file \"${fname}.org\")") >/dev/null 2>&1 || true
        rm -f "$OC_DATA_DIR/skills/$fname.org"
    done
    find "$OC_DATA_DIR/skills" -name "*-tests.lisp" -exec mv {} "$OC_DATA_DIR/tests/" \; 2>/dev/null || true
    [ -f "$OC_DATA_DIR/run-all-tests.lisp" ] && mv "$OC_DATA_DIR/run-all-tests.lisp" "$OC_DATA_DIR/harness/"
    rm -f "$OC_DATA_DIR/harness"/*.org "$OC_DATA_DIR/skills"/*.org

    ln -sf "$SCRIPT_DIR/opencortex.sh" "$OC_BIN_DIR/opencortex"

    if [ "$WITH_FIREWALL" = true ]; then
        case $(detect_distro) in
            debian) sudo ufw allow 9105/tcp 2>/dev/null && echo "✓ UFW: port 9105 opened" || true ;;
            fedora) sudo firewall-cmd --add-port=9105/tcp --permanent 2>/dev/null && sudo firewall-cmd --reload 2>/dev/null && echo "✓ firewalld: port 9105 opened" || true ;;
        esac
    fi

    if [ "$NON_INTERACTIVE" = true ]; then
        echo "Configure complete."
        exit 0
    fi

    echo -e "${YELLOW}--- Launching Setup Wizard ---${NC}"
    exec sbcl --non-interactive \
        --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
        --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
        --eval '(ql:quickload :opencortex)' \
        --eval '(opencortex:initialize-all-skills)' \
        --eval '(funcall (find-symbol "RUN-SETUP-WIZARD" :opencortex))'
}

# --- DOCTOR REPAIR ---
doctor_repair() {
    echo -e "${BLUE}=== OpenCortex: Repair Mode ===${NC}"
    check_dependencies
    mkdir -p "$OC_CONFIG_DIR" "$OC_DATA_DIR" "$OC_STATE_DIR" "$OC_BIN_DIR"
    mkdir -p "$OC_DATA_DIR/harness" "$OC_DATA_DIR/tests" "$OC_DATA_DIR/skills"
    for f in "$SCRIPT_DIR/harness"/*.org; do
        [ -f "$f" ] || continue
        fname=$(basename "$f" .org)
        echo "  Checking harness/$fname..."
        if ! sbcl --non-interactive \
            --eval "(load \"$OC_DATA_DIR/harness/${fname}.lisp\")" \
            --eval "(format t \"OK~%\")" 2>/dev/null | grep -q "OK"; then
            echo "    Re-tangling $fname.org..."
            (cd "$OC_DATA_DIR/harness" && emacs -Q --batch \
                --eval "(require 'org)" \
                --eval "(setq org-confirm-babel-evaluate nil)" \
                --eval "(org-babel-tangle-file \"$f\")") >/dev/null 2>&1 || true
        fi
    done
    for f in "$SCRIPT_DIR/skills"/*.org; do
        [ -f "$f" ] || continue
        fname=$(basename "$f" .org)
        echo "  Checking skill/$fname..."
        if ! sbcl --non-interactive \
            --eval "(load \"$OC_DATA_DIR/skills/${fname}.lisp\")" \
            --eval "(format t \"OK~%\")" 2>/dev/null | grep -q "OK"; then
            echo "    Re-tangling $fname.org..."
            cp "$f" "$OC_DATA_DIR/skills/"
            (cd "$OC_DATA_DIR/skills" && emacs -Q --batch \
                --eval "(require 'org)" \
                --eval "(setq org-confirm-babel-evaluate nil)" \
                --eval "(org-babel-tangle-file \"${fname}.org\")") >/dev/null 2>&1 || true
            rm -f "$OC_DATA_DIR/skills/$fname.org"
        fi
    done
    rm -f "$OC_DATA_DIR/harness"/*.org "$OC_DATA_DIR/skills"/*.org 2>/dev/null || true
    echo -e "${GREEN}--- Repair Complete ---${NC}"
}

# --- INSTALL SKILL ---
install_skill() {
    local SKILL_NAME=$1
    if [ -z "$SKILL_NAME" ]; then
        echo "Usage: opencortex install skill <skill-name>"
        echo "  Installs a skill from opencortex-contrib"
        echo ""
        echo "Available skills:"
        if [ -d "$MEMEX_DIR/projects/opencortex-contrib/skills" ]; then
            ls "$MEMEX_DIR/projects/opencortex-contrib/skills"/*.org 2>/dev/null | xargs -I{} basename {} .org | sed 's/org-skill-//' | sort | uniq
        else
            echo "  (clone opencortex-contrib to ~/memex/projects/ first)"
        fi
        exit 1
    fi
    local SKILL_FILE="org-skill-${SKILL_NAME}.org"
    local SOURCE_DIR="$MEMEX_DIR/projects/opencortex-contrib/skills"
    local TARGET_DIR="$OC_DATA_DIR/skills"
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Error: Contrib skills not found at $SOURCE_DIR"
        echo "Run: git clone https://github.com/amrgharbeia/opencortex-contrib.git \$MEMEX_DIR/projects/opencortex-contrib"
        exit 1
    fi
    if [ ! -f "$SOURCE_DIR/$SKILL_FILE" ]; then
        echo "Error: Skill '$SKILL_NAME' not found"
        exit 1
    fi
    mkdir -p "$TARGET_DIR"
    cp "$SOURCE_DIR/$SKILL_FILE" "$TARGET_DIR/"
    (cd "$TARGET_DIR" && emacs -Q --batch \
        --eval "(require 'org)" \
        --eval "(setq org-confirm-babel-evaluate nil)" \
        --eval "(org-babel-tangle-file \"$SKILL_FILE\")") >/dev/null 2>&1 || true
    rm -f "$TARGET_DIR/$SKILL_FILE"
    if [ -f "$TARGET_DIR/${SKILL_NAME}-tests.lisp" ]; then
        mv "$TARGET_DIR/${SKILL_NAME}-tests.lisp" "$OC_DATA_DIR/tests/" 2>/dev/null || true
    fi
    echo "Skill '$SKILL_NAME' installed. Restart to activate."
}

# --- INSTALL SERVICE ---
install_service() {
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/opencortex.service" << 'SERVICEEOF'
[Unit]
Description=OpenCortex Daemon
After=network.target

[Service]
Type=simple
ExecStart=%h/projects/opencortex/opencortex.sh daemon
Restart=on-failure
RestartSec=10
WorkingDirectory=%h/projects/opencortex

[Install]
WantedBy=default.target
SERVICEEOF
    systemctl --user daemon-reload
    systemctl --user enable opencortex.service
    systemctl --user start opencortex.service
    echo -e "${GREEN}✓ opencortex.service installed and started${NC}"
    echo "  Status: systemctl --user status opencortex.service"
    echo "  Logs:   journalctl --user -u opencortex.service -f"
}

uninstall_service() {
    systemctl --user stop opencortex.service 2>/dev/null || true
    systemctl --user disable opencortex.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/opencortex.service"
    systemctl --user daemon-reload
    echo -e "${GREEN}✓ opencortex.service removed${NC}"
}

# --- BACKUP ---
backup() {
    local dest="${1:-$HOME/opencortex-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
    if [ -f "$dest" ]; then echo "Error: $dest exists"; exit 1; fi
    echo "Backing up to $dest..."
    tar -czf "$dest" \
        "$OC_CONFIG_DIR" "$OC_DATA_DIR" \
        "$MEMEX_DIR/gtd.org" "$MEMEX_DIR/projects/opencortex" \
        2>/dev/null || true
    echo -e "${GREEN}✓ Backed up to $dest${NC}"
}

restore() {
    local src="$1"
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        echo "Usage: opencortex restore <backup-file>"
        exit 1
    fi
    echo "Restoring from $src..."
    tar -xzf "$src" -C /
    echo -e "${GREEN}✓ Restored. Run 'opencortex doctor' to verify.${NC}"
}

# --- HELP ---
help() {
    echo ""
    echo "OpenCortex — Your Autonomous, Plain-Text Life Assistant"
    echo ""
    echo "Usage: opencortex.sh <command> [options]"
    echo ""
    echo "System:"
    echo "  configure [--non-interactive] [--with-firewall]    Install or reconfigure the system"
    echo "  setup                                               Alias for configure"
    echo "  doctor [--fix] [--watch]                            System health check"
    echo ""
    echo "Running:"
    echo "  daemon                                              Start background daemon"
    echo "  tui                                                 Launch terminal UI"
    echo "  gateway {link|unlink|list} <platform> <token>       Manage chat gateways"
    echo ""
    echo "Skills:"
    echo "  install skill <name>                                Install a skill from contrib"
    echo "  install service                                     Install systemd service (auto-start)"
    echo "  uninstall service                                   Remove systemd service"
    echo ""
    echo "Data:"
    echo "  backup [path]                                       Backup config, data, memex"
    echo "  restore <path>                                      Restore from a backup"
    echo ""
    echo "Quick start:"
    echo "  curl -fsSL https://raw.githubusercontent.com/amrgharbeia/opencortex/main/opencortex.sh | bash -s configure"
    echo ""
}

# --- COMMAND ROUTER ---
COMMAND=$1; [ -z "$COMMAND" ] && COMMAND="help"
shift || true

case "$COMMAND" in
    configure|setup)
        check_dependencies
        if [ "$1" = "--add-provider" ]; then
            sbcl --non-interactive \
                --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                --eval '(ql:quickload :opencortex)' \
                --eval '(opencortex:initialize-all-skills)' \
                --eval '(funcall (find-symbol "SETUP-ADD-PROVIDER" :opencortex))'
        elif [ "$1" = "--link" ]; then
            exec "$0" gateway link "$2" "$3"
        else
            setup_system "$@"
        fi
        ;;
    doctor)
        check_dependencies
        if [ "$1" = "--watch" ]; then
            while true; do
                echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
                sbcl --non-interactive \
                    --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                    --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                    --eval '(ql:quickload :opencortex)' \
                    --eval '(opencortex:initialize-all-skills)' \
                    --eval '(funcall (find-symbol "DOCTOR-RUN-ALL" :opencortex))' 2>&1 | grep -E "(HEALTH|OK|FAIL|WARN|SYSTEM|===)" || true
                sleep 60
            done
        elif [ "$1" = "--fix" ]; then
            if [ ! -f "$OC_DATA_DIR/harness/package.lisp" ] || [ ! -f "$OC_DATA_DIR/harness/skills.lisp" ]; then
                setup_system "$@"
            else
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
    daemon)
        check_dependencies
        echo "Starting daemon in background..."
        nohup sbcl --non-interactive \
            --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
            --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
            --eval "(ql:quickload '(:opencortex :croatoan))" \
            --eval '(opencortex:main)' \
            > "$OC_STATE_DIR/daemon.log" 2>&1 &
        echo "Waiting for port 9105..."
        for i in $(seq 1 20); do
            if ss -tln 2>/dev/null | grep -q 9105 || netstat -tln 2>/dev/null | grep -q 9105; then
                echo "✓ Daemon ready on port 9105"; exit 0
            fi
            sleep 1
        done
        echo "✗ Daemon failed to start. Check $OC_STATE_DIR/daemon.log"; exit 1
        ;;
    tui)
        check_dependencies
        if ! ss -tln 2>/dev/null | grep -q 9105 && ! netstat -tln 2>/dev/null | grep -q 9105; then
            echo "Starting daemon first..."
            $0 daemon
        fi
        sbcl \
            --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
            --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
            --eval '(ql:quickload :opencortex/tui)' \
            --eval '(opencortex.tui:main)' || {
            echo "TUI error. Run 'opencortex doctor --fix'"; exit 1
        }
        ;;
    gateway)
        SUBCMD=$1; PLATFORM=$2; TOKEN=$3
        check_dependencies
        case "$SUBCMD" in
            list)
                exec sbcl --non-interactive \
                    --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                    --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                    --eval '(ql:quickload :opencortex)' \
                    --eval '(opencortex:initialize-all-skills)' \
                    --eval '(funcall (find-symbol "GATEWAY-LIST-PRINT" (find-package "OPENCORTEX.SKILLS.ORG-SKILL-GATEWAY-MANAGER")))'
                ;;
            link)
                [ -z "$PLATFORM" ] || [ -z "$TOKEN" ] && echo "Usage: opencortex gateway link <platform> <token>" && exit 1
                exec sbcl --non-interactive \
                    --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                    --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                    --eval '(ql:quickload :opencortex)' \
                    --eval '(opencortex:initialize-all-skills)' \
                    --eval "(funcall (find-symbol \"GATEWAY-LINK\" (find-package \"OPENCORTEX.SKILLS.ORG-SKILL-GATEWAY-MANAGER\")) \"$PLATFORM\" \"$TOKEN\")"
                ;;
            unlink)
                [ -z "$PLATFORM" ] && echo "Usage: opencortex gateway unlink <platform>" && exit 1
                exec sbcl --non-interactive \
                    --eval '(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))' \
                    --eval "(push (truename \"$OC_DATA_DIR/\") asdf:*central-registry*)" \
                    --eval '(ql:quickload :opencortex)' \
                    --eval '(opencortex:initialize-all-skills)' \
                    --eval "(funcall (find-symbol \"GATEWAY-UNLINK\" (find-package \"OPENCORTEX.SKILLS.ORG-SKILL-GATEWAY-MANAGER\")) \"$PLATFORM\")"
                ;;
            *) echo "Usage: opencortex gateway {list|link|unlink}"; exit 1 ;;
        esac
        ;;
    install)
        case "$1" in
            skill) shift; install_skill "$@" ;;
            service) install_service ;;
            *) echo "Usage: opencortex install {skill|service}" >&2; exit 1 ;;
        esac
        ;;
    uninstall)
        case "$1" in
            service) uninstall_service ;;
            *) echo "Usage: opencortex uninstall {service}" >&2; exit 1 ;;
        esac
        ;;
    backup)
        backup "$1"
        ;;
    restore)
        restore "$1"
        ;;
    help|--help|-h)
        help
        ;;
    *)
        echo "Unknown command: $COMMAND"
        help
        exit 1
        ;;
esac
