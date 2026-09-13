#!/usr/bin/env bash
# tests/test-agent-aliases.sh — suite de tests funcionales para configure_agent_aliases
# Ejecutar: bash tests/test-agent-aliases.sh
# No modifica el entorno real del usuario (usa directorios temporales).
# Usa PATH aislado (/usr/bin:/bin + fake-bin) para evitar interferencia
# de herramientas instaladas globalmente (npm, cargo, etc.).

set -euo pipefail

# PATH mínimo para los tests: herramientas esenciales aisladas de agentes instalados
CLEAN_SYS_BIN="$(mktemp -d)"
cleanup_sys_bin() { rm -rf "$CLEAN_SYS_BIN"; }
trap cleanup_sys_bin EXIT

for _cmd in cat grep rm mkdir chmod sh bash touch mktemp awk mv printf echo sed; do
  _p="$(command -v "$_cmd" 2>/dev/null || true)"
  [ -n "$_p" ] && ln -s "$_p" "$CLEAN_SYS_BIN/$_cmd"
done
SYSTEM_PATH="$CLEAN_SYS_BIN"

# ─── Infraestructura de test ───────────────────────────────
PASS=0
FAIL=0
ERRORS=()

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf '  ✓ %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$desc")
    printf '  ✗ %s\n    expected: %s\n    actual:   %s\n' "$desc" "$expected" "$actual"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    printf '  ✓ %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$desc")
    printf '  ✗ %s\n    needle:   %s\n    not in:   %s\n' "$desc" "$needle" "$haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    printf '  ✓ %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$desc")
    printf '  ✗ %s\n    needle:   %s\n    found in: %s\n' "$desc" "$needle" "$haystack"
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then
    PASS=$((PASS + 1))
    printf '  ✓ %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$desc")
    printf '  ✗ %s\n    file exists: %s\n' "$desc" "$path"
  fi
}

# ─── Setup de entorno aislado ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Stubs de logging
log_section()  { :; }
log_info()     { :; }
log_debug()    { :; }
log_success()  { printf '    [OK] %s\n' "$*"; }
log_warn()     { printf '    [WARN] %s\n' "$*"; }
log_fatal()    { printf '    [FATAL] %s\n' "$*"; exit 1; }
log_skip()     { :; }

# Cargar la función bajo test (sin ejecutar nada)
# shellcheck source=../lib/agent-tools.sh
. "$LIB_DIR/agent-tools.sh"

# ─── Helpers ──────────────────────────────────────────────
# Crea un binario fake en un directorio temporal
make_fake_tool() {
  local tool="$1" fake_bin_dir="$2"
  printf '#!/usr/bin/env sh\necho "fake %s"\n' "$tool" > "$fake_bin_dir/$tool"
  chmod +x "$fake_bin_dir/$tool"
}

# Ejecuta configure_agent_aliases con PATH y HOME completamente aislados
run_aliases() {
  local tmp_home="$1" tmp_bin="$2" dry_run="${3:-false}" enable_unsafe="${4:-false}"
  PATH="$tmp_bin:$SYSTEM_PATH" HOME="$tmp_home" DOTFILES_DRY_RUN="$dry_run" \
    DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES="$enable_unsafe" \
    configure_agent_aliases >/dev/null 2>&1 || true
}

run_test() {
  local name="$1" fn="$2"
  local tmp_home tmp_bin
  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"

  printf '\n── %s ──\n' "$name"
  "$fn" "$tmp_home" "$tmp_bin"

  rm -rf "$tmp_home" "$tmp_bin"
}

# ─── Test 1: Dry-run — no crea ningún archivo ─────────────
test_dry_run_no_file() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "claude"   "$tmp_bin"
  make_fake_tool "opencode" "$tmp_bin"
  run_aliases "$tmp_home" "$tmp_bin" "true" "true"

  assert_file_not_exists \
    "dry-run no crea ~/.zshrc.local" \
    "$tmp_home/.zshrc.local"
}

# ─── Test 2: Por defecto no crea aliases inseguros ───────────
test_default_is_safe_no_aliases() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "claude" "$tmp_bin"
  run_aliases "$tmp_home" "$tmp_bin"

   assert_file_not_exists \
    "por defecto no crea ~/.zshrc.local con aliases inseguros" \
    "$tmp_home/.zshrc.local"
}

# ─── Test 3: Opt-in explícito → alias en .zshrc.local ────────
test_installed_tool_gets_alias() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "claude" "$tmp_bin"
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  local content
  content="$(cat "$tmp_home/.zshrc.local" 2>/dev/null || echo '')"

  assert_contains \
    "alias claude con flags de permisividad" \
    "alias claude='claude --allow-dangerously-skip-permissions'" \
    "$content"
}

# ─── Test 4: Herramienta NO instalada → NO aparece alias ──
test_absent_tool_no_alias() {
  local tmp_home="$1" tmp_bin="$2"
  # Solo claude en el PATH aislado
  make_fake_tool "claude" "$tmp_bin"
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  local content
  content="$(cat "$tmp_home/.zshrc.local" 2>/dev/null || echo '')"

  assert_not_contains \
    "herramienta ausente no genera alias (agy)" \
    "alias agy=" \
    "$content"

  assert_not_contains \
    "herramienta ausente no genera alias (codex)" \
    "alias codex=" \
    "$content"
}

# ─── Test 5: Idempotencia — bloque no se duplica ──────────
test_idempotent_no_duplicate() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "claude"   "$tmp_bin"
  make_fake_tool "opencode" "$tmp_bin"

  run_aliases "$tmp_home" "$tmp_bin" "false" "true"
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  local count
  count="$(grep -c 'DOTFILES:AGENT-ALIASES BEGIN' "$tmp_home/.zshrc.local" 2>/dev/null || echo 0)"
  assert_eq \
    "bloque centinela aparece exactamente 1 vez tras 2 ejecuciones" \
    "1" "$count"
}

# ─── Test 6: Idempotencia — alias count correcto ──────────
test_idempotent_alias_count() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "claude" "$tmp_bin"
  make_fake_tool "agy"    "$tmp_bin"

  run_aliases "$tmp_home" "$tmp_bin" "false" "true"
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  local alias_count
  alias_count="$(grep -c '^alias ' "$tmp_home/.zshrc.local" 2>/dev/null || echo 0)"
  assert_eq \
    "solo 2 líneas alias tras 3 ejecuciones (claude + agy)" \
    "2" "$alias_count"
}

# ─── Test 7: Sin herramientas — no se escribe archivo ─────
test_no_tools_no_file() {
  local tmp_home="$1" tmp_bin="$2"
  # tmp_bin vacío: ningún tool agentico instalado
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  assert_file_not_exists \
    "sin herramientas no se crea .zshrc.local" \
    "$tmp_home/.zshrc.local"
}

# ─── Test 8: Contenido previo en .zshrc.local se preserva ─
test_existing_content_preserved() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "claude" "$tmp_bin"

  printf 'export MY_VAR=foo\n# comentario usuario\n' > "$tmp_home/.zshrc.local"
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  local content
  content="$(cat "$tmp_home/.zshrc.local")"

  assert_contains \
    "contenido previo del usuario se preserva" \
    "export MY_VAR=foo" \
    "$content"
}

# ─── Test 9: Markers correctos en el archivo generado ─────
test_markers_present() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "codex" "$tmp_bin"
  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  local content
  content="$(cat "$tmp_home/.zshrc.local" 2>/dev/null || echo '')"

  assert_contains "marker BEGIN presente" \
    "# ─── DOTFILES:AGENT-ALIASES BEGIN ──" "$content"
  assert_contains "marker END presente" \
    "# ─── DOTFILES:AGENT-ALIASES END ────" "$content"
}

# ─── Test 10: Opt-in habilita aliases inseguros conocidos ───
test_yolo_agent_aliases() {
  local tmp_home="$1" tmp_bin="$2"
  make_fake_tool "agy"          "$tmp_bin"
  make_fake_tool "cursor"       "$tmp_bin"
  make_fake_tool "cursor-agent" "$tmp_bin"
  make_fake_tool "cline"        "$tmp_bin"
  make_fake_tool "opencode"     "$tmp_bin"

  run_aliases "$tmp_home" "$tmp_bin" "false" "true"

  local content
  content="$(cat "$tmp_home/.zshrc.local" 2>/dev/null || echo '')"

  assert_contains "alias agy con modo yolo/permisivo" \
    "alias agy='agy --dangerously-skip-permissions'" "$content"
  assert_contains "alias cline con auto-approve" \
    "alias cline='cline --auto-approve true'" "$content"
  assert_contains "alias cursor con agent yolo" \
    "alias cursor='cursor agent --yolo'" "$content"
  assert_contains "alias cursor-agent con yolo" \
    "alias cursor-agent='cursor-agent --yolo'" "$content"
  assert_contains "alias opencode con auto-approve" \
    "alias opencode='opencode --auto'" "$content"
}

# ─── Ejecutar todos los tests ─────────────────────────────
printf '\ntests/test-agent-aliases.sh\n'
printf '═%.0s' {1..40}
printf '\n'

run_test "Test 1: dry-run no crea archivo"               test_dry_run_no_file
run_test "Test 2: por defecto no crea aliases inseguros" test_default_is_safe_no_aliases
run_test "Test 3: opt-in explícito crea alias"           test_installed_tool_gets_alias
run_test "Test 4: herramienta ausente → sin alias"       test_absent_tool_no_alias
run_test "Test 5: idempotencia (sin duplicados)"         test_idempotent_no_duplicate
run_test "Test 6: idempotencia (alias count)"            test_idempotent_alias_count
run_test "Test 7: sin herramientas → sin archivo"        test_no_tools_no_file
run_test "Test 8: contenido previo preservado"           test_existing_content_preserved
run_test "Test 9: markers BEGIN/END presentes"           test_markers_present
run_test "Test 10: aliases inseguros requieren opt-in"   test_yolo_agent_aliases

printf '\n═%.0s' {1..40}
printf '\n'
printf 'Resultado: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  printf '\nFallaron:\n'
  for e in "${ERRORS[@]}"; do
    printf '  - %s\n' "$e"
  done
  exit 1
fi
exit 0
