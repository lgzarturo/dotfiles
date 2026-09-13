#!/usr/bin/env bash
# ==============================================================================
# setup/bootstrap.sh — Base system provisioning
#
# Description : Installs core utilities, thermald (Linux only), and Docker CE.
#               Configures the package manager for performance where supported.
#               Also installs mise (polyglot version manager) as the real user.
#
# OS support  : Fedora / RHEL / Rocky · Ubuntu / Debian / Pop!_OS ·
#               Arch / Manjaro / EndeavourOS · macOS (Homebrew)
#
# Dependencies: lib/detect.sh, lib/logger.sh, lib/package-managers.sh
#               sudo, curl, systemctl (Linux)
#
# Usage       : sudo ./bootstrap.sh [--dry-run] [--yes]
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
    --dry-run)  export DOTFILES_DRY_RUN=true ;;
    --yes|-y)   export DOTFILES_ASSUME_YES=true ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# ── Detect environment ───────────────────────────────────────────────────────
detect_os
detect_hardware

# ── Guard: must run as root (or via sudo) on Linux ──────────────────────────
if [[ "${DOTFILES_OS}" == "linux" ]] && [[ "$(id -u)" -ne 0 ]]; then
  log_fatal "Run this script with sudo: sudo $0"
fi

REAL_USER="${SUDO_USER:-$(whoami)}"

log_section "Bootstrap — ${DOTFILES_DISTRO} ${DOTFILES_DISTRO_VERSION}"
print_environment

# ── Step 1: Optimize package manager (Fedora/DNF only) ─────────────────────
if [[ "${DOTFILES_PKG_MANAGER}" == "dnf" || "${DOTFILES_PKG_MANAGER}" == "dnf5" ]]; then
  log_section "Step 1: Optimise DNF configuration"
  DNF_CONF="/etc/dnf/dnf.conf"
  declare -a DNF_OPTS=(
    "max_parallel_downloads=10"
    "defaultyes=True"
    "clean_requirements_on_remove=True"
    "installonly_limit=3"
    "keepcache=False"
  )
  for opt in "${DNF_OPTS[@]}"; do
    if grep -qF "${opt}" "${DNF_CONF}" 2>/dev/null; then
      log_skip "dnf.conf: ${opt}"
    else
      run echo "${opt}" >> "${DNF_CONF}"
      log_success "dnf.conf: ${opt}"
    fi
  done
fi

# ── Step 2: Enable extra repos (distro-specific) ────────────────────────────
log_section "Step 2: Enable additional repositories"

case "${DOTFILES_PKG_MANAGER}" in
  dnf|dnf5)
    # RPM Fusion (free + nonfree)
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
      FEDORA_VER="$(rpm -E %fedora)"
      run sudo_run "${DOTFILES_PKG_MANAGER}" install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
      log_success "RPM Fusion repositories enabled"
    else
      log_skip "RPM Fusion already enabled"
    fi
    # Flathub
    if command -v flatpak &>/dev/null; then
      run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      log_success "Flathub remote registered"
    fi
    ;;
  apt)
    run sudo_run apt-get update -qq
    ensure_cmd curl curl
    ensure_cmd wget wget
    # Add universe repo on Ubuntu if missing
    if command -v add-apt-repository &>/dev/null; then
      run sudo_run add-apt-repository -y universe 2>/dev/null || true
      run sudo_run apt-get update -qq
    fi
    log_success "APT repositories refreshed"
    ;;
  pacman)
    # Ensure multilib is enabled for Arch
    if ! grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
      log_hint "Consider enabling [multilib] in /etc/pacman.conf for 32-bit support"
    fi
    run sudo_run pacman -Syy --noconfirm --quiet
    log_success "Pacman databases refreshed"
    ;;
  brew)
    run brew update --quiet
    log_success "Homebrew updated"
    ;;
esac

# ── Step 3: thermald — thermal mitigation (Linux only) ──────────────────────
log_section "Step 3: Thermal management (Linux only)"

if [[ "${DOTFILES_OS}" == "linux" ]]; then
  # thermald is Intel/Hybrid-Intel only; useful for Alder/Raptor Lake
  if [[ "${DOTFILES_CPU_VENDOR}" =~ [Gg]enuine[Ii]ntel ]] || \
     [[ "${DOTFILES_CPU_PROFILE}" == "intel" ]]; then
    if command -v thermald &>/dev/null; then
      log_skip "thermald already installed"
    else
      run pkg_install thermald
      log_success "thermald installed"
    fi
    if [[ "${DOTFILES_INIT_SYSTEM}" == "systemd" ]]; then
      run sudo_run systemctl enable --now thermald
      log_success "thermald service enabled"
    fi
  else
    log_skip "thermald — not an Intel CPU (${DOTFILES_CPU_PROFILE}), skipping"
  fi
else
  log_skip "thermald — Linux only, skipping on ${DOTFILES_OS}"
fi

# ── Step 4: Core utilities ───────────────────────────────────────────────────
log_section "Step 4: Core utilities"

# Package names vary by distro
case "${DOTFILES_PKG_MANAGER}" in
  dnf|dnf5)
    CORE_PKGS=(curl wget git jq htop tmux zsh neovim util-linux-user)
    ;;
  apt)
    CORE_PKGS=(curl wget git jq htop tmux zsh neovim)
    ;;
  pacman)
    CORE_PKGS=(curl wget git jq htop tmux zsh neovim)
    ;;
  brew)
    CORE_PKGS=(curl wget git jq htop tmux zsh neovim)
    ;;
  *)
    CORE_PKGS=(curl wget git jq htop tmux zsh neovim)
    ;;
esac

run pkg_update
run pkg_install "${CORE_PKGS[@]}"
log_success "Core packages installed"

# ── Step 5: Docker CE ────────────────────────────────────────────────────────
log_section "Step 5: Docker CE"

if command -v docker &>/dev/null; then
  log_skip "Docker already installed ($(docker --version 2>/dev/null | head -1))"
else
  case "${DOTFILES_PKG_MANAGER}" in
    dnf|dnf5)
      run sudo_run "${DOTFILES_PKG_MANAGER}" install -y dnf-plugins-core
      run sudo_run "${DOTFILES_PKG_MANAGER}" config-manager addrepo --overwrite \
        --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
      run sudo_run "${DOTFILES_PKG_MANAGER}" install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    apt)
      run sudo_run apt-get install -y ca-certificates curl gnupg lsb-release
      run sudo_run install -m 0755 -d /etc/apt/keyrings
      run curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo_run gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      run sudo_run chmod a+r /etc/apt/keyrings/docker.gpg
      DOCKER_ARCH="$(dpkg --print-architecture)"
      DOCKER_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")"
      echo \
        "deb [arch=${DOCKER_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${DOCKER_CODENAME} stable" \
        | sudo_run tee /etc/apt/sources.list.d/docker.list > /dev/null
      run sudo_run apt-get update -qq
      run sudo_run apt-get install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    pacman)
      run sudo_run pacman -S --noconfirm --needed docker docker-compose
      ;;
    brew)
      log_hint "On macOS, install Docker Desktop from https://www.docker.com/products/docker-desktop/"
      ;;
    *)
      log_warn "Unknown package manager '${DOTFILES_PKG_MANAGER}' — skipping Docker install"
      ;;
  esac

  if [[ "${DOTFILES_OS}" == "linux" ]] && command -v docker &>/dev/null; then
    if [[ "${DOTFILES_INIT_SYSTEM}" == "systemd" ]]; then
      run sudo_run systemctl enable --now docker
      log_success "Docker service enabled"
    fi
    # Add real user to docker group
    if ! groups "${REAL_USER}" | grep -q '\bdocker\b'; then
      run sudo_run usermod -aG docker "${REAL_USER}"
      log_hint "User '${REAL_USER}' added to docker group — log out and back in to apply"
    else
      log_skip "User '${REAL_USER}' already in docker group"
    fi
    log_success "Docker CE installed"
  fi
fi

# ── Step 6: mise — polyglot version manager ─────────────────────────────────
log_section "Step 6: mise (polyglot version manager)"

if su - "${REAL_USER}" -c 'command -v mise' &>/dev/null 2>&1; then
  log_skip "mise already installed"
else
  run su - "${REAL_USER}" -c 'curl https://mise.run | sh'
  # Activate in bash
  BASHRC="/home/${REAL_USER}/.bashrc"
  if [[ -f "${BASHRC}" ]] && ! grep -q 'mise activate bash' "${BASHRC}"; then
    run su - "${REAL_USER}" -c \
      'echo "eval \"$(~/.local/bin/mise activate bash)\"" >> ~/.bashrc'
    log_success "mise activation added to .bashrc"
  fi
  log_success "mise installed"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
log_section "Bootstrap complete"
log_hint "Reboot (or re-login) to apply Docker group membership and any shell changes."
