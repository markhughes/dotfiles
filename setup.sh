#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DOTFILES_DIR"

mkdir -p "$DOTFILES_DIR/tmp"

# ---------- helpers ----------
info()  { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[ ok ]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }

# ---------- OS detection ----------
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *)      warn "Unsupported OS: $OS"; exit 1 ;;
esac
info "Detected platform: $PLATFORM"

# ---------- macOS setup ----------
if [ "$PLATFORM" = "macos" ]; then
 
  # Xcode Command Line Tools (needed for git, compilers, Homebrew)
  if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools..."
    xcode-select --install
    warn "Complete the CLT installer dialog, then re-run this script."
    exit 0
  fi
  ok "Xcode Command Line Tools present"
 
  # Homebrew
  if ! command -v brew >/dev/null 2>&1; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # Ensure brew is on PATH for this session (Apple Silicon vs Intel)
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "Homebrew ready"
 
  # Install everything declared in the Brewfile (CLI tools + apps like VS Code)
  if [ -f "$DOTFILES_DIR/Brewfile" ]; then
    info "Installing packages from Brewfile..."
    brew bundle --file="$DOTFILES_DIR/Brewfile"
    ok "Brewfile packages installed"
  else
    warn "No Brewfile found, skipping package installs"
  fi

  # shellcheck source=/dev/null
  source "$DOTFILES_DIR/setup-macos-shared.sh"
fi

# ---------- linux setup ----------
if [ "$PLATFORM" = "linux" ]; then
  warn "Not ready for linux yet"
  exit 1
fi


# ---------- oh-my-zsh ----------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  info "Installing oh-my-zsh..."
  # RUNZSH=no  -> don't drop into a new shell mid-script
  # KEEP_ZSHRC=yes -> don't clobber the .zshrc we're about to stow
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
ok "oh-my-zsh present"

# plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_plugin() {
  local repo="$1" dest
  dest="$ZSH_CUSTOM/plugins/$(basename "$1")"
  [ -d "$dest" ] || git clone --depth=1 "https://github.com/$repo" "$dest"
}
clone_plugin zsh-users/zsh-autosuggestions
clone_plugin zsh-users/zsh-syntax-highlighting
clone_plugin MichaelAquilina/zsh-you-should-use
ok "zsh plugins present"


# ---------- symlink dotfiles ----------
info "Stowing dotfile packages..."
# --restow makes re-runs clean; add/remove package names to taste
stow --restow zsh ghostty starship vscode nvim git claude 2>/dev/null || {
  warn "Stow reported conflicts. Back up the existing files it names, then re-run."
  stow --restow --verbose zsh ghostty starship vscode nvim git claude || true
}
ok "Dotfiles linked"

# Seed a local-only zsh config (sourced at the end of .zshrc, not tracked here)
if [ ! -f "$HOME/.zshrc.local" ]; then
  printf '# Local machine-only zsh config. Not tracked in dotfiles.\n' > "$HOME/.zshrc.local"
  ok "Created ~/.zshrc.local"
fi

# ---------- rust ----------
if ! command -v rustup >/dev/null 2>&1; then
  info "Installing Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
# Load cargo into this session so anything below can use it
# shellcheck source=/dev/null
[ -s "$HOME/.cargo/env" ] && \. "$HOME/.cargo/env"
ok "Rust ready"


# ---------- nvm ----------
info "Setting up nvm"
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
# shellcheck source=/dev/null
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm

nvm install --lts


# ---------- pyenv ----------
if command -v pyenv >/dev/null 2>&1; then
  info "Setting up pyenv Python..."
  pyenv install -s 3   # -s skips if that version is already installed
  pyenv global 3
  ok "pyenv ready"
else
  warn "pyenv not installed, skipping Python setup"
fi

# ---------- vscode ----------
EXT_FILE="$DOTFILES_DIR/vscode-extensions.txt"
if [ -f "$EXT_FILE" ]; then
  info "Installing VS Code extensions..."
  installed="$(code --list-extensions)"
  # Strip comments/blank lines, then install any that aren't already present
  grep -vE '^\s*(#|$)' "$EXT_FILE" | while read -r ext; do
    echo "$installed" | grep -qi "^$ext$" || code --install-extension "$ext"
  done
  ok "VS Code extensions installed"
else
  warn "No $EXT_FILE found, skipping VS Code extensions"
fi


# ---------- shared git options ----------
# Do not stow, as our personal/work is different, didn't want to maintain
# two configs with shared options

# useful initials
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global diff.colorMoved zebra
git config --global merge.conflictStyle zdiff3
git config --global rerere.enabled true
git config --global fetch.prune false

# delta (git-delta) as the diff pager
git config --global core.pager "delta"
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.line-numbers true
git config --global delta.side-by-side false

git config --global commit.gpgsign true
git config --global tag.gpgsign true

# ---------- work vs personal ----------
read -r -p "Is this a work computer? [y/N] " is_work
case "$is_work" in
  [yY]|[yY][eE][sS]) MACHINE_SCRIPT="setup-work.sh" ;;
  *)                 MACHINE_SCRIPT="setup-personal.sh" ;;
esac

if [ -f "$DOTFILES_DIR/$MACHINE_SCRIPT" ]; then
  info "Running $MACHINE_SCRIPT..."
  # shellcheck source=/dev/null
  source "$DOTFILES_DIR/$MACHINE_SCRIPT"
  ok "$MACHINE_SCRIPT complete"
else
  warn "No $MACHINE_SCRIPT found, skipping"
fi

# ---------- claude ----------
if ! command -v claude >/dev/null 2>&1; then
  info "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
else
  ok "Claude Code already installed"
fi

# Add default MCP servers, skipping any already in the user config
add_mcp() {
  local name="$1"; shift
  if claude mcp list 2>/dev/null | grep -q "^${name}:"; then
    ok "MCP $name already configured"
  else
    info "Adding MCP $name..."
    claude mcp add "$@"
  fi
}
add_mcp notion --transport http notion https://mcp.notion.com/mcp --scope user
add_mcp figma  --transport http figma  https://mcp.figma.com/mcp  --scope user

ok "Claude setup and default MCPs!"

# ---------- Switch to Ghostty ----------
if [ "$TERM_PROGRAM" = "Apple_Terminal" ]; then
  echo "Install complete, launching Ghostty..."
  open -a Ghostty
else 
  exec zsh
fi
