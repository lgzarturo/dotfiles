# ─────────────────────────────────────────────
# zsh config — dotfiles
# ─────────────────────────────────────────────

# Historial
HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY INC_APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE
setopt AUTO_CD CORRECT AUTO_PUSHD PUSHD_IGNORE_DUPS

# Bindkeys Vim-style
bindkey -v
bindkey '^P' history-search-backward
bindkey '^N' history-search-forward
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^K' kill-line
bindkey '^R' history-incremental-search-backward

# ─── Plugins via Zap ───────────────────────
if [ -f ~/.local/share/zap/zap.zsh ]; then
  plugin-list=(
    zsh-users/zsh-autosuggestions
    zsh-users/zsh-syntax-highlighting
    zsh-users/zsh-completions
    agkozak/zsh-z
    changyuheng/fz
  )
  source ~/.local/share/zap/zap.zsh
  plugin "$plugin-list"
fi

# ─── Aliases agenticos ─────────────────────
alias ll='eza -al --group --git --icons'
alias ls='eza --icons'
alias cat='bat --paging=never --style=plain'
alias grep='rg'
alias find='fd'
alias top='btop'
alias df='duf'
alias du='dust'
alias lg='lazygit'
alias g='git'
alias vim='nvim'

# Claude Code
if command -v claude >/dev/null 2>&1; then
  alias claude-fresh='tmux new-session -d -s claude && tmux send-keys -t claude "claude" Enter && tmux attach -t claude'
fi

# Atajos
alias ..='cd ..'
alias ...='cd ../..'
alias reload='source ~/.zshrc && echo "zsh recargado"'
alias paths='echo $PATH | tr ":" "\n"'
alias newproj='new-agent-project'

# ─── Runtimes ─────────────────────────────
[ -f ~/.local/bin/mise ] && eval "$(~/.local/bin/mise activate zsh 2>/dev/null)"

# ─── Starship ─────────────────────────────
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# ─── Local overrides ──────────────────────
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
