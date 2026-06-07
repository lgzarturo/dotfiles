#!/usr/bin/env bash
# lib/agent-tools.sh — instalación de tooling agentico
# - Claude Code CLI
# - Ollama (opcional)
# - Open WebUI (opcional)
# - LangChain, LlamaIndex (opcional)

DOTFILES_AGENT_DIR="$HOME/agents"
DOTFILES_AGENT_BIN="$HOME/bin"

install_agent_tools() {
  log_section "Agent Tools (Claude Code, Ollama, etc.)"

  ensure_claude_code
  ensure_ollama
  ensure_agent_structure
}

ensure_claude_code() {
  if command -v claude >/dev/null 2>&1; then
    log_debug "claude CLI ya presente: $(claude --version 2>/dev/null || echo unknown)"
    return 0
  fi

  log_info "instalando Claude Code CLI"

  # Requiere Node.js. Si no está, lo instalamos via pkg.
  if ! command -v node >/dev/null 2>&1; then
    log_warn "Node.js no detectado — install node first via runtime step"
    return 1
  fi

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] npm install -g @anthropic-ai/claude-code"
    return 0
  fi

  npm install -g @anthropic-ai/claude-code
  log_success "Claude Code instalado"
}

ensure_ollama() {
  if [ "${DOTFILES_INSTALL_OLLAMA:-false}" != "true" ]; then
    log_debug "Ollama skip (DOTFILES_INSTALL_OLLAMA != true)"
    return 0
  fi

  if command -v ollama >/dev/null 2>&1; then
    log_debug "Ollama ya presente"
    return 0
  fi

  log_info "instalando Ollama"
  case "$DOTFILES_OS" in
    linux|macos)
      if [ "$DOTFILES_DRY_RUN" = "true" ]; then
        log_info "[dry-run] descargaría e instalaría Ollama"
        return 0
      fi
      local tmp
      tmp="$(mktemp)"
      if curl -fsSL https://ollama.com/install.sh -o "$tmp"; then
        sh "$tmp"
        rm -f "$tmp"
        log_success "Ollama instalado"
      else
        rm -f "$tmp"
        log_warn "falló descarga de Ollama"
        return 1
      fi
      ;;
    *)
      log_warn "Ollama no soportado en $DOTFILES_OS"
      ;;
  esac
}

ensure_agent_structure() {
  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] crearía estructura $DOTFILES_AGENT_DIR"
    return 0
  fi

  log_info "creando estructura agentic en $DOTFILES_AGENT_DIR"
  mkdir -p "$DOTFILES_AGENT_DIR"/{workspaces,scratch,memory,prompts,tools,templates}

  if [ ! -f "$DOTFILES_AGENT_DIR/README.md" ]; then
    cat > "$DOTFILES_AGENT_DIR/README.md" <<'EOF'
# ~/agents/

Estructura para trabajo con agentes de IA:

- `workspaces/` — proyectos donde trabaja el agente
- `scratch/` — experimentos descartables
- `memory/` — notas persistentes, decisiones
- `prompts/` — system prompts reutilizables
- `tools/` — scripts personalizados
- `templates/` — plantillas para nuevos proyectos
EOF
  fi

  mkdir -p "$DOTFILES_AGENT_BIN"
  log_success "estructura agentic creada"
}
