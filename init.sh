#!/bin/sh

set -eu

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/markhughes/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

info() { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ ok ]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }

# ---------- OS check ----------
if [ "$(uname -s)" != "Darwin" ]; then
  warn "init.sh currently only supports macOS"
  exit 1
fi

# ---------- Xcode Command Line Tools ----------
# Needed for git (to clone the repo) and everything install.sh does after.
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools present"
else
  info "Installing Xcode Command Line Tools (a dialog will pop up — click Install)..."
  xcode-select --install 2>/dev/null || true
  # Poll until the install completes; the GUI installer runs out-of-process.
  until xcode-select -p >/dev/null 2>&1; do
    printf "."
    sleep 10
  done
  printf "\n"
  ok "Xcode Command Line Tools installed"
fi

# ---------- clone dotfiles ----------
if [ -d "$DOTFILES_DIR/.git" ]; then
  info "Dotfiles already cloned, pulling latest..."
  git -C "$DOTFILES_DIR" pull --ff-only
else
  info "Cloning $DOTFILES_REPO to $DOTFILES_DIR..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi
ok "Dotfiles ready at $DOTFILES_DIR"

# ---------- hand off to setup.sh ----------
# When this script is piped from curl, stdin is the pipe — reattach the
# terminal so setup.sh's interactive prompts (work/personal) still work.
info "Running setup.sh..."
if [ -t 0 ]; then
  bash "$DOTFILES_DIR/setup.sh"
else
  bash "$DOTFILES_DIR/setup.sh" </dev/tty
fi
