#!/usr/bin/env bash
# lib/change-shell.sh — cambiar shell por defecto a Zsh

step_change_shell() {
  should_run change-shell || return 0
  log_section "Change default shell to Zsh"

  local zsh_path
  zsh_path="$(command -v zsh 2>/dev/null)"

  if [ -z "$zsh_path" ]; then
    log_warn "zsh no encontrado — no se puede cambiar shell"
    return 0
  fi

  local current_shell
  current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"

  if [ "$current_shell" = "$zsh_path" ]; then
    log_success "zsh ya es el shell por defecto"
    return 0
  fi

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] chsh -s $zsh_path"
    return 0
  fi

  log_info "cambiando shell por defecto a zsh"
  sudo_run chsh -s "$zsh_path" "$USER"
  log_success "shell cambiado a $zsh_path"
  log_info "cierra sesión y vuelve a entrar para aplicar el cambio"
}
