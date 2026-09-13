#!/usr/bin/env bash
# ==============================================================================
# setup/dev-setup.sh — Developer environment setup (cross-distro)
#
# Description : Installs a modern CLI dev environment:
#               git, curl, wget, zsh, neovim, ripgrep, fd, fzf, bat,
#               eza (or lsd on some distros), btop.
#               Then installs Starship prompt and LazyVim.
#               Idempotent — skips tools that are already present.
#
# OS support  : Fedora / RHEL / Rocky · Ubuntu / Debian / Pop!_OS ·
#               Arch / Manjaro / EndeavourOS · macOS (Homebrew)
#
# Dependencies: lib/detect.sh, lib/logger.sh, lib/package-managers.sh
#               sudo (Linux), curl, git, unzip
#
# Usage       : ./dev-setup.sh [--dry-run] [--yes] [--skip-lazyvim] [--skip-starship]
#                 --dry-run         Print actions without executing them
#                 --yes             Assume yes on all confirmations
#                 --skip-lazyvim    Skip LazyVim installation
#                 --skip-starship   Skip Starship prompt installation
# ==============================================================================

set -euo pipefail

# ── Resolve dotfiles root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Source libraries ─────────────────────────────────────────────────────────
# shellcheck source=../../lib/detect.sh
source "${DOTFILES_ROOT}/lib/detect.sh"
# shellcheck source=../../lib/logger.sh
source "${DOTFILES_ROOT}/lib/logger.sh"
# shellcheck source=../../lib/package-managers.sh
source "${DOTFILES_ROOT}/lib/package-managers.sh"

# ── Parse flags ─────────────────────────────────────────────────────────────
SKIP_LAZYVIM=false
SKIP_STARSHIP=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)        export DOTFILES_DRY_RUN=true ;;
    --yes|-y)         export DOTFILES_ASSUME_YES=true ;;
    --skip-lazyvim)   SKIP_LAZYVIM=true ;;
    --skip-starship)  SKIP_STARSHIP=true ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# ── Detect ───────────────────────────────────────────────────────────────────
detect_os

log_section "Dev Setup — ${DOTFILES_DISTRO} (${DOTFILES_PKG_MANAGER})"

# ── Step 1: CLI tools ────────────────────────────────────────────────────────
log_section "Step 1: CLI developer tools"

# Package names differ across distros/OS
case "${DOTFILES_PKG_MANAGER}" in
  dnf|dnf5)
    # fd-find ships as 'fd-find' on Fedora, binary is 'fd'
    # eza is available from RPM Fusion / COPR; fall back to lsd if absent
    DEV_PKGS=(git curl wget zsh neovim ripgrep fd-find fzf bat lsd btop)
    ;;
  apt)
    # fd-find ships as 'fd-find', binary is 'fdfind' (symlink manually or via batcat/fd)
    # eza not in base repos on older Ubuntu — use lsd instead
    DEV_PKGS=(git curl wget zsh neovim ripgrep fd-find fzf bat lsd btop)
    ;;
  pacman)
    # Arch has native packages for all tools
    DEV_PKGS=(git curl wget zsh neovim ripgrep fd fzf bat eza btop)
    ;;
  brew)
    # macOS / Homebrew
    DEV_PKGS=(git curl wget zsh neovim ripgrep fd fzf bat eza btop)
    ;;
  *)
    log_warn "Unknown package manager '${DOTFILES_PKG_MANAGER}' — using generic list"
    DEV_PKGS=(git curl wget zsh neovim ripgrep fd fzf bat btop)
    ;;
esac

run pkg_update
run pkg_install "${DEV_PKGS[@]}"
log_success "CLI tools installed"

# fd-find: on Debian/Ubuntu the binary is 'fdfind', create symlink 'fd' for convenience
if [[ "${DOTFILES_PKG_MANAGER}" == "apt" ]]; then
  if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    mkdir -p "${HOME}/.local/bin"
    ln -sf "$(command -v fdfind)" "${HOME}/.local/bin/fd"
    log_success "Symlinked fdfind → ~/.local/bin/fd"
  fi
fi

# ── Step 2: Change default shell to zsh ─────────────────────────────────────
log_section "Step 2: Default shell"

CURRENT_SHELL="$(basename "${SHELL:-}")"
if [[ "${CURRENT_SHELL}" == "zsh" ]]; then
  log_skip "zsh is already the default shell"
else
  ZSH_PATH="$(command -v zsh 2>/dev/null || true)"
  if [[ -z "${ZSH_PATH}" ]]; then
    log_warn "zsh binary not found — shell not changed"
  else
    if confirm "Change default shell to zsh (${ZSH_PATH})?"; then
      if [[ "${DOTFILES_OS}" == "linux" ]]; then
        run sudo_run chsh -s "${ZSH_PATH}" "${USER}"
      else
        run chsh -s "${ZSH_PATH}"
      fi
      log_success "Default shell changed to zsh — re-login to apply"
    fi
  fi
fi

# ── Step 3: Starship prompt ──────────────────────────────────────────────────
if [[ "${SKIP_STARSHIP}" == "false" ]]; then
  log_section "Step 3: Starship prompt"

  if command -v starship &>/dev/null; then
    log_skip "Starship already installed ($(starship --version | head -1))"
  else
    run curl -sS https://starship.rs/install.sh | sh -s -- -y
    log_success "Starship installed"
  fi

  # Create a minimal starter config if none exists
  STARSHIP_CONF="${HOME}/.config/starship.toml"
  mkdir -p "${HOME}/.config"
  if [[ ! -f "${STARSHIP_CONF}" ]]; then
    cat > "${STARSHIP_CONF}" <<'TOML'
# Starship configuration — generated by dev-setup.sh
add_newline = false

[character]
success_symbol = "[➜](bold green)"
error_symbol   = "[✗](bold red)"

[git_branch]
symbol = "🌱 "
style  = "bold purple"

[python]
symbol = "🐍 "
style  = "yellow dim"

[nodejs]
symbol = "⬢ "
style  = "green dim"

[rust]
symbol = "🦀 "
style  = "red dim"
TOML
    log_success "Starship config created at ${STARSHIP_CONF}"
  else
    log_skip "Starship config already exists at ${STARSHIP_CONF}"
  fi

  # Add eval line to .zshrc if not already present
  ZSHRC="${HOME}/.zshrc"
  if [[ -f "${ZSHRC}" ]] && grep -q 'starship init zsh' "${ZSHRC}"; then
    log_skip "Starship already wired in .zshrc"
  else
    run echo 'eval "$(starship init zsh)"' >> "${ZSHRC}"
    log_success "Starship init added to .zshrc"
  fi
else
  log_skip "Starship — skipped via --skip-starship"
fi

# ── Step 4: LazyVim ──────────────────────────────────────────────────────────
if [[ "${SKIP_LAZYVIM}" == "false" ]]; then
  log_section "Step 4: LazyVim (Neovim distribution)"

  NVIM_CONFIG="${HOME}/.config/nvim"

  if [[ -d "${NVIM_CONFIG}" ]] && [[ -f "${NVIM_CONFIG}/lua/config/lazy.lua" ]]; then
    log_skip "LazyVim config already present at ${NVIM_CONFIG}"
  else
    # Backup existing nvim config
    if [[ -d "${NVIM_CONFIG}" ]]; then
      BACKUP="${NVIM_CONFIG}.bak.$(date +%s)"
      log_warn "Existing nvim config found — backing up to ${BACKUP}"
      run mv "${NVIM_CONFIG}" "${BACKUP}"
    fi

    # Clone LazyVim starter
    run git clone --depth 1 https://github.com/LazyVim/starter "${NVIM_CONFIG}"

    # Detach from the starter's git history so the user owns the config
    run rm -rf "${NVIM_CONFIG}/.git"

    log_success "LazyVim starter cloned to ${NVIM_CONFIG}"
    log_hint "Open nvim — LazyVim will bootstrap itself automatically on first launch"
  fi

  # Create plugin directory for extra specs
  mkdir -p "${NVIM_CONFIG}/lua/plugins"

  EXTRAS_FILE="${NVIM_CONFIG}/lua/plugins/dev-extras.lua"
  if [[ ! -f "${EXTRAS_FILE}" ]]; then
    cat > "${EXTRAS_FILE}" <<'LUA'
-- dev-extras.lua — generated by dev-setup.sh
-- Enable LazyVim language extras. Add/remove as needed.
return {
  { import = "lazyvim.plugins.extras.lang.python" },
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.lang.json" },
  { import = "lazyvim.plugins.extras.lang.docker" },
  { import = "lazyvim.plugins.extras.formatting.prettier" },
  { import = "lazyvim.plugins.extras.linting.eslint" },
  { import = "lazyvim.plugins.extras.editor.leap" },
}
LUA
    log_success "LazyVim extras spec written to ${EXTRAS_FILE}"
  else
    log_skip "LazyVim extras spec already present"
  fi
else
  log_skip "LazyVim — skipped via --skip-lazyvim"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
log_section "Dev setup complete"
log_hint "Re-login (or source your .zshrc) to enjoy the new shell environment."
