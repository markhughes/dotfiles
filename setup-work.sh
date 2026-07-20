#!/usr/bin/env bash

# Work machine setup. Sourced by install.sh, so it shares the
# info/ok/warn helpers, DOTFILES_DIR, brew env, etc.

info "Running work machine setup..."

# brew bundle --file="$DOTFILES_DIR/Brewfile.work"

# ---------- setup ini ----------
# Machine secrets/identity live in a gitignored ini (tmp/dotfiles-setup.ini):
#   GPG_KEY_ID=<short key id>
#   GPG_KEY_FPR=<full fingerprint>
#   GPG_PRIVATE_KEY=<base64 of the ASCII-armored private key export>
#   EMAIL=<git identity email>
#   SSH_KEY_NAME=<filename under ~/.ssh, e.g. id_ed25519_work>
#   SSH_PRIVATE_KEY=<base64 of the private key file>
#   SSH_PUBLIC_KEY=<contents of the .pub file (optional)>
# See additions.ini in the repo root for the SSH template.
INI_FILE="$DOTFILES_DIR/tmp/dotfiles-setup.ini"

while [ ! -f "$INI_FILE" ]; do
  info "Waiting for setup file: $INI_FILE"
  read -r -p "Create it, then press Enter to re-check (or 's' to skip): " answer
  case "$answer" in
    [sS]) break ;;
  esac
done

if [ -f "$INI_FILE" ]; then
  info "Reading $(basename "$INI_FILE")..."
  # shellcheck source=/dev/null
  source "$INI_FILE"

  if [ -z "${GPG_KEY_ID:-}" ] || [ -z "${GPG_KEY_FPR:-}" ] || [ -z "${EMAIL:-}" ]; then
    warn "Ini is missing GPG_KEY_ID, GPG_KEY_FPR or EMAIL — fix $INI_FILE and re-run"
  else
    # ---------- GPG signing key ----------
    info "GPG key..."

    # Import the secret key if it isn't already in the keyring.
    if gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
      ok "GPG signing key $GPG_KEY_ID already imported"
    elif [ -n "${GPG_PRIVATE_KEY:-}" ]; then
      if printf '%s' "$GPG_PRIVATE_KEY" | base64 -d | gpg --import; then
        ok "Imported GPG signing key $GPG_KEY_ID"
      else
        warn "GPG key import failed"
      fi
    else
      warn "GPG_PRIVATE_KEY not set in ini — skipping GPG key import"
    fi

    # Ensure the key is trusted ultimately (6). Idempotent; only runs if lower.
    if gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
      if gpg --export-ownertrust 2>/dev/null | grep -q "^${GPG_KEY_FPR}:6:"; then
        ok "GPG key trust already set to ultimate"
      else
        echo "${GPG_KEY_FPR}:6:" | gpg --import-ownertrust && ok "Set GPG key trust to ultimate"
      fi
    fi

    # ---------- git configuration ----------
    info "Basic git config..."
    git config --global user.name  "Mark Hughes"
    git config --global user.email "$EMAIL"
    git config --global user.signingkey "$GPG_KEY_ID" # public identifier for signing key

    # ---------- SSH key ----------
    if [ -n "${SSH_KEY_NAME:-}" ] && [ -n "${SSH_PRIVATE_KEY:-}" ]; then
      info "SSH key..."
      mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
      KEY_PATH="$HOME/.ssh/$SSH_KEY_NAME"

      # Import the private (and optional public) key if not already present.
      if [ -f "$KEY_PATH" ]; then
        ok "SSH key $SSH_KEY_NAME already present"
      else
        printf '%s' "$SSH_PRIVATE_KEY" | base64 -d > "$KEY_PATH"
        chmod 600 "$KEY_PATH"

        printf '%s\n' "$SSH_PUBLIC_KEY" > "$KEY_PATH.pub"
        chmod 644 "$KEY_PATH.pub"
        ok "Imported SSH key $SSH_KEY_NAME"
      fi

      # Managed ~/.ssh/config block (idempotent via markers).
      SSH_CONFIG="$HOME/.ssh/config"
      touch "$SSH_CONFIG" && chmod 600 "$SSH_CONFIG"
      if grep -q "# >>> dotfiles $SSH_KEY_NAME >>>" "$SSH_CONFIG" 2>/dev/null; then
        ok "SSH config block already present"
      else
        cat >> "$SSH_CONFIG" <<EOF

# >>> dotfiles $SSH_KEY_NAME >>>
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/$SSH_KEY_NAME
# <<< dotfiles $SSH_KEY_NAME <<<
EOF
        ok "Added SSH config block"
      fi

      # Load into the agent + Apple keychain (no-op if already loaded).
      ssh-add --apple-use-keychain "$KEY_PATH" >/dev/null 2>&1 || true
    else
      warn "SSH_KEY_NAME/SSH_PRIVATE_KEY not set in ini — skipping SSH setup"
    fi


    rm "$INI_FILE"
  fi
else
  warn "Setup ini skipped — some configuration skipped"
fi
