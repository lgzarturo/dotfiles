#!/usr/bin/env bash
# lib/matrix-fetch.sh
# Configura matrix-fetch (fastfetch estilo Matrix) en ~/.zshrc.local.
# Idempotente: usa bloques centinela para no duplicar entradas.

configure_matrix_fetch() {
  log_section "Matrix fastfetch (~/.zshrc.local)"

  local zshrc_local="${1:-$HOME/.zshrc.local}"
  local repo_bin="${SCRIPT_DIR:-$HOME/.dotfiles}/bin/matrix-fetch"
  local marker_begin="# ─── DOTFILES:MATRIX-FETCH BEGIN ──"
  local marker_end="# ─── DOTFILES:MATRIX-FETCH END ────"

  # Asegurar permisos y symlink de matrix-fetch a ~/bin
  if [ -f "$repo_bin" ]; then
    chmod +x "$repo_bin"
    if [ "${DOTFILES_DRY_RUN:-false}" = "true" ]; then
      log_info "[dry-run] ln -sf $repo_bin $HOME/bin/matrix-fetch"
    else
      mkdir -p "$HOME/bin"
      ln -sf "$repo_bin" "$HOME/bin/matrix-fetch"
      log_debug "linked: $HOME/bin/matrix-fetch -> $repo_bin"
    fi
  fi

  local fetch_block
  fetch_block="$(cat << 'EOF'
# Fastfetch estilo Matrix para inicio de terminal
# Gestionado por dotfiles — no editar manualmente

# Asegurar ~/bin en PATH
[[ ":$PATH:" != *":$HOME/bin:"* ]] && export PATH="$HOME/bin:$PATH"

# Alias para invocar manualmente
alias fetch='matrix-fetch'

# Ejecutar al iniciar ventana de terminal interactiva
if [[ -o interactive ]] && [ -t 1 ] && [ -z "${VIMRUNTIME:-}" ] && [ -z "${MC_SID:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  if command -v matrix-fetch >/dev/null 2>&1; then
    matrix-fetch
  elif [ -x "$HOME/bin/matrix-fetch" ]; then
    "$HOME/bin/matrix-fetch"
  fi
fi
EOF
)"

  if [ "${DOTFILES_DRY_RUN:-false}" = "true" ]; then
    log_info "[dry-run] configuraría matrix-fetch en $zshrc_local"
    return 0
  fi

  # Crear ~/.zshrc.local si no existe
  mkdir -p "$(dirname "$zshrc_local")"
  touch "$zshrc_local"

  # Eliminar bloque anterior (idempotencia) mediante awk portable
  if grep -qF "$marker_begin" "$zshrc_local" 2>/dev/null; then
    local _tmp
    _tmp="$(mktemp)"
    awk '
      /# ─── DOTFILES:MATRIX-FETCH BEGIN/ { skip=1; next }
      /# ─── DOTFILES:MATRIX-FETCH END/   { skip=0; next }
      !skip
    ' "$zshrc_local" > "$_tmp" && mv "$_tmp" "$zshrc_local"
  fi

  # Escribir bloque nuevo al final del archivo
  {
    printf '\n%s\n' "$marker_begin"
    printf '%s\n' "$fetch_block"
    printf '%s\n' "$marker_end"
  } >> "$zshrc_local"

  log_success "matrix-fetch configurado en $zshrc_local"
}
