#!/usr/bin/env bash
# ==============================================================================
# maintenance/system-optimize.sh — System optimizer
#
# Description : Checks and optionally applies performance/power optimisations:
#               F1. Throttling forensics (dmesg analysis)
#               F2/F3. Dynamic energy profile via tuned + EPP (AC ↔ battery)
#               F4. vm.swappiness tuning
#               F5. NVMe APST power-saving state
#               F6. Battery health report (read-only)
#               F7. Post-apply re-audit via system-audit.sh (if present)
#
# OS support  : Linux only — specifically tuned for Fedora/RHEL with tuned,
#               systemd, and Dell/Intel hardware. Other distros may need
#               package-name adjustments (e.g., tuned, nvme-cli).
#               THIS SCRIPT IS LINUX/FEDORA-SPECIFIC BY DESIGN.
#
# Dependencies: tuned, tuned-adm, nvme-cli, udevadm, dmesg (root),
#               system-audit.sh (optional, same directory for F7)
#
# Usage       : sudo ./system-optimize.sh            → check mode (no changes)
#               sudo ./system-optimize.sh --apply    → apply module by module
#               sudo ./system-optimize.sh --apply --yes → apply all without prompts
#               sudo ./system-optimize.sh --revert   → restore last backup
# ==============================================================================

set -uo pipefail
export LANG=C LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BACKUP_BASE=/var/backups/sys-opt
RULE_FILE=/etc/udev/rules.d/99-power-profile.rules
SWITCH_SCRIPT=/usr/local/sbin/power-profile-switch.sh
SYSCTL_FILE=/etc/sysctl.d/99-optimize.conf
NVME_DEV=$(lsblk -dnp -o NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1 ~ /nvme/{print $1; exit}')
MARKER='managed-by-system-optimize.sh'

MODE=check
ASSUME_YES=0
for arg in "$@"; do
    case $arg in
        --check) MODE=check ;;
        --apply) MODE=apply ;;
        --yes|-y) ASSUME_YES=1 ;;
        --revert) MODE=revert ;;
        --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "This script requires root (sudo)."; exit 1
fi

BACKUP_DIR="${BACKUP_BASE}/$(date +%Y%m%d-%H%M%S)"
declare -a APPLIED=() SKIPPED=()

# ── Backup / apply helpers ────────────────────────────────────────────────────
backup_file() {
    local f=$1
    local dst="${BACKUP_DIR}${f}"
    mkdir -p "$(dirname "$dst")"
    if [[ -e $f ]]; then
        cp -a "$f" "$dst"
    else
        touch "${dst}.newfile"
    fi
}

confirm() {
    [[ $ASSUME_YES -eq 1 ]] && return 0
    read -r -p "    Apply: $1? [y/N] " ans
    [[ ${ans,,} =~ ^(y|yes)$ ]]
}

run_action() {
    local desc=$1; shift
    if [[ $MODE == check ]]; then
        printf '  [PENDING] %s\n      command: %s\n' "$desc" "$*"
        APPLIED+=("pending: $desc")
        return 0
    fi
    if confirm "$desc"; then
        if "$@"; then
            printf '  [APPLIED] %s\n' "$desc"
            APPLIED+=("$desc")
        else
            printf '  [ERROR] %s\n' "$desc"
            return 1
        fi
    else
        printf '  [SKIPPED] %s\n' "$desc"
        SKIPPED+=("$desc")
    fi
}

section() { printf '\n\033[1m>> %s\033[0m\n' "$1"; }
ok()      { printf '  [OK] %s\n' "$1"; SKIPPED+=("ok: $1"); }

# ── Revert mode ───────────────────────────────────────────────────────────────
if [[ $MODE == revert ]]; then
    LATEST=$(ls -1dt "${BACKUP_BASE}"/*/ 2>/dev/null | head -n1)
    if [[ -z $LATEST ]]; then echo "No backups found in ${BACKUP_BASE}"; exit 1; fi
    echo "Restoring from: $LATEST"
    find "$LATEST" -type f | while read -r f; do
        rel=${f#"$LATEST"}
        if [[ $f == *.newfile ]]; then
            rm -f "${f%.newfile}" && echo "  removed (was new): ${f%.newfile}"
        else
            mkdir -p "$(dirname "$rel")"
            cp -a "$f" "$rel" && echo "  restored: $rel"
        fi
    done
    echo "Reverted. Run 'sudo ./system-optimize.sh' to verify."
    exit 0
fi

echo "==================================================="
echo "  SYSTEM OPTIMIZER  (mode: $MODE)"
echo "  Backup: $BACKUP_DIR"
echo "==================================================="

# ════════════════════════════════════════════════════════════════════════════
section "F1. Throttling forensics (dmesg)"
REAL_TH=0 MCE_TH=0 BENIGN_TH=0
declare -a REAL_LINES=()
while IFS= read -r line; do
    [[ -z $line ]] && continue
    if echo "$line" | grep -qiE 'interrupt throttling rate|coalescing'; then
        (( BENIGN_TH++ )) || true
        continue
    fi
    if echo "$line" | grep -qiE 'mce|machine check'; then
        (( MCE_TH++ )) || true
    fi
    (( REAL_TH++ )) || true
    REAL_LINES+=("$line")
done < <(dmesg 2>/dev/null | grep -iE 'throttl|mce|machine check|thermal trip|power limit' || true)

if [[ $REAL_TH -eq 0 ]]; then
    if [[ $BENIGN_TH -gt 0 ]]; then
        ok "No real throttling ($BENIGN_TH benign event(s) discarded — e.g. NIC interrupt coalescing)"
    else
        ok "No throttling/MCE events in kernel ring buffer"
    fi
else
    echo "  $REAL_TH real event(s) found:"
    printf '%s\n' "${REAL_LINES[@]}" | tail -n 5 | sed 's/^/    /'
    if [[ $MCE_TH -gt 0 ]]; then
        echo "  [DIAG] Machine Check present: check 'mcelog --client' or install rasdaemon."
    elif printf '%s\n' "${REAL_LINES[@]}" | grep -qiE 'temperature|thermal|power limit'; then
        echo "  [DIAG] Thermal/power-limit throttling. If recurring (>10/day): clean dust,"
        echo "         check thermald ('systemctl status thermald') and thermal paste."
    else
        echo "  [DIAG] Unclassified throttling event; monitor over time."
    fi
    SKIPPED+=("forensics: $REAL_TH real events analysed")
fi

# ════════════════════════════════════════════════════════════════════════════
section "F2/F3. Dynamic energy profile (tuned + EPP)"
if ! systemctl is-active --quiet tuned; then
    echo "  [ERROR] tuned is not active; enable it first: systemctl enable --now tuned"
    exit 1
fi
if systemctl is-active --quiet power-profiles-daemon; then
    echo "  [NOTICE] power-profiles-daemon is active: may conflict with tuned."
fi

RULE_OK=0
if [[ -f $RULE_FILE ]] && grep -q "$MARKER" "$RULE_FILE"; then RULE_OK=1; fi
if [[ -f $SWITCH_SCRIPT ]] && grep -q "$MARKER" "$SWITCH_SCRIPT"; then :; else RULE_OK=0; fi

if [[ $RULE_OK -eq 1 ]]; then
    ok "Dynamic udev power-profile rule already installed"
else
    write_tuned_files() {
        backup_file "$SWITCH_SCRIPT"
        cat > "$SWITCH_SCRIPT" <<'EOS'
#!/usr/bin/env bash
# __MARKER__
if [[ $(cat /sys/class/power_supply/AC/online 2>/dev/null) == 1 ]]; then
    tuned-adm profile balanced        # AC: performance + EPP balance_performance
else
    tuned-adm profile powersave       # battery: power saving + EPP power
fi
EOS
        sed -i "s/__MARKER__/$MARKER/" "$SWITCH_SCRIPT"
        chmod 755 "$SWITCH_SCRIPT"
        backup_file "$RULE_FILE"
        cat > "$RULE_FILE" <<EOR
# $MARKER
ACTION=="change", KERNEL=="AC", SUBSYSTEM=="power_supply", RUN+="$SWITCH_SCRIPT"
EOR
        udevadm control --reload-rules
    }
    run_action "Install automatic tuned profile switch (AC→balanced, battery→powersave)" write_tuned_files
fi
CUR_PROFILE=$(tuned-adm active 2>/dev/null | awk -F': ' '{print $2}')
AC_NOW=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0)
EXPECTED=$([[ $AC_NOW == 1 ]] && echo balanced || echo powersave)
if [[ $CUR_PROFILE == "$EXPECTED" ]]; then
    ok "Current profile '${CUR_PROFILE}' matches power state"
else
    run_action "Set tuned profile to '${EXPECTED}' (AC state: ${AC_NOW})" tuned-adm profile "$EXPECTED"
fi

# ════════════════════════════════════════════════════════════════════════════
section "F4. RAM (vm.swappiness)"
SWAP_CUR=$(sysctl -n vm.swappiness)
if [[ $SWAP_CUR -le 10 ]]; then
    ok "vm.swappiness=${SWAP_CUR} already optimal"
else
    write_sysctl() {
        backup_file "$SYSCTL_FILE"
        if [[ -f $SYSCTL_FILE ]] && grep -q '^vm.swappiness' "$SYSCTL_FILE"; then
            sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' "$SYSCTL_FILE"
        else
            echo 'vm.swappiness=10' >> "$SYSCTL_FILE"
        fi
        sysctl -w vm.swappiness=10 > /dev/null
    }
    run_action "Set vm.swappiness=10 (current: ${SWAP_CUR})" write_sysctl
fi

# ════════════════════════════════════════════════════════════════════════════
section "F5. NVMe APST (SSD power saving)"
if [[ -n ${NVME_DEV:-} ]]; then
    APSTA=$(nvme id-ctrl "$NVME_DEV" 2>/dev/null | awk '/^apsta/{print $3}')
    if [[ ${APSTA:-0} == 0 ]]; then
        ok "Controller does not support APST; nothing to do"
    else
        APST_VAL=$(nvme get-feature "$NVME_DEV" -f apst -o json 2>/dev/null | grep -oE '"result"[^,}]*' | grep -oE '0x[0-9a-fA-F]+|[0-9]+' | head -n1)
        APST_ON=0
        [[ -n ${APST_VAL:-} ]] && (( APST_ON = APST_VAL & 1 ))
        if [[ $APST_ON -eq 1 ]]; then
            ok "APST already enabled on ${NVME_DEV}"
        else
            echo "  [INFO] APST supported but disabled. Saves ~0.5W at idle."
            run_action "Enable APST on ${NVME_DEV} (low risk, reversible via --revert)" \
                nvme set-feature "$NVME_DEV" -f apst --value=1
        fi
    fi
else
    echo "  [INFO] No NVMe device found."
fi

# ════════════════════════════════════════════════════════════════════════════
section "F6. Battery (read-only check)"
BAT=/sys/class/power_supply/BAT0
if [[ -d $BAT ]]; then
    FULL=$(cat "$BAT/charge_full" 2>/dev/null); DESIGN=$(cat "$BAT/charge_full_design" 2>/dev/null)
    HEALTH=$(awk -v f="${FULL:-0}" -v d="${DESIGN:-1}" 'BEGIN{printf "%.1f", f*100/d}')
    START=$(cat "$BAT/charge_control_start_threshold" 2>/dev/null || echo '?')
    END=$(cat "$BAT/charge_control_end_threshold" 2>/dev/null || echo '?')
    ok "Health ${HEALTH}% | charge limits kept: ${START}-${END}%"
else
    echo "  [INFO] No battery detected."
fi

# ════════════════════════════════════════════════════════════════════════════
section "F7. Post-apply re-audit"
AUDIT_SCRIPT="${SCRIPT_DIR}/system-audit.sh"
if [[ -f "${AUDIT_SCRIPT}" ]]; then
    if [[ $MODE == apply ]]; then
        bash "${AUDIT_SCRIPT}" | tail -n 12
    else
        echo "  (will run automatically after --apply)"
    fi
else
    echo "  [INFO] system-audit.sh not found alongside system-optimize.sh"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "==================================================="
if ((${#APPLIED[@]})); then
    printf 'Changes (%s):\n' "$MODE"
    printf '  - %s\n' "${APPLIED[@]}"
fi
if [[ $MODE == check ]]; then
    echo "Nothing modified. Run 'sudo ./system-optimize.sh --apply' to apply."
else
    echo "Backup saved to: ${BACKUP_DIR}  (restore: sudo ./system-optimize.sh --revert)"
fi
echo "==================================================="
