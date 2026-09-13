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
# No alias find→fd: rompe scripts (p.ej. SDKMAN usa find -type f;
# fd interpreta -type como --type ype).
alias ff='fd'
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

# Docker: prefer compose mem_limit <= 4g en este hardware

export CURSOR_MAX_MEMORY=4096

export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# ─── Dotfiles scripts (bin/) ──────────────────────────
# Scripts y utilidades del repositorio de dotfiles
_DOTFILES_BIN="${DOTFILES_DIR:-$HOME/.dotfiles}/bin"
if [[ -d "$_DOTFILES_BIN" ]]; then
  case ":$PATH:" in
    *":$_DOTFILES_BIN:"*) ;;  # ya en el PATH
    *) export PATH="$_DOTFILES_BIN:$PATH" ;;
  esac
fi
unset _DOTFILES_BIN


# Added by Antigravity CLI installer
export PATH="/home/algforge/.local/bin:$PATH"

export AGY_IDE_MAX_MEMORY=4096

export ANDROID_HOME="$HOME/Android/Sdk"

export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

export GRADLE_OPTS="${GRADLE_OPTS:--Xmx1536m -Dorg.gradle.daemon=true -Dorg.gradle.parallel=true -Dorg.gradle.workers.max=4}"

alias py314=python3.14

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

export GOPATH="$HOME/go"

export PATH="$HOME/.local/go/bin:$GOPATH/bin:$PATH"

export PNPM_HOME="$HOME/.local/share/pnpm"

case ":$PATH:" in *":$PNPM_HOME:"*) ;; *) export PATH="$PNPM_HOME:$PATH" ;; esac
source "$HOME/.config/matrix-aliases.sh"
