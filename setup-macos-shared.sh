#!/usr/bin/env bash

# macOS system preferences. Sourced by setup.sh, so it shares the
# info/ok/warn helpers, DOTFILES_DIR, brew env, etc.
# These are opinionated — trim to taste. Most take effect after a
# logout/restart; the killall at the end applies the rest immediately.

info "Applying macOS defaults..."

# ---------- keyboard ----------
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# ---------- finder ----------
defaults write com.apple.finder AppleShowAllFiles -bool true          # show hidden files
defaults write NSGlobalDomain AppleShowAllExtensions -bool true       # show file extensions
defaults write com.apple.finder ShowPathbar -bool true                # breadcrumb path bar at bottom of finder iwndows
defaults write com.apple.finder ShowStatusBar -bool true              # status bar showing item count and disk space
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"   # list view
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"   # search current folder

# ---------- dock ----------
defaults write com.apple.dock autohide -bool false
defaults write com.apple.dock tilesize -int 42
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mru-spaces -bool false   # don't reorder spaces by use

# ---------- screenshots ----------
mkdir -p "$HOME/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Screenshots"
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture disable-shadow -bool true

# ---------- global UI ----------
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true  # expand save dialog
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false  # save to disk, not iCloud

# ---------- apply ----------
for app in Finder Dock SystemUIServer; do killall "$app" >/dev/null 2>&1 || true; done
ok "macOS defaults applied (some need a logout/restart)"
