#!/usr/bin/env bash
# scripts/verify.sh — verifica que la instalación está completa

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/logger.sh"

log_section "Verificación del entorno"

pass=0
fail=0
declare -a missing=()

check() {
  local name="$1"
  local cmd="${2:-command -v $1}"
  if eval "$cmd" >/dev/null 2>&1; then
    log_success "$name"
    pass=$((pass+1))
  else
    log_warn "$name (faltante)"
    missing+=("$name")
    fail=$((fail+1))
  fi
}

# Core
check "git" "command -v git"
check "curl" "command -v curl"
check "zsh" "command -v zsh"
check "vim o nvim" "command -v nvim || command -v vim"

# Search & nav
check "ripgrep (rg)" "command -v rg"
check "fd" "command -v fd"
check "fzf" "command -v fzf"
check "zoxide" "command -v zoxide"

# Viewers
check "bat" "command -v bat"
check "eza" "command -v eza"
check "btop" "command -v btop"
check "duf" "command -v duf"
check "dust" "command -v dust"

# Git tooling
check "lazygit" "command -v lazygit"
check "git-delta" "command -v delta"

# Multiplexer
check "tmux" "command -v tmux"
check "tpm" "[ -d $HOME/.tmux/plugins/tpm ]"

# Terminal
check "kitty" "command -v kitty"
check "nerd font" "fc-list | grep -qi JetBrainsMonoNerdFont"

# Runtimes
check "node" "command -v node"
check "npm" "command -v npm"
check "python3" "command -v python3"
check "uv" "command -v uv"
check "mise" "command -v mise"

# Agentic
check "claude" "command -v claude"
check "ollama" "command -v ollama"
check "agents dir" "[ -d $HOME/agents ]"

# Configs linkeados
check "~/.zshrc linked" "[ -L $HOME/.zshrc ] || [ -f $HOME/.zshrc ]"
check "~/.tmux.conf linked" "[ -L $HOME/.tmux.conf ] || [ -f $HOME/.tmux.conf ]"
check "kitty.conf" "[ -f $HOME/.config/kitty/kitty.conf ]"
check "starship.toml" "[ -f $HOME/.config/starship.toml ]"

# System tweaks (Linux)
if [ "$(uname -s)" = "Linux" ]; then
  check "sysctl tuned" "grep -q 'managed by dotfiles-agentic' /etc/sysctl.d/99-dotfiles-agentic.conf"
  check "zram config" "[ -f /etc/systemd/zram-generator.conf ] && grep -q 'dotfiles-agentic' /etc/systemd/zram-generator.conf"
  check "fstrim.timer" "systemctl is-active fstrim.timer"
  check "TCP BBR" "sysctl net.ipv4.tcp_congestion_control | grep -q bbr"
fi

echo
log_info "resultado: $pass OK, $fail faltantes"

if [ "$fail" -gt 0 ]; then
  echo
  log_warn "componentes faltantes:"
  for m in "${missing[@]}"; do
    echo "  - $m"
  done
  echo
  log_info "para instalarlos todos, corre:"
  echo "  ./setup.sh"
  exit 1
fi

log_success "entorno verificado correctamente"
