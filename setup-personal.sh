#!/usr/bin/env bash

info "Running personal machine setup..."

brew bundle --file="$DOTFILES_DIR/Brewfile.personal"

info "Basic git config..."
git config --global user.name  "Mark Hughes"
git config --global user.email "m@rkhugh.es"
