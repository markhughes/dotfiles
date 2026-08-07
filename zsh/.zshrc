export ZSH="$HOME/.oh-my-zsh"

# leave as blank for starship
ZSH_THEME=""

ENABLE_CORRECTION="true"
DISABLE_MAGIC_FUNCTIONS="true"

# plugins
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-you-should-use docker aws brew)

source $ZSH/oh-my-zsh.sh

export LANG=en_AU.UTF-8

# brew (strip pyenv shims so brew never links against a pyenv python; PATH set in .zprofile)
alias brew='env PATH="${PATH//$(pyenv root)\/shims:/}" brew'

# user-local binaries 
export PATH="$HOME/.local/bin:$PATH"

HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE

# force neovim
export EDITOR='nvim'
alias vim='nvim'
alias vi='nvim'

# NVM 
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# GO
export GOPATH="$HOME/go"
export PATH="$PATH:$GOPATH/bin"

# rust cargo
. "$HOME/.cargo/env" 

# pyenv (shim init for interactive shells; PYENV_ROOT/PATH set in .zprofile)
command -v pyenv >/dev/null && eval "$(pyenv init - zsh)"

# fzf key bindings and completion
source <(fzf --zsh)

# Starship
eval "$(starship init zsh)"


# Local machine-only config (not tracked in dotfiles).
# Put per-machine settings, secrets, and overrides in ~/.zshrc.local
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
