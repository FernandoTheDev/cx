#!/usr/bin/env bash
#
# build.sh — build/install script for the Cx compiler
#
# Usage:
#   ./build.sh                 # checks deps, builds, installs binary and updates std/
#   ./build.sh check           # only checks if ldc2 and dub are installed
#   ./build.sh install-deps    # shows how to install ldc2/dub on your distro
#   ./build.sh build           # only builds (dub build --compiler=ldc2 --build=release)
#   ./build.sh install-bin     # only copies the already-built `cx` binary to ~/.local/bin/
#   ./build.sh update-std      # only updates ~/.cx/std/ with the project's std/
#   ./build.sh path            # shows how to add ~/.local/bin to PATH (zsh/bash/fish)
#   ./build.sh help            # shows this help
#
set -euo pipefail

# ---------- colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[error]${NC} $1" >&2; }

# ---------- paths ----------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_NAME="cx"
INSTALL_DIR="$HOME/.local/bin"
CX_HOME="$HOME/.cx"
CX_STD_DEST="$CX_HOME/std"
CX_STD_SRC="$PROJECT_DIR/std"

# ---------- distro-specific install instructions ----------
show_install_instructions() {
    echo
    echo -e "${BOLD}Install ldc2 + dub:${NC}"
    echo
    echo -e "${YELLOW}Debian / Ubuntu${NC} (and derivatives):"
    echo "  sudo apt update && sudo apt install -y ldc dub"
    echo
    echo -e "${YELLOW}RedHat / Fedora / CentOS / RHEL${NC}:"
    echo "  sudo dnf install -y ldc dub"
    echo "  # older systems using yum:"
    echo "  sudo yum install -y ldc dub"
    echo
    echo -e "${YELLOW}Arch / Manjaro${NC}:"
    echo "  sudo pacman -S --needed ldc dub"
    echo
    echo "If a package isn't available in your distro's repos, install via the"
    echo "official D installer (works on any distro):"
    echo '  curl -fsS https://dlang.org/install.sh | bash -s ldc'
    echo "  see also: https://dlang.org/download.html"
    echo
}

# ---------- dependency check ----------
check_deps() {
    local missing=0

    if command -v ldc2 >/dev/null 2>&1; then
        ok "ldc2 found: $(ldc2 --version | head -n1)"
    else
        err "ldc2 not found in PATH"
        missing=1
    fi

    if command -v dub >/dev/null 2>&1; then
        ok "dub found: $(dub --version | head -n1)"
    else
        err "dub not found in PATH"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        echo
        warn "Install the missing dependencies before continuing."
        show_install_instructions
        return 1
    fi

    ok "All dependencies are installed."
    return 0
}

# ---------- build ----------
do_build() {
    cd "$PROJECT_DIR"
    info "Building with dub (ldc2, release)..."
    dub build --compiler=ldc2 --build=release
    if [[ -f "$PROJECT_DIR/$BIN_NAME" ]]; then
        ok "Build finished: $PROJECT_DIR/$BIN_NAME"
    else
        err "Build finished but binary '$BIN_NAME' was not found in $PROJECT_DIR"
        return 1
    fi
}

# ---------- install binary ----------
install_bin() {
    if [[ ! -f "$PROJECT_DIR/$BIN_NAME" ]]; then
        err "Binary '$BIN_NAME' not found in $PROJECT_DIR. Run './build.sh build' first."
        return 1
    fi

    mkdir -p "$INSTALL_DIR"
    cp "$PROJECT_DIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
    chmod +x "$INSTALL_DIR/$BIN_NAME"
    ok "Binary copied to $INSTALL_DIR/$BIN_NAME"
}

# ---------- update std ----------
update_std() {
    if [[ ! -d "$CX_STD_SRC" ]]; then
        err "std/ directory not found in $PROJECT_DIR"
        return 1
    fi

    mkdir -p "$CX_HOME"
    rm -rf "$CX_STD_DEST"
    cp -r "$CX_STD_SRC" "$CX_STD_DEST"
    ok "std/ updated at $CX_STD_DEST"
}

# ---------- PATH instructions ----------
show_path_instructions() {
    echo
    echo -e "${BOLD}Add ~/.local/bin to PATH:${NC}"
    echo
    echo -e "${YELLOW}zsh${NC} (~/.zshrc):"
    echo '  echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> ~/.zshrc && source ~/.zshrc'
    echo
    echo -e "${YELLOW}bash${NC} (~/.bashrc):"
    echo '  echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> ~/.bashrc && source ~/.bashrc'
    echo
    echo -e "${YELLOW}fish${NC}:"
    echo '  fish_add_path $HOME/.local/bin'
    echo
    echo "Then verify with: which cx"
    echo
}

show_help() {
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---------- main ----------
main() {
    local cmd="${1:-all}"

    case "$cmd" in
        check)
            check_deps
            ;;
        install-deps)
            show_install_instructions
            ;;
        build)
            check_deps
            do_build
            ;;
        install-bin)
            install_bin
            ;;
        update-std)
            update_std
            ;;
        path)
            show_path_instructions
            ;;
        help|-h|--help)
            show_help
            ;;
        all)
            check_deps
            do_build
            install_bin
            update_std
            echo
            ok "All done! '$BIN_NAME' installed at $INSTALL_DIR and std/ at $CX_STD_DEST"
            show_path_instructions
            ;;
        *)
            err "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
