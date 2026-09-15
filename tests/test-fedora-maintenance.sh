#!/usr/bin/env bash
# Smoke tests: no necesitan Fedora ni red; usan --dry-run y os-release falso.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROGRAM="$ROOT/bin/fedora-maintenance"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
printf 'ID=fedora\nPRETTY_NAME="Fedora test"\n' > "$TMPDIR_TEST/os-release"
printf '%s\n' \
  'AUTO_REBOOT=true' \
  'UPDATE_FLATPAK=false' \
  'UPDATE_FIRMWARE=false' \
  'OFFLINE_UPDATE=false' \
  'ENABLE_SNAPSHOTS=false' \
  'LOG_RETENTION=9' \
  'INJECTION=$(touch /tmp/fedora-maintenance-injected)' \
  > "$TMPDIR_TEST/config"
printf '%s\n' '#!/usr/bin/env bash' 'exec sleep 5' > "$TMPDIR_TEST/slow-dnf"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$TMPDIR_TEST/reboot-dnf"
chmod 755 "$TMPDIR_TEST/slow-dnf"
chmod 755 "$TMPDIR_TEST/reboot-dnf"

pass=0
fail=0
check() {
  local name="$1"; shift
  if "$@"; then
    printf '  ✓ %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  ✗ %s\n' "$name" >&2
    fail=$((fail + 1))
  fi
}

check "sintaxis Bash" bash -n "$PROGRAM"
check "ayuda" bash -c '"$1" --help | grep -q -- "--interactive"' _ "$PROGRAM"
check "configuración segura y sin eval" bash -c '
  source "$1"
  CONFIG_PATH="$2"
  init_config
  parse_args --all
  [[ "$AUTO_REBOOT" == true && "$OFFLINE" == false && "$ENABLE_SNAPSHOTS" == false && "$LOG_RETENTION" == 9 ]]
  [[ "$RUN_UPDATE" == true && "$RUN_FLATPAK" == false && "$RUN_FIRMWARE" == false && "$RUN_CLEANUP" == true ]]
  [[ ! -e /tmp/fedora-maintenance-injected ]]
' _ "$PROGRAM" "$TMPDIR_TEST/config"
check "actualización no hace una consulta DNF silenciosa" bash -c '
  output="$(FM_LOG_FILE="$3/log" FEDORA_MAINTENANCE_OS_RELEASE="$2" "$1" --update --dry-run --yes --config "$4" 2>&1)"
  [[ "$output" =~ \[dry-run\].*dnf(5)?[[:space:]]upgrade ]]
  [[ "$output" != *"check-upgrade"* ]]
' _ "$PROGRAM" "$TMPDIR_TEST/os-release" "$TMPDIR_TEST" "$TMPDIR_TEST/config"
check "estado DNF tiene límite de tiempo" bash -c '
  source "$1"
  DNF_CMD="$2"
  STATUS_TIMEOUT=1
  rc=0
  output="$(dnf_cached_status 2>&1)" || rc=$?
  [[ "$rc" -eq 2 && "$output" == *"agotó el límite"* ]]
' _ "$PROGRAM" "$TMPDIR_TEST/slow-dnf"
check "snapshot Btrfs está integrado" bash -c '
  source "$1"
  DRY_RUN=true
  ENABLE_SNAPSHOTS=true
  FM_ROOT_FSTYPE=btrfs
  SNAPSHOT_DIR=/tmp/fm-snapshots-test
  command_exists() { return 0; }
  output="$(create_pre_update_snapshot 2>&1)"
  [[ "$output" == *"btrfs subvolume snapshot"* ]]
' _ "$PROGRAM"
check "detección de reinicio DNF" bash -c '
  source "$1"
  DNF_CMD="$2"
  REBOOT_REQUIRED=false
  detect_reboot_required
  [[ "$REBOOT_REQUIRED" == true ]]
' _ "$PROGRAM" "$TMPDIR_TEST/reboot-dnf"
check "instalación de timer dry-run" bash -c '
  FM_LOG_FILE="$3/log" FEDORA_MAINTENANCE_OS_RELEASE="$2" "$1" --install-timer --dry-run 2>&1 |
    grep -q "fedora-maintenance.timer"
' _ "$PROGRAM" "$TMPDIR_TEST/os-release" "$TMPDIR_TEST"
check "offline sin actualización falla" bash -c '
  ! FEDORA_MAINTENANCE_OS_RELEASE="$2" "$1" --offline --dry-run 2>/dev/null
' _ "$PROGRAM" "$TMPDIR_TEST/os-release"
check "opción desconocida falla" bash -c '
  ! FEDORA_MAINTENANCE_OS_RELEASE="$2" "$1" --inexistente 2>/dev/null
' _ "$PROGRAM" "$TMPDIR_TEST/os-release"

printf '\nResultado: %d OK, %d fallos\n' "$pass" "$fail"
(( fail == 0 ))
