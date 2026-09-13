#!/usr/bin/env bash
#
# scripts/maintenance/repo-security-check.sh — auditoría básica del repositorio

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "Error: ripgrep (rg) es requerido para ejecutar esta auditoría." >&2
  exit 1
fi

failures=0

run_check() {
  local label="$1" pattern="$2"
  shift 2

  local output
  output="$(rg --hidden --no-ignore -n "$pattern" "$@" 2>/dev/null || true)"
  if [[ -n "$output" ]]; then
    failures=$((failures + 1))
    printf '\n[FAIL] %s\n%s\n' "$label" "$output"
  else
    printf '[OK] %s\n' "$label"
  fi
}

SECRET_PATTERN='ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----|aws_access_key_id|aws_secret_access_key|SECRET_ACCESS_KEY|JWT_SECRET='
PERSONAL_PATH_PATTERN='/home/[A-Za-z0-9._-]+/\.dotfiles|/Users/[A-Za-z0-9._-]+/\.dotfiles|[A-Za-z]:\\\\Users\\\\[^\\\\]+\\\\'
REMOTE_EXEC_PATTERN='curl[^|\n]*\|\s*(sh|bash)|wget[^|\n]*\|\s*(sh|bash)|irm\s+[^|]+\|\s*iex|Invoke-WebRequest[^\n]*install\.ps1|https?://[^[:space:]'"'"'"]+/install\.(sh|ps1)|https?://mise\.run/?'

printf 'repo-security-check\n'
printf '═%.0s' {1..40}
printf '\n'

run_check \
  "secretos o credenciales hardcodeadas" \
  "$SECRET_PATTERN" \
  --glob '!**/.git/**' \
  --glob '!**/tests/**' \
  --glob '!**/scripts/maintenance/repo-security-check.sh' \
  "$REPO_ROOT"

run_check \
  "rutas personales absolutas hardcodeadas" \
  "$PERSONAL_PATH_PATTERN" \
  --glob '!**/.git/**' \
  --glob '!**/scripts/maintenance/repo-security-check.sh' \
  "$REPO_ROOT"

run_check \
  "patrones de descarga remota ejecutable en scripts" \
  "$REMOTE_EXEC_PATTERN" \
  --glob '!**/tests/**' \
  --glob '!**/SECURITY.md' \
  --glob '!**/README.md' \
  --glob '!**/CHANGELOG.md' \
  --glob '!**/docs/**' \
  --glob '!**/scripts/maintenance/repo-security-check.sh' \
  "$REPO_ROOT/setup.sh" \
  "$REPO_ROOT/setup.ps1" \
  "$REPO_ROOT/lib" \
  "$REPO_ROOT/bin" \
  "$REPO_ROOT/scripts" \
  "$REPO_ROOT/config"

printf '\n'
if [[ "$failures" -gt 0 ]]; then
  printf 'Resultado: %d hallazgo(s)\n' "$failures"
  exit 1
fi

printf 'Resultado: sin hallazgos\n'
