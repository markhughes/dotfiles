# Auto-switch node version on cd when an .nvmrc is present (installs if missing),
# and back to the default version when leaving. Runs once at shell start too.
load-nvmrc() {
  emulate -L zsh
  local nvmrc_path=$(nvm_find_nvmrc)

  if [[ -n $nvmrc_path ]]; then
    local nvmrc_node_version=$(nvm version "$(cat "$nvmrc_path")")
    if [[ $nvmrc_node_version == "N/A" ]]; then
      nvm install
    elif [[ $nvmrc_node_version != "$(nvm version)" ]]; then
      nvm use
    fi
  elif [[ -n "$(PWD=$OLDPWD nvm_find_nvmrc)" && "$(nvm version)" != "$(nvm version default)" ]]; then
    print "Reverting to nvm default version"
    nvm use default
  fi
}

autoload -U add-zsh-hook
add-zsh-hook chpwd load-nvmrc
load-nvmrc
