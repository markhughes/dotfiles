# Login-shell config. Sourced once per login shell, before .zshrc.
# Keep interactive settings in .zshrc; put PATH/env setup here.

# Homebrew (Apple Silicon vs Intel)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# pyenv (PATH setup for login shells; shim init lives in .zshrc)
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
