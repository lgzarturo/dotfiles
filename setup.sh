#!/usr/bin/env bash
# setup.sh — entry point principal para Linux/macOS/WSL
# Detecta SO + hardware, ejecuta pipeline de instalación.

set -euo pipefail

# ─── Paths ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CONFIG_DIR="$SCRIPT_DIR/config"
BIN_DIR="$SCRIPT_DIR/bin"

# ─── Defaults ──────────────────────────────────────────────
DOTFILES_DRY_RUN="${DOTFILES_DRY_RUN:-false}"
DOTFILES_ASSUME_YES="${DOTFILES_ASSUME_YES:-false}"
DOTFILES_LOG_LEVEL="${DOTFILES_LOG_LEVEL:-INFO}"
DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"
DOTFILES_PROFILE="${DOTFILES_PROFILE:-auto}"
DOTFILES_SKIP="${DOTFILES_SKIP:-}"
DOTFILES_ONLY="${DOTFILES_ONLY:-}"
DOTFILES_INSTALL_OLLAMA="${DOTFILES_INSTALL_OLLAMA:-false}"
DOTFILES_BACKUP_DIR="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

# ─── Carga librerías ───────────────────────────────────────
# shellcheck source=lib/logger.sh
. "$LIB_DIR/logger.sh"
# shellcheck source=lib/detect.sh
. "$LIB_DIR/detect.sh"
# shellcheck source=lib/package-managers.sh
. "$LIB_DIR/package-managers.sh"
# shellcheck source=lib/sysctl-tune.sh
. "$LIB_DIR/sysctl-tune.sh"
# shellcheck source=lib/ssd-tune.sh
. "$LIB_DIR/ssd-tune.sh"
# shellcheck source=lib/ram-tune.sh
. "$LIB_DIR/ram-tune.sh"
# shellcheck source=lib/agent-tools.sh
. "$LIB_DIR/agent-tools.sh"

# ─── Banner ────────────────────────────────────────────────
banner() {
  cat <<'EOF'

  ┌───────────────────────────────────────────────┐
  │  dotfiles-agentic — entorno agentico portable  │
  └───────────────────────────────────────────────┘

EOF
}

# ─── CLI parsing ───────────────────────────────────────────
usage() {
  cat <<EOF
Uso: $0 [opciones]

Opciones:
  --yes, -y           Acepta todos los prompts
  --dry-run           Solo muestra lo que haría
  --profile NAME      laptop | desktop | workstation | minimal | auto
  --skip STEP,...     Pasos a saltar (ej: ssd,ram,sysctl)
  --only STEP,...     Solo corre estos pasos
  --install-ollama    Incluye Ollama (LLM local)
  --log-level LVL     TRACE | DEBUG | INFO | WARN | ERROR
  --log-file PATH     Archivo de log
  --backup-dir PATH   Directorio de backup
  --help, -h          Esta ayuda

Pasos disponibles (en orden):
  preflight, system-update, core-packages, shell, terminal,
  multiplexer, dev-tools, runtimes, agent-tools, gnome,
  sysctl, ssd, ram, network, dotfiles-link, post-install

Variables de entorno equivalentes:
  DOTFILES_DRY_RUN, DOTFILES_ASSUME_YES, DOTFILES_PROFILE,
  DOTFILES_SKIP, DOTFILES_ONLY, DOTFILES_INSTALL_OLLAMA,
  DOTFILES_LOG_LEVEL, DOTFILES_LOG_FILE, DOTFILES_BACKUP_DIR
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes|-y)             DOTFILES_ASSUME_YES=true ;;
      --dry-run)            DOTFILES_DRY_RUN=true ;;
      --profile)            DOTFILES_PROFILE="$2"; shift ;;
      --skip)               DOTFILES_SKIP="$2"; shift ;;
      --only)               DOTFILES_ONLY="$2"; shift ;;
      --install-ollama)     DOTFILES_INSTALL_OLLAMA=true ;;
      --log-level)          DOTFILES_LOG_LEVEL="$2"; shift ;;
      --log-file)           DOTFILES_LOG_FILE="$2"; shift ;;
      --backup-dir)         DOTFILES_BACKUP_DIR="$2"; shift ;;
      --help|-h)            usage; exit 0 ;;
      *)                    log_error "opción desconocida: $1"; usage; exit 1 ;;
    esac
    shift
  done

  export DOTFILES_DRY_RUN DOTFILES_ASSUME_YES DOTFILES_PROFILE
  export DOTFILES_SKIP DOTFILES_ONLY DOTFILES_INSTALL_OLLAMA
  export DOTFILES_LOG_LEVEL DOTFILES_LOG_FILE DOTFILES_BACKUP_DIR
}

# ─── Step helpers ──────────────────────────────────────────
in_skip() {
  [ -n "$DOTFILES_SKIP" ] && [[ ",$DOTFILES_SKIP," == *",$1,"* ]]
}

in_only() {
  [ -z "$DOTFILES_ONLY" ] && return 0   # no filter = run all
  [[ ",$DOTFILES_ONLY," == *",$1,"* ]]
}

should_run() {
  if in_skip "$1"; then
    log_skip "step: $1"
    return 1
  fi
  if ! in_only "$1"; then
    return 1
  fi
  return 0
}

# ─── Pre-flight ────────────────────────────────────────────
step_preflight() {
  should_run preflight || return 0
  log_section "Pre-flight checks"

  # Privilegios
  if [ "$DOTFILES_OS" = "linux" ] && [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    log_fatal "linux sin root y sin sudo — abortando"
  fi

  # Network
  if ! curl -sSf -m 5 https://github.com >/dev/null 2>&1; then
    log_warn "sin conectividad a GitHub — algunas instalaciones fallarán"
    if [ "$DOTFILES_DRY_RUN" != "true" ]; then
      confirm "continuar de todas formas?" "n" || exit 1
    fi
  fi

  # Disco mínimo
  local free_gb
  free_gb="$(df -BG "$HOME" | awk 'NR==2 {print $4}' | tr -d 'G')"
  if [ -n "$free_gb" ] && [ "$free_gb" -lt 5 ]; then
    log_warn "poco espacio en $HOME: ${free_gb}GB libres"
  fi

  log_success "preflight OK"
}

# ─── Backup ────────────────────────────────────────────────
step_backup() {
  should_run backup || return 0
  log_section "Backup de configs existentes"

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] backup a $DOTFILES_BACKUP_DIR"
    return 0
  fi

  mkdir -p "$DOTFILES_BACKUP_DIR"
  local files=(
    "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"
    "$HOME/.tmux.conf"
    "$HOME/.gitconfig"
    "$HOME/.config/kitty"
    "$HOME/.config/starship.toml"
  )
  for f in "${files[@]}"; do
    if [ -e "$f" ] && [ ! -L "$f" ]; then
      local rel
      rel="$(realpath --relative-to="$HOME" "$f" 2>/dev/null || echo "$f")"
      local dest="$DOTFILES_BACKUP_DIR/$rel"
      mkdir -p "$(dirname "$dest")"
      cp -a "$f" "$dest"
      log_success "backed up: $f"
    fi
  done
  log_info "backup completo en $DOTFILES_BACKUP_DIR"
}

# ─── System update ─────────────────────────────────────────
step_system_update() {
  should_run system-update || return 0
  log_section "System update"

  case "$DOTFILES_OS" in
    linux)
      log_info "actualizando paquetes del sistema"
      pkg_update
      sudo_run $DOTFILES_PKG_MANAGER upgrade -y || log_warn "upgrade parcial"
      ;;
    macos)
      log_info "macOS: omitiendo (no se actualiza el SO vía brew)"
      ;;
  esac
  log_success "system update"
}

# ─── Core packages ─────────────────────────────────────────
step_core_packages() {
  should_run core-packages || return 0
  log_section "Core packages"

  case "$DOTFILES_OS" in
    linux)
      local pkgs=(
        curl wget git vim nano
        ca-certificates gnupg
        build-essential  # no-op si no existe
        unzip zip tar xz
        openssh-client
        htop
        fontconfig
      )
      # Filtrar paquetes que no existen en la distro
      case "$DOTFILES_DISTRO" in
        fedora|rhel|centos|rocky|almalinux)
          pkgs=(
            curl wget git vim nano
            ca-certificates gnupg2
            gcc make
            unzip zip tar xz
            openssh
            htop
            fontconfig
            openssl-devel
          )
          ;;
      esac
      pkg_install "${pkgs[@]}"
      ;;
    macos)
      local formulae=(curl wget git vim nano htop)
      for f in "${formulae[@]}"; do
        if ! brew list --formula "$f" >/dev/null 2>&1; then
          brew install "$f" || true
        fi
      done
      ;;
  esac
  log_success "core packages"
}

# ─── Shell stack ───────────────────────────────────────────
step_shell() {
  should_run shell || return 0
  log_section "Shell stack (Zsh, Starship, plugins)"

  # Zsh
  if ! command -v zsh >/dev/null 2>&1; then
    pkg_install zsh
  fi

  # Starship
  if ! command -v starship >/dev/null 2>&1; then
    log_info "instalando Starship"
    if [ "$DOTFILES_DRY_RUN" != "true" ]; then
      curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
  fi

  # Zsh plugins via Zap
  if [ ! -d "$HOME/.local/share/zap" ]; then
    log_info "instalando Zap (zsh plugin manager)"
    if [ "$DOTFILES_DRY_RUN" != "true" ]; then
      zsh -c "$(curl -fsSL https://raw.githubusercontent.com/zap-zsh/zap/main/install.sh)" "" --silent
    fi
  fi

  # Linkear .zshrc
  _link_config "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"

  log_success "shell stack"
}

# ─── Terminal ──────────────────────────────────────────────
step_terminal() {
  should_run terminal || return 0
  log_section "Terminal emulator"

  case "$DOTFILES_OS" in
    linux)
      if ! command -v kitty >/dev/null 2>&1; then
        pkg_install kitty kitty-terminfo
      fi
      _link_config "$CONFIG_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
      # Nerd Font
      _install_nerd_font
      ;;
    macos)
      # Kitty está disponible vía brew
      if ! command -v kitty >/dev/null 2>&1; then
        brew install --cask kitty
      fi
      _link_config "$CONFIG_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
      _install_nerd_font
      ;;
  esac

  log_success "terminal"
}

_install_nerd_font() {
  local font_dir="$HOME/.local/share/fonts"
  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] instalaría JetBrains Mono Nerd Font"
    return 0
  fi
  mkdir -p "$font_dir"

  # Si ya está, no descargar de nuevo
  if ls "$font_dir" 2>/dev/null | grep -qi "JetBrainsMonoNerdFont"; then
    log_debug "nerd font ya presente"
    return 0
  fi

  log_info "descargando JetBrains Mono Nerd Font"
  local tmp
  tmp="$(mktemp -d)"
  (cd "$tmp" && \
    curl -sL -o jbm.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && \
    unzip -qo jbm.zip -d "$font_dir" && \
    rm jbm.zip) || log_warn "falló descarga de Nerd Font (puedes hacerlo manual)"
  rm -rf "$tmp"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv >/dev/null 2>&1
  fi
  log_success "Nerd Font instalado"
}

# ─── Multiplexer (tmux) ────────────────────────────────────
step_multiplexer() {
  should_run multiplexer || return 0
  log_section "tmux + plugins"

  if ! command -v tmux >/dev/null 2>&1; then
    pkg_install tmux
  fi

  # TPM
  [ -d "$HOME/.tmux/plugins/tpm" ] || git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"

  _link_config "$CONFIG_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
  log_success "tmux + TPM"
}

# ─── Dev tools ─────────────────────────────────────────────
step_dev_tools() {
  should_run dev-tools || return 0
  log_section "Dev CLI tools (rg, fd, bat, eza, fzf, lazygit)"

  case "$DOTFILES_OS" in
    linux)
      case "$DOTFILES_DISTRO" in
        fedora|*)
          pkg_install \
            ripgrep fd-find bat eza zoxide fzf btop duf dust \
            tldr neovim git-delta lazygit \
            jq yq
          # Copr útiles
          _enable_copr "alternateved/eza" || true
          ;;
        ubuntu|debian)
          sudo_run apt-get install -y --no-install-recommends \
            ripgrep fd-find bat fzf btop jq neovim
          # eza via cargo o .deb
          if ! command -v eza >/dev/null 2>&1; then
            sudo_run mkdir -p /etc/apt/keyrings
            wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
              | sudo_run gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
              | sudo_run tee /etc/apt/sources.list.d/gierens.list >/dev/null
            sudo_run apt-get update -qq
            sudo_run apt-get install -y eza
          fi
          ;;
      esac
      ;;
    macos)
      local formulae=(ripgrep fd bat eza zoxide fzf btop duf dust neovim lazygit jq yq tldr)
      for f in "${formulae[@]}"; do
        brew list --formula "$f" >/dev/null 2>&1 || brew install "$f" || true
      done
      ;;
  esac
  log_success "dev tools"
}

_enable_copr() {
  local repo="$1"
  if [ "$DOTFILES_PKG_MANAGER" != "dnf" ] && [ "$DOTFILES_PKG_MANAGER" != "dnf5" ]; then
    return 1
  fi
  if sudo_run $DOTFILES_PKG_MANAGER copr list 2>/dev/null | grep -q "$repo"; then
    return 0
  fi
  sudo_run $DOTFILES_PKG_MANAGER copr enable -y "$repo" || return 1
}

# ─── Runtimes (Node, Python, Go via mise) ─────────────────
step_runtimes() {
  should_run runtimes || return 0
  log_section "Runtimes (mise)"

  if ! command -v mise >/dev/null 2>&1; then
    log_info "instalando mise"
    if [ "$DOTFILES_DRY_RUN" != "true" ]; then
      curl https://mise.run | sh
    fi
  fi
  export PATH="$HOME/.local/bin:$PATH"

  if [ "$DOTFILES_DRY_RUN" != "true" ] && [ -f "$HOME/.config/mise/config.toml" ]; then
    log_info "instalando runtimes definidos"
    mise install --yes || true
  fi

  # uv para Python
  if ! command -v uv >/dev/null 2>&1; then
    log_info "instalando uv"
    if [ "$DOTFILES_DRY_RUN" != "true" ]; then
      curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
  fi

  log_success "runtimes"
}

# ─── Agent tools ───────────────────────────────────────────
step_agent_tools() {
  should_run agent-tools || return 0
  install_agent_tools
}

# ─── SO-specific tweaks ────────────────────────────────────
step_gnome() {
  should_run gnome || return 0
  log_section "GNOME / DE tweaks"

  case "$DOTFILES_DESKTOP_ENV" in
    gnome|*gnome*)
      # dconf: animaciones off, weekday, etc.
      gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
      gsettings set org.gnome.desktop.interface clock-show-weekday true 2>/dev/null || true
      gsettings set org.gnome.desktop.interface clock-show-seconds true 2>/dev/null || true
      gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
      gsettings set org.gnome.desktop.wm.preferences num-workspaces 6 2>/dev/null || true

      # Extensiones (si gnome-extensions CLI está disponible)
      if command -v gnome-extensions >/dev/null 2>&1; then
        log_info "extensiones: instalar vía extensions.gnome.org (no automático)"
      fi
      log_success "GNOME tweaks"
      ;;
    *)
      log_skip "GNOME tweaks (DE no es GNOME: $DOTFILES_DESKTOP_ENV)"
      ;;
  esac
}

step_macos() {
  should_run macos || return 0
  log_section "macOS tweaks"

  # Finder: mostrar archivos ocultos
  defaults write com.apple.finder AppleShowAllFiles -bool true
  # Mostrar extensiones
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  # Quitar auto-corrección (developer friendly)
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  # Quitar press-and-hold para keys repetidos
  defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
  # Screenshot a Downloads
  defaults write com.apple.screencapture location -string "$HOME/Downloads"
  # Trackpad tap-to-click
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  # Restart cfprefsd
  killall cfprefsd 2>/dev/null || true

  log_success "macOS tweaks"
}

# ─── Network ───────────────────────────────────────────────
step_network() {
  should_run network || return 0
  log_section "Network tuning"

  case "$DOTFILES_OS" in
    linux)
      # TCP BBR (ya en sysctl, pero verificamos)
      if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_warn "TCP BBR no está activo (módulo tcp_bbr falta?)"
      else
        log_success "TCP BBR activo"
      fi
      # Hostname: configurar si es genérico
      if [ "$DOTFILES_DRY_RUN" != "true" ] && ! command -v hostnamectl >/dev/null 2>&1; then
        log_debug "no hostnamectl"
      fi
      ;;
    macos)
      # macOS no permite cambiar congestion control
      log_info "macOS: TCP BBR no soportado (Apple usa su propio stack)"
      ;;
  esac
  log_success "network tuning"
}

# ─── Dotfiles link ─────────────────────────────────────────
step_dotfiles_link() {
  should_run dotfiles-link || return 0
  log_section "Linking dotfiles"

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] enlazaría dotfiles"
    return 0
  fi

  _link_config "$CONFIG_DIR/zsh/.zshrc"             "$HOME/.zshrc"
  _link_config "$CONFIG_DIR/tmux/.tmux.conf"         "$HOME/.tmux.conf"
  _link_config "$CONFIG_DIR/kitty/kitty.conf"        "$HOME/.config/kitty/kitty.conf"
  _link_config "$CONFIG_DIR/starship/starship.toml"  "$HOME/.config/starship.toml"
  _link_config "$CONFIG_DIR/git/.gitconfig"         "$HOME/.gitconfig"
  _link_config "$CONFIG_DIR/git/.gitignore_global"  "$HOME/.gitignore_global"

  # Copiar bin/ a ~/bin
  if [ -d "$BIN_DIR" ]; then
    mkdir -p "$HOME/bin"
    for f in "$BIN_DIR"/*; do
      [ -f "$f" ] || continue
      chmod +x "$f"
      ln -sf "$f" "$HOME/bin/$(basename "$f")"
    done
  fi

  log_success "dotfiles enlazados"
}

_link_config() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    log_debug "skip $dst (source $src no existe)"
    return 0
  fi
  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] ln -sf $src $dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] || [ -e "$dst" ]; then
    # Backup si difiere del target
    if [ ! -L "$dst" ] && ! cmp -s "$src" "$dst"; then
      cp -p "$dst" "$dst.dotfiles-backup" 2>/dev/null || true
    fi
    rm -f "$dst"
  fi
  ln -sf "$src" "$dst"
  log_success "linked: $dst"
}

# ─── Post-install verification ─────────────────────────────
step_post_install() {
  should_run post-install || return 0
  log_section "Post-install verification"

  local checks=(
    "git:git --version"
    "zsh:zsh --version"
    "tmux:tmux -V"
    "ripgrep:rg --version"
    "fd:fd --version"
    "bat:bat --version"
    "eza:eza --version"
    "fzf:fzf --version"
    "btop:btop --version"
    "neovim:nvim --version"
    "starship:starship --version"
    "kitty:kitty --version"
    "node:node --version"
    "npm:npm --version"
    "mise:mise --version"
    "uv:uv --version"
  )

  local pass=0
  local fail=0
  for c in "${checks[@]}"; do
    local name="${c%%:*}"
    local cmd="${c##*:}"
    if command -v "${cmd%% *}" >/dev/null 2>&1; then
      log_success "$name"
      pass=$((pass + 1))
    else
      log_warn "$name (no instalado)"
      fail=$((fail + 1))
    fi
  done

  echo
  log_info "verificación: $pass OK, $fail faltantes"
  log_info "log: $DOTFILES_LOG_FILE"
  log_info "backup: $DOTFILES_BACKUP_DIR"
}

# ─── Perfil auto-detect ────────────────────────────────────
detect_profile() {
  if [ "$DOTFILES_PROFILE" != "auto" ]; then
    return 0
  fi
  if [ "$DOTFILES_IS_LAPTOP" -eq 1 ]; then
    DOTFILES_PROFILE="laptop"
  elif [ "$DOTFILES_RAM_GB" -ge 64 ]; then
    DOTFILES_PROFILE="workstation"
  else
    DOTFILES_PROFILE="desktop"
  fi
  export DOTFILES_PROFILE
  log_info "perfil auto-detectado: $DOTFILES_PROFILE"
}

# ─── Main ──────────────────────────────────────────────────
main() {
  banner
  parse_args "$@"

  log_info "log: $DOTFILES_LOG_FILE"
  log_info "perfil: $DOTFILES_PROFILE"
  log_info "dry-run: $DOTFILES_DRY_RUN"

  detect_os
  detect_hardware
  detect_profile

  print_environment
  echo

  if [ "$DOTFILES_DRY_RUN" != "true" ] && [ "$DOTFILES_ASSUME_YES" != "true" ]; then
    confirm "¿continuar con la instalación?" "y" || exit 1
  fi

  # ── Pipeline ─────────────────────────────────────────
  step_preflight
  step_backup
  step_system_update
  step_core_packages
  step_shell
  step_terminal
  step_multiplexer
  step_dev_tools
  step_runtimes
  step_agent_tools

  # SO-specific
  case "$DOTFILES_OS" in
    linux)  step_gnome ;;
    macos)  step_macos ;;
  esac

  # Optimizaciones
  apply_sysctl_tuning
  apply_ssd_tuning
  apply_ram_tuning
  step_network

  step_dotfiles_link
  step_post_install

  log_section "Instalación completada"
  log_info "próximos pasos:"
  echo "  1. cierra sesión y vuelve a entrar (para que Zsh aplique)"
  echo "  2. abre Kitty desde tu launcher"
  echo "  3. tmux: prefix+I (Ctrl+a, I) para instalar plugins de TPM"
  echo "  4. claude (autentícate con tu API key)"
  echo "  5. lee docs/FAQ.md para más"
  echo
}

main "$@"
