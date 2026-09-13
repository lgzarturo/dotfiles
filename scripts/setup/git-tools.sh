#!/usr/bin/env bash
# ==============================================================================
# setup/git-tools.sh — GitHub CLI (gh) and lazygit installation
#
# Description : Installs gh (GitHub CLI) and lazygit using the official
#               method for each supported distribution/OS. Also adds
#               convenience aliases to .zshrc (idempotent).
#
# OS support  : Fedora / RHEL · Ubuntu / Debian · Arch / Manjaro · macOS
#
# Dependencies: lib/detect.sh, lib/logger.sh, lib/package-managers.sh
#               sudo (Linux), curl
#
# Usage       : ./git-tools.sh [--dry-run] [--yes]
#                 --dry-run   Print actions without executing them
#                 --yes       Assume yes on all confirmations
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
for arg in "$@"; do
  case "$arg" in
    --dry-run) export DOTFILES_DRY_RUN=true ;;
    --yes|-y)  export DOTFILES_ASSUME_YES=true ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# ── Detect ───────────────────────────────────────────────────────────────────
detect_os

log_section "Git Tools — ${DOTFILES_DISTRO} (${DOTFILES_PKG_MANAGER})"

# ════════════════════════════════════════════════════════════════════════════
# 1. GitHub CLI (gh)
# ════════════════════════════════════════════════════════════════════════════
log_section "Step 1: GitHub CLI (gh)"

if command -v gh &>/dev/null; then
  log_skip "gh already installed ($(gh --version | head -1))"
else
  case "${DOTFILES_PKG_MANAGER}" in
    dnf|dnf5)
      # Official RPM repository from cli.github.com
      run sudo_run "${DOTFILES_PKG_MANAGER}" config-manager addrepo \
        --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
      run pkg_install gh
      ;;
    apt)
      # Official DEB repository
      run sudo_run mkdir -p /etc/apt/keyrings
      GITHUB_CLI_KEYRING_TMP="$(mktemp)"
      run curl -fsSL -o "${GITHUB_CLI_KEYRING_TMP}" https://cli.github.com/packages/githubcli-archive-keyring.gpg
      if [[ ! -s "${GITHUB_CLI_KEYRING_TMP}" ]]; then
        rm -f "${GITHUB_CLI_KEYRING_TMP}"
        log_fatal "keyring de GitHub CLI vacío o no descargado"
      fi
      run sudo_run install -m 0644 "${GITHUB_CLI_KEYRING_TMP}" /usr/share/keyrings/githubcli-archive-keyring.gpg
      rm -f "${GITHUB_CLI_KEYRING_TMP}"
      run sudo_run chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo_run tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      run sudo_run apt-get update -qq
      run pkg_install gh
      ;;
    pacman)
      # Available in the community/extra repository
      run pkg_install github-cli
      ;;
    brew)
      run brew install gh
      ;;
    *)
      log_warn "Unsupported package manager '${DOTFILES_PKG_MANAGER}' for gh — install manually"
      log_hint "  https://github.com/cli/cli/releases/latest"
      ;;
  esac
  log_success "gh installed"
fi

# ════════════════════════════════════════════════════════════════════════════
# 2. lazygit
# ════════════════════════════════════════════════════════════════════════════
log_section "Step 2: lazygit"

if command -v lazygit &>/dev/null; then
  log_skip "lazygit already installed ($(lazygit --version | head -1))"
else
  case "${DOTFILES_PKG_MANAGER}" in
    dnf|dnf5)
      # Fedora COPR by atim (maintained, up-to-date)
      run sudo_run "${DOTFILES_PKG_MANAGER}" copr enable atim/lazygit -y
      run pkg_install lazygit
      ;;
    apt)
      if pkg_install lazygit; then
        :
      else
        log_warn "lazygit no disponible vía APT — instala manualmente desde una fuente verificada"
      fi
      ;;
    pacman)
      # Available in the community/extra repository
      run pkg_install lazygit
      ;;
    brew)
      run brew install lazygit
      ;;
    *)
      log_warn "Unsupported package manager '${DOTFILES_PKG_MANAGER}' for lazygit — install manually"
      log_hint "  https://github.com/jesseduffield/lazygit/releases/latest"
      ;;
  esac
  log_success "lazygit installed"
fi

# ════════════════════════════════════════════════════════════════════════════
# 3. Shell aliases (idempotent)
# ════════════════════════════════════════════════════════════════════════════
log_section "Step 3: Shell aliases"

ZSHRC="${HOME}/.zshrc"
touch "${ZSHRC}"

if grep -q 'alias lg=' "${ZSHRC}"; then
  log_skip "Git aliases already present in .zshrc"
else
  run tee -a "${ZSHRC}" > /dev/null <<'EOF'

# GitHub & Git aliases — added by git-tools.sh
alias lg='lazygit'
alias gpr='gh pr checkout'     # Quick PR checkout
alias gcreate='gh repo create' # Create repo from CLI
EOF
  log_success "Git aliases added to .zshrc"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
log_section "Git tools setup complete"
log_hint "Next steps:"
log_hint "  1. Authenticate: gh auth login"
log_hint "     (choose GitHub.com → HTTPS → Login with a web browser)"
log_hint "  2. Wire credentials: gh auth setup-git"
log_hint "  3. Open lazygit in any repo: lg (alias) or lazygit"
