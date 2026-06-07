#!/usr/bin/env bash
# lib/package-managers.sh — abstracción de instalación de paquetes
# Detecta el gestor y expone funciones: pkg_update, pkg_install, pkg_exists, pkg_add_repo

pkg_update() {
  case "$DOTFILES_PKG_MANAGER" in
    dnf|dnf5)
      sudo_run $DOTFILES_PKG_MANAGER check-update -y >/dev/null 2>&1 || true
      ;;
    apt)
      sudo_run apt-get update -qq
      ;;
    pacman)
      sudo_run pacman -Sy --noconfirm --quiet
      ;;
    brew)
      brew update --quiet
      ;;
    zypper)
      sudo_run zypper --quiet refresh
      ;;
    apk)
      sudo_run apk update --quiet
      ;;
    *)
      log_warn "pkg_update: gestor '$DOTFILES_PKG_MANAGER' no soportado"
      return 1
      ;;
  esac
}

pkg_install() {
  local pkgs=("$@")
  [ "${#pkgs[@]}" -eq 0 ] && return 0

  case "$DOTFILES_PKG_MANAGER" in
    dnf|dnf5)
      sudo_run $DOTFILES_PKG_MANAGER install -y "${pkgs[@]}"
      ;;
    apt)
      sudo_run apt-get install -y --no-install-recommends "${pkgs[@]}"
      ;;
    pacman)
      sudo_run pacman -S --noconfirm --needed "${pkgs[@]}"
      ;;
    brew)
      brew install "${pkgs[@]}"
      ;;
    zypper)
      sudo_run zypper --non-interactive install "${pkgs[@]}"
      ;;
    apk)
      sudo_run apk add --no-cache "${pkgs[@]}"
      ;;
    *)
      log_warn "pkg_install: gestor '$DOTFILES_PKG_MANAGER' no soportado"
      return 1
      ;;
  esac
}

pkg_exists() {
  case "$DOTFILES_PKG_MANAGER" in
    dnf|dnf5)
      $DOTFILES_PKG_MANAGER list -q installed "$1" 2>/dev/null | grep -q "^$1"
      ;;
    apt)
      dpkg -l "$1" 2>/dev/null | grep -q "^ii"
      ;;
    pacman)
      pacman -Q "$1" 2>/dev/null | grep -q "^$1"
      ;;
    brew)
      brew list --formula "$1" 2>/dev/null | grep -q "^$1"
      ;;
    zypper)
      rpm -q "$1" >/dev/null 2>&1
      ;;
    apk)
      apk info -e "$1" >/dev/null 2>&1
      ;;
    *)
      command -v "$1" >/dev/null 2>&1
      ;;
  esac
}

# Verifica comando, intenta instalar si no está
ensure_cmd() {
  local cmd="$1"
  shift || true
  local pkgs=("$@")
  if command -v "$cmd" >/dev/null 2>&1; then
    log_debug "ensure_cmd: '$cmd' ya presente"
    return 0
  fi
  if [ "${#pkgs[@]}" -eq 0 ]; then
    pkgs=("$cmd")
  fi
  log_info "instalando $cmd (${pkgs[*]})"
  pkg_install "${pkgs[@]}"
}

# ── AUR helper (Arch) ────────────────────────────────────
aur_install() {
  if command -v paru >/dev/null 2>&1; then
    paru -S --noconfirm --needed "$@"
  elif command -v yay >/dev/null 2>&1; then
    yay -S --noconfirm --needed "$@"
  else
    log_warn "AUR helper (paru/yay) no encontrado"
    return 1
  fi
}
