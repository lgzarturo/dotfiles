#!/usr/bin/env bash
# tests/test-matrix-fetch.sh — suite de tests funcionales para matrix-fetch
# Ejecutar: bash tests/test-matrix-fetch.sh
# No modifica el entorno real del usuario (usa directorios temporales).

set -euo pipefail

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

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ] || [ -L "$path" ]; then
    PASS=$((PASS + 1))
    printf '  ✓ %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$desc")
    printf '  ✗ %s\n    file does not exist: %s\n' "$desc" "$path"
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ] && [ ! -L "$path" ]; then
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
BIN_DIR="$SCRIPT_DIR/bin"

# Stubs de logging
log_section() { :; }
log_info()    { :; }
log_debug()   { :; }
log_success() { :; }
log_warn()    { :; }
log_fatal()   { printf '    [FATAL] %s\n' "$*"; exit 1; }
log_skip()    { :; }

# Cargar la función bajo test
# shellcheck source=../lib/matrix-fetch.sh
. "$LIB_DIR/matrix-fetch.sh"

run_test() {
  local name="$1" fn="$2"
  printf '\n── %s ──\n' "$name"
  local tmp_home
  tmp_home="$(mktemp -d)"
  export HOME="$tmp_home"
  export SCRIPT_DIR="$SCRIPT_DIR"

  "$fn" "$tmp_home"
  rm -rf "$tmp_home"
}

# ─── Test 1: dry-run no crea archivo ───────────────────────
test_dry_run_no_file() {
  local tmp_home="$1"
  DOTFILES_DRY_RUN=true configure_matrix_fetch "$tmp_home/.zshrc.local"

  assert_file_not_exists \
    "dry-run no crea ~/.zshrc.local" \
    "$tmp_home/.zshrc.local"
}

# ─── Test 2: markers BEGIN/END presentes ───────────────────
test_markers_present() {
  local tmp_home="$1"
  DOTFILES_DRY_RUN=false configure_matrix_fetch "$tmp_home/.zshrc.local"

  local content
  content="$(cat "$tmp_home/.zshrc.local")"

  assert_contains "marker BEGIN presente" \
    "# ─── DOTFILES:MATRIX-FETCH BEGIN ──" "$content"
  assert_contains "marker END presente" \
    "# ─── DOTFILES:MATRIX-FETCH END ────" "$content"
  assert_contains "alias fetch presente" \
    "alias fetch='matrix-fetch'" "$content"
}

# ─── Test 3: idempotencia (sin bloques duplicados) ────────
test_idempotent_no_duplicate() {
  local tmp_home="$1"
  DOTFILES_DRY_RUN=false configure_matrix_fetch "$tmp_home/.zshrc.local"
  DOTFILES_DRY_RUN=false configure_matrix_fetch "$tmp_home/.zshrc.local"
  DOTFILES_DRY_RUN=false configure_matrix_fetch "$tmp_home/.zshrc.local"

  local count
  count="$(grep -c 'DOTFILES:MATRIX-FETCH BEGIN' "$tmp_home/.zshrc.local" 2>/dev/null || echo 0)"
  assert_eq "bloque centinela aparece exactamente 1 vez tras 3 ejecuciones" "1" "$count"
}

# ─── Test 4: contenido previo preservado ──────────────────
test_existing_content_preserved() {
  local tmp_home="$1"
  printf 'export MY_TEST_VAR=custom_val\nalias mycmd="echo hi"\n' > "$tmp_home/.zshrc.local"
  DOTFILES_DRY_RUN=false configure_matrix_fetch "$tmp_home/.zshrc.local"

  local content
  content="$(cat "$tmp_home/.zshrc.local")"

  assert_contains "contenido previo variable preservado" \
    "export MY_TEST_VAR=custom_val" "$content"
  assert_contains "contenido previo alias preservado" \
    'alias mycmd="echo hi"' "$content"
  assert_contains "bloque matrix-fetch presente tras contenido previo" \
    "# ─── DOTFILES:MATRIX-FETCH BEGIN ──" "$content"
}

# ─── Test 5: symlink en ~/bin ─────────────────────────────
test_bin_symlink_created() {
  local tmp_home="$1"
  DOTFILES_DRY_RUN=false configure_matrix_fetch "$tmp_home/.zshrc.local"

  assert_file_exists "symlink ~/bin/matrix-fetch creado" "$tmp_home/bin/matrix-fetch"
}

# ─── Test 6: matrix-fetch salida y código de salida 0 ──────
test_matrix_fetch_runs() {
  local tmp_home="$1"
  local output rc=0
  output="$("$BIN_DIR/matrix-fetch" --no-color 2>&1)" || rc=$?

  assert_eq "matrix-fetch exit code 0" "0" "$rc"
  assert_contains "contiene sección HOST" "HOST" "$output"
  assert_contains "contiene sección OS" "OS" "$output"
  assert_contains "contiene sección CPU" "CPU" "$output"
  assert_contains "contiene sección RAM" "RAM" "$output"
  assert_contains "contiene sección DISK" "DISK" "$output"
  assert_contains "contiene sección FOLDER" "FOLDER" "$output"
  assert_contains "contiene sección GIT" "GIT" "$output"
}

# ─── Test 7: matrix-fetch --short ─────────────────────────
test_matrix_fetch_short() {
  local tmp_home="$1"
  local output rc=0
  output="$("$BIN_DIR/matrix-fetch" --short --no-color 2>&1)" || rc=$?

  assert_eq "matrix-fetch --short exit code 0" "0" "$rc"
  assert_contains "short mode contiene [MATRIX]" "[MATRIX]" "$output"
  assert_contains "short mode contiene RAM" "RAM" "$output"
}

# ─── Test 8: matrix-fetch --compact ───────────────────────
test_matrix_fetch_compact() {
  local tmp_home="$1"
  local output rc=0
  output="$("$BIN_DIR/matrix-fetch" --compact --no-color 2>&1)" || rc=$?

  assert_eq "matrix-fetch --compact exit code 0" "0" "$rc"
  assert_contains "compact mode contiene HUD header" "MATRIX // SYS HUD" "$output"
}

# ─── Test 9: detección de git vs non-git ──────────────────
test_matrix_fetch_git_detection() {
  local tmp_home="$1"
  # En tmp_home (no git)
  local out_nongit
  out_nongit="$(cd "$tmp_home" && "$BIN_DIR/matrix-fetch" --no-color 2>&1)"
  assert_contains "directorio no-git muestra 'GIT     :: none'" "GIT     :: none" "$out_nongit"

  # En repo git fake
  mkdir -p "$tmp_home/repo"
  (
    cd "$tmp_home/repo"
    git init -q -b test-branch 2>/dev/null || (git init -q && git checkout -q -b test-branch)
  )
  local out_git
  out_git="$(cd "$tmp_home/repo" && "$BIN_DIR/matrix-fetch" --no-color 2>&1)"
  assert_contains "directorio git detecta rama test-branch" "test-branch" "$out_git"
}

# ─── Ejecutar tests ───────────────────────────────────────
printf '\ntests/test-matrix-fetch.sh\n'
printf '═%.0s' {1..40}
printf '\n'

run_test "Test 1: dry-run no crea archivo" test_dry_run_no_file
run_test "Test 2: markers BEGIN/END presentes" test_markers_present
run_test "Test 3: idempotencia (sin duplicados)" test_idempotent_no_duplicate
run_test "Test 4: contenido previo preservado" test_existing_content_preserved
run_test "Test 5: symlink en ~/bin" test_bin_symlink_created
run_test "Test 6: ejecucion matrix-fetch y campos" test_matrix_fetch_runs
run_test "Test 7: matrix-fetch --short" test_matrix_fetch_short
run_test "Test 8: matrix-fetch --compact" test_matrix_fetch_compact
run_test "Test 9: deteccion git vs no-git" test_matrix_fetch_git_detection

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
