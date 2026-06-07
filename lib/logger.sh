#!/usr/bin/env bash
# lib/logger.sh — logging con colores, niveles, archivo de log

# Niveles: TRACE < DEBUG < INFO < WARN < ERROR < FATAL
_DOTFILES_LOG_LEVEL="${DOTFILES_LOG_LEVEL:-INFO}"
_DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"
_DOTFILES_NO_COLOR="${NO_COLOR:-${DOTFILES_NO_COLOR:-}}"
_DOTFILES_DRY_RUN="${DOTFILES_DRY_RUN:-false}"

# ANSI
if [ -t 1 ] && [ -z "$_DOTFILES_NO_COLOR" ]; then
  _RED='\033[0;31m'
  _GREEN='\033[0;32m'
  _YELLOW='\033[0;33m'
  _BLUE='\033[0;34m'
  _MAGENTA='\033[0;35m'
  _CYAN='\033[0;36m'
  _GRAY='\033[0;90m'
  _BOLD='\033[1m'
  _RESET='\033[0m'
else
  _RED='' _GREEN='' _YELLOW='' _BLUE='' _MAGENTA='' _CYAN='' _GRAY='' _BOLD='' _RESET=''
fi

_log_level_value() {
  case "$1" in
    TRACE) echo 0 ;;
    DEBUG) echo 1 ;;
    INFO)  echo 2 ;;
    WARN)  echo 3 ;;
    ERROR) echo 4 ;;
    FATAL) echo 5 ;;
    *) echo 2 ;;
  esac
}

_log() {
  local level="$1"; shift
  local msg="$*"
  local now ts lvl caller_line
  now="$(date +%H:%M:%S)"
  ts="$(date -Iseconds 2>/dev/null || date)"

  # Caller info
  caller_line="${BASH_LINENO[0]:-?}"

  # Filter by level
  local cur_val msg_val
  cur_val=$(_log_level_value "$_DOTFILES_LOG_LEVEL")
  msg_val=$(_log_level_value "$level")
  if [ "$msg_val" -lt "$cur_val" ]; then
    return 0
  fi

  local color
  case "$level" in
    TRACE) color="$_GRAY" ;;
    DEBUG) color="$_CYAN" ;;
    INFO)  color="$_BLUE" ;;
    WARN)  color="$_YELLOW" ;;
    ERROR) color="$_RED" ;;
    FATAL) color="$_RED$_BOLD" ;;
  esac

  # File output (sin colores)
  printf '[%s] %-5s %s\n' "$ts" "$level" "$msg" >> "$_DOTFILES_LOG_FILE"

  # TTY output (con colores)
  printf '%s%s%s %s[%s]%s %s\n' \
    "$color" "$level" "$_RESET" \
    "$_GRAY" "$now" "$_RESET" \
    "$msg"
}

log_trace() { _log TRACE "$@"; }
log_debug() { _log DEBUG "$@"; }
log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }
log_fatal() {
  _log FATAL "$@"
  exit 1
}

log_section() {
  local title="$*"
  printf '\n%s═══ %s ═══%s\n' "$_BOLD$_MAGENTA" "$title" "$_RESET"
  printf '\n' >> "$_DOTFILES_LOG_FILE"
  printf '═══ %s ═══\n' "$title" >> "$_DOTFILES_LOG_FILE"
}

log_success() {
  printf '  %s✓%s %s\n' "$_GREEN" "$_RESET" "$*"
  printf '  ✓ %s\n' "$*" >> "$_DOTFILES_LOG_FILE"
}

log_skip() {
  printf '  %s○%s %s (skipped)\n' "$_YELLOW" "$_RESET" "$*"
  printf '  ○ %s (skipped)\n' "$*" >> "$_DOTFILES_LOG_FILE"
}

# ── Wrapper de ejecución con soporte dry-run ──────────────
run() {
  if [ "$_DOTFILES_DRY_RUN" = "true" ]; then
    printf '  %s[dry-run]%s %s\n' "$_CYAN" "$_RESET" "$*"
    return 0
  fi
  "$@"
}

# ── sudo helper (no-op si ya eres root) ──────────────────
sudo_run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ── confirmación interactiva ─────────────────────────────
confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-y}"
  local response
  if [ "$_DOTFILES_DRY_RUN" = "true" ]; then
    printf '%s [dry-run: assuming yes]\n' "$prompt"
    return 0
  fi
  if [ "${DOTFILES_ASSUME_YES:-false}" = "true" ]; then
    return 0
  fi
  if [ "$default" = "y" ]; then
    prompt="$prompt [Y/n] "
  else
    prompt="$prompt [y/N] "
  fi
  printf '%s' "$prompt"
  read -r response
  case "$response" in
    [nN]*) return 1 ;;
    [yY]*) return 0 ;;
    "")    [ "$default" = "y" ] && return 0 || return 1 ;;
    *)     return 1 ;;
  esac
}
