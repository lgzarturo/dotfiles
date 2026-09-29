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
DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES="${DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES:-false}"
DOTFILES_BACKUP_DIR="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

# ─── Normaliza line endings (CRLF → LF) ────────────────────
# Necesario cuando el repo se checkout en Windows con core.autocrlf=true
# y los scripts se ejecutan desde WSL vía /mnt/c/... —
# bash falla con `$'\r': command not found` en cualquier línea con CRLF.
if command -v sed >/dev/null 2>&1; then
  for _f in "$LIB_DIR"/*.sh; do
    [ -f "$_f" ] && grep -q $'\r' "$_f" 2>/dev/null || continue
    _tmp="$(mktemp)" && tr -d '\r' < "$_f" > "$_tmp" && cat "$_tmp" > "$_f"
    rm -f "$_tmp"
  done
  unset _f _tmp
fi

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
# shellcheck source=lib/matrix-fetch.sh
. "$LIB_DIR/matrix-fetch.sh"
# shellcheck source=lib/change-shell.sh
. "$LIB_DIR/change-shell.sh"

# ─── Version ────────────────────────────────────────────────
DOTFILES_VERSION="unknown"
if [ -f "$SCRIPT_DIR/VERSION" ]; then
  DOTFILES_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
fi

# ─── Banner ────────────────────────────────────────────────
banner() {
  cat <<EOF

  ┌───────────────────────────────────────────────┐
  │  dotfiles v${DOTFILES_VERSION}                │
  │  entorno agentico portable                    │
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
  --enable-unsafe-agent-aliases  Habilita aliases inseguros de herramientas agenticas
  --log-level LVL     TRACE | DEBUG | INFO | WARN | ERROR
  --log-file PATH     Archivo de log
  --backup-dir PATH   Directorio de backup
  --help, -h          Esta ayuda

Pasos disponibles (en orden):
  preflight, system-update, core-packages, shell, terminal,
  multiplexer, dev-tools, runtimes, agent-tools, agent-aliases, matrix-fetch, gnome,
  sysctl, ssd, ram, network, git-config, dotfiles-link, change-shell, post-install

Variables de entorno equivalentes:
  DOTFILES_DRY_RUN, DOTFILES_ASSUME_YES, DOTFILES_PROFILE,
  DOTFILES_SKIP, DOTFILES_ONLY, DOTFILES_INSTALL_OLLAMA,
  DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES,
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
      --enable-unsafe-agent-aliases) DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES=true ;;
      --log-level)          DOTFILES_LOG_LEVEL="$2"; shift ;;
      --log-file)           DOTFILES_LOG_FILE="$2"; shift ;;
      --backup-dir)         DOTFILES_BACKUP_DIR="$2"; shift ;;
      --help|-h)            usage; exit 0 ;;
      *)                    log_error "opción desconocida: $1"; usage; exit 1 ;;
    esac
    shift
  done

  export DOTFILES_DRY_RUN DOTFILES_ASSUME_YES DOTFILES_PROFILE
  export DOTFILES_SKIP DOTFILES_ONLY DOTFILES_INSTALL_OLLAMA DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES
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

# ─── Step runner (lifecycle + tracking) ────────────────────
_STEP_NAMES=()
_STEP_STATES=()
_STEP_HINTS=()
_STEP_COUNT=0
_STEP_CURRENT=0

run_step() {
  local name="$1" description="$2" func="$3" critical="${4:-optional}"
  _STEP_CURRENT=$((_STEP_CURRENT + 1))
  _STEP_NAMES+=("$name")

  # Check if step should be skipped before running it
  if in_skip "$name"; then
    _STEP_STATES+=("skipped")
    _STEP_HINTS+=("")
    log_skip "$description"
    return 0
  fi
  if ! in_only "$name"; then
    _STEP_STATES+=("skipped")
    _STEP_HINTS+=("")
    log_skip "$description"
    return 0
  fi

  printf '\n%s[%d/21]%s %s\n' "$_BOLD" "$_STEP_CURRENT" "$_RESET" "$description"

  local start_time
  start_time=$(date +%s)
  local step_rc=0

  if "$func"; then
    step_rc=0
  else
    step_rc=$?
  fi

  local end_time elapsed elapsed_fmt
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  elapsed_fmt=$(printf '%dm %ds' $((elapsed / 60)) $((elapsed % 60)))

  if [ "$step_rc" -eq 0 ]; then
    _STEP_STATES+=("ok")
    _STEP_HINTS+=("")
    log_success "$description (${elapsed_fmt})"
  else
    if [ "$critical" = "critical" ]; then
      _STEP_STATES+=("fatal")
      log_error "$description FALLÓ (crítico)"
      log_hint "reintentar: ./setup.sh --only $name"
      log_hint "ver log: $DOTFILES_LOG_FILE"
      log_hint "ver soporte: docs/FAQ.md"
      exit 1
    else
      _STEP_STATES+=("failed")
      _STEP_HINTS+=("./setup.sh --only $name")
      log_warn "$description falló (no crítico) — continuando"
      log_hint "reintentar: ./setup.sh --only $name"
      log_hint "ver log: $DOTFILES_LOG_FILE"
      log_hint "ver soporte: docs/FAQ.md"
    fi
  fi
}

# ─── Pre-flight ────────────────────────────────────────────
step_preflight() {
  should_run preflight || return 0
  log_section "Pre-flight checks"

  # Privilegios
  if [ "$DOTFILES_OS" = "linux" ] && [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    log_fatal "linux sin root y sin sudo — abortando"
  fi
  if [ "$DOTFILES_OS" = "macos" ] && [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    log_warn "macOS sin sudo — trimforce y operaciones del sistema no disponibles"
  fi

  # Network
  if ! curl -sSf -m 5 https://github.com >/dev/null 2>&1; then
    log_warn "sin conectividad a GitHub — algunas instalaciones fallarán"
    if [ "$DOTFILES_DRY_RUN" != "true" ]; then
      confirm "continuar de todas formas?" "n" || exit 1
    fi
  fi

  # Disco mínimo
  local free_kb free_gb
  free_kb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
  free_gb=$((free_kb / 1024 / 1024))
  if [ -n "$free_kb" ] && [ "$free_gb" -lt 5 ]; then
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
      rel="${f#"$HOME"/}"
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
      sudo_run "$DOTFILES_PKG_MANAGER" upgrade -y || log_warn "upgrade parcial"
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
        unzip zip tar xz-utils
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
      if pkg_install starship; then
        log_success "Starship instalado"
      else
        log_warn "Starship no disponible vía $DOTFILES_PKG_MANAGER — instala manualmente desde la documentación oficial"
      fi
    fi
  fi

  # Zsh plugins via Zap
  if [ ! -d "$HOME/.local/share/zap" ]; then
    log_warn "Zap no se instala automáticamente por seguridad"
    log_hint "instálalo manualmente si quieres habilitar los plugins de zsh incluidos"
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
  curl -fsSL -o "$tmp/jbm.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip || log_warn "falló descarga de Nerd Font (puedes hacerlo manual)"
  if [ -f "$tmp/jbm.zip" ]; then
    if unzip -tq "$tmp/jbm.zip" >/dev/null 2>&1; then
      unzip -qo "$tmp/jbm.zip" -d "$font_dir" || log_warn "falló extracción de Nerd Font"
    else
      log_warn "Nerd Font zip corrupto"
    fi
  fi
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
  [ -d "$HOME/.tmux/plugins/tpm" ] || git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"

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
        fedora|rhel|centos|rocky|almalinux)
          pkg_install \
            ripgrep fd-find bat eza zoxide fzf btop duf dust \
            tldr neovim git-delta lazygit \
            jq yq --skip-unavailable
          # Copr útiles
          _enable_copr "alternateved/eza" || true
          ;;
        ubuntu|debian)
          sudo_run apt-get install -y --no-install-recommends \
            ripgrep fd-find bat fzf btop jq neovim
          # eza via cargo o .deb
          if ! command -v eza >/dev/null 2>&1; then
            sudo_run mkdir -p /etc/apt/keyrings
            local _tmpasc
            _tmpasc="$(mktemp)"
            curl -fsSL -o "$_tmpasc" https://raw.githubusercontent.com/eza-community/eza/main/deb.asc
            sudo_run gpg --dearmor -o /etc/apt/keyrings/gierens.gpg < "$_tmpasc"
            rm -f "$_tmpasc"
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
      if pkg_install mise; then
        log_success "mise instalado"
      else
        log_warn "mise no disponible vía $DOTFILES_PKG_MANAGER — instala manualmente desde la documentación oficial"
      fi
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
      if pkg_install uv; then
        log_success "uv instalado"
      else
        log_warn "uv no disponible vía $DOTFILES_PKG_MANAGER — instala manualmente desde la documentación oficial"
      fi
    fi
  fi

  log_success "runtimes"
}

# ─── Agent tools ───────────────────────────────────────────
step_agent_tools() {
  should_run agent-tools || return 0
  install_agent_tools
}

# ─── Agent aliases ─────────────────────────────────────────
step_agent_aliases() {
  should_run agent-aliases || return 0
  configure_agent_aliases
}

# ─── Matrix fetch ──────────────────────────────────────────
step_matrix_fetch() {
  should_run matrix-fetch || return 0
  configure_matrix_fetch
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

# ─── Git user config ───────────────────────────────────────
step_git_config() {
  should_run git-config || return 0
  log_section "Git user config"

  local tmpl="$CONFIG_DIR/git/.gitconfig"
  local PLACEHOLDER_NAME="Tu Nombre"
  local PLACEHOLDER_EMAIL="tu@email.com"

  if ! command -v git >/dev/null 2>&1; then
    log_warn "git no disponible — se saltará configuración de usuario"
    return 0
  fi

  if [ ! -f "$tmpl" ]; then
    log_warn "template $tmpl no encontrado — se saltará"
    return 0
  fi

  # Leer valores del template actual
  local tmpl_name tmpl_email
  tmpl_name="$(git config --file "$tmpl" user.name  2>/dev/null || echo "")"
  tmpl_email="$(git config --file "$tmpl" user.email 2>/dev/null || echo "")"

  # Leer valores del sistema (config global preexistente, puede ser el propio template si ya hay symlink)
  local sys_name sys_email
  sys_name="$(git config --global user.name  2>/dev/null || echo "")"
  sys_email="$(git config --global user.email 2>/dev/null || echo "")"

  # Determinar defaults: sistema > template, ignorando placeholders
  local default_name default_email
  default_name=""
  default_email=""
  if [ -n "$sys_name"  ] && [ "$sys_name"  != "$PLACEHOLDER_NAME"  ]; then
    default_name="$sys_name"
  elif [ -n "$tmpl_name" ] && [ "$tmpl_name" != "$PLACEHOLDER_NAME" ]; then
    default_name="$tmpl_name"
  fi
  if [ -n "$sys_email" ] && [ "$sys_email" != "$PLACEHOLDER_EMAIL" ]; then
    default_email="$sys_email"
  elif [ -n "$tmpl_email" ] && [ "$tmpl_email" != "$PLACEHOLDER_EMAIL" ]; then
    default_email="$tmpl_email"
  fi

  local git_name git_email
  git_name=""
  git_email=""

  if [ "$DOTFILES_ASSUME_YES" = "true" ]; then
    if [ -n "$default_name" ] && [ -n "$default_email" ]; then
      log_info "git user: $default_name <$default_email> (detectado, sin prompt)"
      git_name="$default_name"
      git_email="$default_email"
    else
      log_warn "git-config: --yes activo pero no hay valores válidos; configura git manualmente"
      return 0
    fi
  else
    if [ -n "$default_name" ]; then
      printf "  Git name  [%s]: " "$default_name"
    else
      printf "  Git name: "
    fi
    read -r git_name
    git_name="$(printf '%s' "$git_name" | xargs 2>/dev/null || printf '%s' "$git_name")"
    [ -z "$git_name" ] && git_name="$default_name"

    if [ -n "$default_email" ]; then
      printf "  Git email [%s]: " "$default_email"
    else
      printf "  Git email: "
    fi
    read -r git_email
    git_email="$(printf '%s' "$git_email" | xargs 2>/dev/null || printf '%s' "$git_email")"
    [ -z "$git_email" ] && git_email="$default_email"
  fi

  if [ -z "$git_name" ] || [ -z "$git_email" ]; then
    log_warn "git user config incompleto — edita $tmpl manualmente"
    return 0
  fi

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] git config user.name  = $git_name"
    log_info "[dry-run] git config user.email = $git_email"
    return 0
  fi

  git config --file "$tmpl" user.name  "$git_name"
  git config --file "$tmpl" user.email "$git_email"
  log_success "git user: $git_name <$git_email>"
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

# ─── ERR trap (failures outside run_step) ─────────────────
on_error() {
  local line="$1" cmd="$2"
  log_error "error inesperado en línea $line: $cmd"
  log_hint "ver log: $DOTFILES_LOG_FILE"
  log_hint "reintentar: ./setup.sh --only <paso>"
  log_hint "ver soporte: docs/FAQ.md"
  cleanup_sudo_keepalive
}
trap 'on_error ${LINENO} "$BASH_COMMAND"' ERR

# ─── Sudo keepalive ────────────────────────────────────────
_SUDO_KEEPALIVE_PID=""

sudo_keepalive() {
  [ "$DOTFILES_DRY_RUN" = "true" ] && return 0
  if [ -n "$DOTFILES_ONLY" ]; then
    case "$DOTFILES_ONLY" in
      agent-aliases|matrix-fetch|dotfiles-link|git-config) return 0 ;;
    esac
  fi
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo -v 2>/dev/null || true
    (while true; do sudo -n true 2>/dev/null; sleep 60; done) &
    _SUDO_KEEPALIVE_PID=$!
  fi
}

cleanup_sudo_keepalive() {
  if [ -n "$_SUDO_KEEPALIVE_PID" ] && kill -0 "$_SUDO_KEEPALIVE_PID" 2>/dev/null; then
    kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
}

# ─── Summary ──────────────────────────────────────────────
print_summary() {
  log_section "Resumen de instalación"
  printf '\n'
  printf '  %-25s %-10s\n' "PASO" "ESTADO"
  printf '  %-25s %-10s\n' "─────────────────────────" "──────────"
  local i
  local ok=0 failed_count=0
  for (( i=0; i < ${#_STEP_NAMES[@]}; i++ )); do
    local state_icon
    case "${_STEP_STATES[$i]}" in
      ok)      state_icon="${_GREEN}✓ OK${_RESET}";   ok=$((ok + 1)) ;;
      failed)  state_icon="${_YELLOW}✗ FALLO${_RESET}"; failed_count=$((failed_count + 1)) ;;
      fatal)   state_icon="${_RED}✗ FATAL${_RESET}";    failed_count=$((failed_count + 1)) ;;
      skipped) state_icon="${_YELLOW}○ SKIP${_RESET}" ;;
    esac
    printf '  %-25s ' "${_STEP_NAMES[$i]}"
    printf '%b\n' "$state_icon"
  done

  printf '\n'
  log_info "pasos completados: $ok"
  if [ "$failed_count" -gt 0 ]; then
    log_warn "pasos fallidos: $failed_count — ejecuta ./setup.sh --only <paso> para reintentar"
    for (( i=0; i < ${#_STEP_NAMES[@]}; i++ )); do
      if [ "${_STEP_STATES[$i]}" = "failed" ] || [ "${_STEP_STATES[$i]}" = "fatal" ]; then
        log_hint "reintentar: ./setup.sh --only ${_STEP_NAMES[$i]}"
      fi
    done
  fi
  log_info "log: $DOTFILES_LOG_FILE"
  log_info "backup: $DOTFILES_BACKUP_DIR"
}
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

  sudo_keepalive

  # ── Pipeline (con run_step para tracking) ───────────────
  run_step preflight "Pre-flight checks"                step_preflight              critical
  run_step backup    "Backup de configs existentes"     step_backup                 optional
  run_step system-update "System update"                step_system_update          optional
  run_step core-packages "Core packages"                step_core_packages          critical
  run_step shell     "Shell stack (Zsh, Starship, plugins)" step_shell              optional
  run_step terminal  "Terminal emulator"                step_terminal               optional
  run_step multiplexer "tmux + plugins"                 step_multiplexer            optional
  run_step dev-tools "Dev CLI tools"                    step_dev_tools              optional
  run_step runtimes  "Runtimes (mise)"                  step_runtimes               optional
  run_step agent-tools "Agent tools"                    step_agent_tools            optional
  run_step agent-aliases "Agent aliases"                step_agent_aliases          optional
  run_step matrix-fetch "Matrix fastfetch setup"        step_matrix_fetch           optional

  # SO-specific
  case "$DOTFILES_OS" in
    linux)  run_step gnome "GNOME / DE tweaks"                  step_gnome          optional ;;
    macos)  run_step macos  "macOS tweaks"                      step_macos          optional ;;
  esac

  # Optimizaciones
  step_sysctl_fn() { should_run sysctl || return 0; apply_sysctl_tuning; }
  step_ssd_fn()    { should_run ssd    || return 0; apply_ssd_tuning; }
  step_ram_fn()    { should_run ram    || return 0; apply_ram_tuning; }
  run_step sysctl "Sysctl tuning"                step_sysctl_fn    optional
  run_step ssd    "SSD optimization"             step_ssd_fn       optional
  run_step ram    "RAM & virtual memory"         step_ram_fn       optional
  run_step network "Network tuning"              step_network      optional

  run_step git-config "Git user config"          step_git_config   optional
  run_step dotfiles-link "Linking dotfiles"      step_dotfiles_link critical
  run_step change-shell "Change default shell"   step_change_shell  optional
  run_step post-install "Post-install verification" step_post_install optional

  cleanup_sudo_keepalive

  print_summary
}

main "$@"
