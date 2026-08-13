# Usage: wtree <git-repo> [directory]
# Clones as a bare repo (.bare/) with a .git pointer, ready for worktrees.
# With no [directory]: uses the directory dir if empty, otherwise creates one named after the repo.
wtree() {
  emulate -L zsh
  local url=$1
  if [[ -z $url ]]; then
    print -ru2 -- "usage: $0 <git-repo> [directory]"
    return 1
  fi

  local dir=$2
  local -a entries
  if [[ -z $dir ]]; then
    entries=( *(DNY1) )
    if (( $#entries == 0 )); then
      dir=.
    else
      dir=${${url:t}%.git}
    fi
  fi

  mkdir -p $dir && cd -q $dir || return
  entries=( *(DNY1) )
  if (( $#entries )); then
    print -ru2 -- "❌ Error: $PWD is not empty"
    return 1
  fi

  print "🚀 Initializing bare worktree setup..."
  git clone --bare $url .bare || return

  print -r -- "gitdir: ./.bare" > .git

  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git fetch --all

  print "✅ Setup complete!"
  print "Next step: git worktree add main"
}