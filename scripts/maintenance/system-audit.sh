#!/usr/bin/env bash
# ==============================================================================
# maintenance/system-audit.sh — Hardware & system diagnostics
#
# Description : Read-only audit that checks CPU thermals, RAM, storage (SMART),
#               battery health, PCI/USB devices, and active power services.
#               Issues a colour-coded report: OPTIMAL / WARNING / CRITICAL.
#               Sensor detection uses three layers:
#                 1. hwmon sysfs (preferred)
#                 2. lm_sensors text output (fallback)
#                 3. /sys/class/thermal thermal zones (last resort)
#
# OS support  : Linux only (requires /proc, /sys, sysfs)
#               This script is intentionally Linux-specific and
#               makes no attempt to be cross-platform.
#
# Dependencies: smartctl (smartmontools), sensors (lm_sensors),
#               lsblk, free, lscpu, lspci, lsusb — all optional;
#               degrades gracefully when absent.
#
# Usage       : ./system-audit.sh          (as regular user, some checks skipped)
#               sudo ./system-audit.sh     (full diagnostics including SMART)
# ==============================================================================

set -uo pipefail

IS_ROOT=0
[[ $EUID -eq 0 ]] && IS_ROOT=1

export LANG=C LC_ALL=C

# ── Utilities ────────────────────────────────────────────────────────────────
declare -a WARN_LIST=() CRIT_LIST=() INFO_LIST=()

has() { command -v "$1" &>/dev/null; }

warn() { WARN_LIST+=("$1"); }
crit() { CRIT_LIST+=("$1"); }

section() {
    printf '\n\033[1m>> %s\033[0m\n' "$1"
}

# Floating-point comparison: 0 = true (force arithmetic with +0)
fcmp() {
    local op=$3
    [[ $op == lt ]] && op='<'
    [[ $op == gt ]] && op='>'
    awk -v a="$1" -v b="$2" "BEGIN{exit !((a+0) $op (b+0))}"
}

# Extract first numeric value (with decimals) from a string
num() { echo "$1" | grep -oE '[0-9]+\.?[0-9]*' | head -n1; }

# eval_metric NAME VALUE THRESHOLD gt|lt [CRIT_THRESHOLD]
# Marks CRITICAL if CRIT_THRESHOLD exceeded, WARNING if THRESHOLD exceeded
eval_metric() {
    local name=$1 value=$2 thr=$3 cond=$4 crit_thr=${5:-}
    local v
    v=$(num "$value")
    if [[ -z $v ]]; then
        printf '  %-38s : UNKNOWN\n' "$name"
        return
    fi
    if [[ -n $crit_thr ]] && fcmp "$v" "$crit_thr" "$cond"; then
        printf '  %-38s : %s \033[31m[CRITICAL — threshold %s]\033[0m\n' "$name" "$value" "$crit_thr"
        crit "$name: $value (critical threshold $crit_thr)"
    elif fcmp "$v" "$thr" "$cond"; then
        printf '  %-38s : %s \033[33m[WARNING — threshold %s]\033[0m\n' "$name" "$value" "$thr"
        warn "$name: $value (threshold $thr)"
    else
        printf '  %-38s : %s [OPTIMAL]\n' "$name" "$value"
    fi
}

skip_root() { printf '  %-38s : SKIPPED (requires root)\n' "$1"; }

# ── Guard: Linux only ────────────────────────────────────────────────────────
OS=$(uname -s)
[[ $OS == Linux ]] || { echo "This script supports Linux only."; exit 1; }

# ── Optional dependency check ────────────────────────────────────────────────
MISSING=()
for dep in smartctl sensors lsblk free; do
    has "$dep" || MISSING+=("$dep")
done
if ((${#MISSING[@]})); then
    echo "[!] Missing tools: ${MISSING[*]}"
    echo "    Install: sudo dnf install smartmontools lm_sensors   (Fedora)"
    echo "             sudo apt-get install smartmontools lm-sensors (Debian/Ubuntu)"
fi
if has sensors && [[ $IS_ROOT -eq 1 ]]; then
    if [[ -x /usr/sbin/sensors-detect ]] && ! sensors 2>/dev/null | grep -q coretemp; then
        echo "[i] Running sensor module detection…"
        yes | /usr/sbin/sensors-detect --auto &>/dev/null || true
    fi
fi

echo "==================================================="
echo "  HARDWARE AUDIT & SYSTEM DIAGNOSTICS"
echo "  $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
echo "  Kernel $(uname -r)  |  root=$IS_ROOT"
echo "==================================================="

# ════════════════════════════════════════════════════════════════════════════
section "CPU & Thermals"

CPU_MODEL=$(lscpu | awk -F': *' '/Model name/{print $2}')
CORES=$(nproc)
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "n/a")
DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "n/a")
EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "n/a")
printf '  %-38s : %s\n' "CPU" "$CPU_MODEL"
printf '  %-38s : %s threads | governor=%s driver=%s epp=%s\n' "Topology/governor" "$CORES" "$GOVERNOR" "$DRIVER" "$EPP"

# CPU usage: 2-sample /proc/stat
read -r _ u1 n1 s1 i1 w1 irq1 sirq1 st1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 irq2 sirq2 st2 _ < /proc/stat
IDLE=$(( (i2 + w2) - (i1 + w1) ))
TOTAL=$(( (u2+n2+s2+i2+w2+irq2+sirq2+st2) - (u1+n1+s1+i1+w1+irq1+sirq1+st1) ))
CPU_PCT=$(awk -v i="$IDLE" -v t="$TOTAL" 'BEGIN{ if(t>0) printf "%.1f", 100*(t-i)/t; else print "0.0"}')
LOADAVG=$(cut -d' ' -f1-3 /proc/loadavg)
printf '  %-38s : %s%% (loadavg %s)\n' "CPU usage" "$CPU_PCT" "$LOADAVG"
if fcmp "$CPU_PCT" 85 ">"; then warn "CPU usage: ${CPU_PCT}% (>85%)"; fi

# ── Sensor Layer 1: hwmon sysfs ──────────────────────────────────────────────
PKG_TEMP="" PKG_CRIT="" NVME_TEMP="" NVME_CRIT="" MAXCORE_TEMP="" FAN_RPM="" AMBIENT="" SPD_MAX="" WIFI_TEMP=""
declare -A HWMON_SUMMARY=()

for hw in /sys/class/hwmon/hwmon*; do
    [[ -e $hw ]] || continue
    name=$(cat "$hw/name" 2>/dev/null || echo "?")
    case $name in
        coretemp)
            PKG_TEMP=$(awk '{printf "%.1f", $1/1000}' "$hw/temp1_input" 2>/dev/null)
            [[ -f $hw/temp1_crit ]] && PKG_CRIT=$(awk '{printf "%.0f", $1/1000}' "$hw/temp1_crit")
            maxcore=0
            for f in "$hw"/temp*_label; do
                [[ -f $f ]] || continue
                lbl=$(cat "$f")
                if [[ $lbl == Core* ]]; then
                    idx=$(basename "$f" | grep -oE '[0-9]+')
                    t=$(awk '{printf "%.0f", $1/1000}' "$hw/temp${idx}_input" 2>/dev/null || echo 0)
                    (( t > maxcore )) && maxcore=$t
                fi
            done
            MAXCORE_TEMP=$maxcore
            ;;
        nvme)
            NVME_TEMP=$(awk '{printf "%.1f", $1/1000}' "$hw/temp1_input" 2>/dev/null)
            [[ -f $hw/temp1_max ]] && NVME_CRIT=$(awk '{printf "%.0f", $1/1000}' "$hw/temp1_max")
            ;;
        dell_ddv|dell_smm)
            [[ -z $FAN_RPM && -f $hw/fan1_input ]] && FAN_RPM=$(cat "$hw/fan1_input")
            if [[ -z $AMBIENT ]]; then
                for f in "$hw"/temp*_label; do
                    [[ -f $f ]] || continue
                    [[ $(cat "$f") == Ambient ]] || continue
                    idx=$(basename "$f" | grep -oE '[0-9]+')
                    AMBIENT=$(awk '{printf "%.1f", $1/1000}' "$hw/temp${idx}_input" 2>/dev/null)
                done
            fi
            ;;
        spd5118)
            t=$(awk '{printf "%.0f", $1/1000}' "$hw/temp1_input" 2>/dev/null || echo 0)
            (( t > ${SPD_MAX:-0} )) && SPD_MAX=$t
            ;;
        iwlwifi*)
            WIFI_TEMP=$(awk '{printf "%.1f", $1/1000}' "$hw/temp1_input" 2>/dev/null)
            ;;
    esac
done

# ── Sensor Layer 2: lm_sensors fallback ──────────────────────────────────────
if [[ -z $PKG_TEMP ]] && has sensors; then
    PKG_TEMP=$(sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$3); print $3; exit}')
    [[ -z $PKG_TEMP ]] && PKG_TEMP=$(sensors 2>/dev/null | awk '/Tctl/{gsub(/[+°C]/,"",$2); print $2; exit}')
fi
# ── Sensor Layer 3: thermal zones ────────────────────────────────────────────
if [[ -z $PKG_TEMP ]]; then
    for z in /sys/class/thermal/thermal_zone*; do
        if [[ $(cat "$z/type" 2>/dev/null) == x86_pkg_temp ]]; then
            PKG_TEMP=$(awk '{printf "%.1f", $1/1000}' "$z/temp")
        fi
    done
fi

if [[ -n $PKG_TEMP ]]; then
    eval_metric "CPU Package Temp (°C)" "$PKG_TEMP" 75 gt "${PKG_CRIT:-90}"
else
    printf '  %-38s : NOT DETECTED\n' "CPU Package Temp (°C)"
    warn "No CPU temperature sensor detected"
fi
[[ -n $MAXCORE_TEMP ]] && printf '  %-38s : %s °C\n' "Hottest core" "$MAXCORE_TEMP"
if [[ -n $NVME_TEMP ]]; then
    eval_metric "NVMe Composite Temp (°C)" "$NVME_TEMP" 65 gt "${NVME_CRIT:-76}"
fi
[[ -n $AMBIENT ]] && printf '  %-38s : %s °C\n' "Chassis ambient" "$AMBIENT"
[[ -n ${SPD_MAX:-} && ${SPD_MAX} -gt 0 ]] && eval_metric "RAM SPD Temp (°C)" "$SPD_MAX" 55 gt 85
[[ -n ${WIFI_TEMP:-} ]] && printf '  %-38s : %s °C\n' "WiFi temp" "$WIFI_TEMP"

if [[ -n $FAN_RPM ]]; then
    printf '  %-38s : %s RPM\n' "CPU Fan" "$FAN_RPM"
    if [[ $FAN_RPM -eq 0 ]] && [[ -n $PKG_TEMP ]] && fcmp "$PKG_TEMP" 70 ">"; then
        crit "Fan at 0 RPM with hot CPU"
    fi
else
    printf '  %-38s : NOT DETECTED\n' "CPU Fan"
fi

if [[ $IS_ROOT -eq 1 ]] && has dmesg; then
    THERM_EVT=$(dmesg 2>/dev/null | grep -iE 'throttl|thermal trip|machine check|power limit' \
        | grep -cviE 'interrupt throttling rate|coalescing' || true)
    [[ ${THERM_EVT:-0} -gt 0 ]] && warn "${THERM_EVT} real throttling/MCE event(s) in dmesg"
fi

# ════════════════════════════════════════════════════════════════════════════
section "RAM"
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
AVAIL_RAM=$(free -m | awk '/^Mem:/{print $7}')
SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
RAM_PCT=$(awk -v f="$AVAIL_RAM" -v t="$TOTAL_RAM" 'BEGIN{printf "%.1f", f*100/t}')
printf '  %-38s : %s MB (%s MB available)\n' "Total RAM" "$TOTAL_RAM" "$AVAIL_RAM"
eval_metric "Available RAM (%)" "$RAM_PCT" 15 lt
if [[ $SWAP_TOTAL -gt 0 ]]; then
    SWAP_USED=$(free -m | awk '/^Swap:/{print $3}')
    printf '  %-38s : %s MB\n' "Swap in use (of ${SWAP_TOTAL} MB)" "$SWAP_USED"
fi
SWAPPINESS=$(cat /proc/sys/vm/swappiness)
printf '  %-38s : %s\n' "vm.swappiness" "$SWAPPINESS"
lsblk -dn -o NAME,SIZE | grep -q zram && printf '  %-38s : present\n' "zram"

# ════════════════════════════════════════════════════════════════════════════
section "Storage"
printf '  %-5s %-24s %-8s %-6s %s\n' "DEV" "MODEL" "SIZE" "TRAN" "SMART STATUS"
while read -r dev size tran; do
    [[ $dev == /dev/* ]] || continue
    model=$(lsblk -dno MODEL "$dev" 2>/dev/null)
    case $dev in */loop*|*/zram*) continue;; esac
    if [[ $IS_ROOT -eq 1 ]] && has smartctl; then
        case $dev in
            */nvme*)
                used=$(smartctl -A "$dev" 2>/dev/null | awk '/Percentage Used/{print $3}' | tr -d '%,')
                spare=$(smartctl -A "$dev" 2>/dev/null | awk '/Available Spare:/{print $3}')
                media=$(smartctl -A "$dev" 2>/dev/null | awk '/Media and Data Integrity Errors/{print $6}')
                health=$(smartctl -H "$dev" 2>/dev/null | awk '/test result/{print $NF}')
                state="${health:-N/A} used=${used:-?}% spare=${spare:-?}"
                [[ -n $media && $media != 0 ]] && state+=" [MEDIA ERRORS]" && crit "$dev: integrity errors"
                if [[ -n $used ]] && fcmp "$used" 50 ">"; then warn "$dev wear ${used}%"; fi
                [[ $health != PASSED && -n $health ]] && crit "$dev SMART: $health"
                ;;
            *)
                health=$(smartctl -H "$dev" 2>/dev/null | awk '/test result/{print $NF}')
                state="${health:-N/A}"
                [[ -n $health && $health != PASSED ]] && crit "$dev SMART: $health"
                ;;
        esac
    else
        state="SKIPPED (root required)"
    fi
    printf '  %-5s %-24s %-8s %-6s %s\n' "${dev#/dev/}" "${model:0:24}" "$size" "$tran" "$state"
done < <(lsblk -dnpo NAME,SIZE,TRAN 2>/dev/null)

if has df; then
    printf '\n'
    df -h --output=target,size,pcent,avail -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null | head -n 8 | sed 's/^/  /'
fi

# ════════════════════════════════════════════════════════════════════════════
section "Battery & Power"
BAT_PATH=""
for p in /sys/class/power_supply/BAT*; do [[ -d $p ]] && BAT_PATH=$p && break; done
if [[ -n $BAT_PATH ]]; then
    FULL=$(cat "$BAT_PATH/charge_full" 2>/dev/null || echo 0)
    DESIGN=$(cat "$BAT_PATH/charge_full_design" 2>/dev/null || echo 0)
    CYCLES=$(cat "$BAT_PATH/cycle_count" 2>/dev/null || echo 0)
    STATUS=$(cat "$BAT_PATH/status" 2>/dev/null)
    CAP_NOW=$(cat "$BAT_PATH/capacity" 2>/dev/null)
    BAT_VOLT=$(awk '{printf "%.2f", $1/1000000}' "$BAT_PATH/voltage_now" 2>/dev/null)
    if [[ $DESIGN -gt 0 ]]; then
        HEALTH=$(awk -v f="$FULL" -v d="$DESIGN" 'BEGIN{printf "%.1f", f*100/d}')
        eval_metric "Battery health (full/design %)" "$HEALTH" 80 lt 50
    fi
    printf '  %-38s : %s | charge %s%% | %s V | cycles %s\n' \
        "Status" "$STATUS" "${CAP_NOW:-?}" "${BAT_VOLT:-?}" "${CYCLES:-?}"
    START_TH=$(cat "$BAT_PATH/charge_control_start_threshold" 2>/dev/null)
    END_TH=$(cat "$BAT_PATH/charge_control_end_threshold" 2>/dev/null)
    [[ -n ${END_TH:-} ]] && printf '  %-38s : %s%% - %s%%\n' "Charge limit configured" "${START_TH:-n/a}" "$END_TH"
    for hw in /sys/class/hwmon/hwmon*; do
        if [[ $(cat "$hw/name" 2>/dev/null) == BAT0 && -f $hw/temp1_input ]]; then
            BAT_TEMP=$(awk '{printf "%.1f", $1/1000}' "$hw/temp1_input")
            eval_metric "Battery temp (°C)" "$BAT_TEMP" 40 gt 50
        fi
    done
else
    printf '  %-38s : NOT DETECTED\n' "Battery"
fi
AC_ONLINE=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo "?")
printf '  %-38s : %s\n' "AC power" "$([ "$AC_ONLINE" = 1 ] && echo connected || echo on-battery)"

# ════════════════════════════════════════════════════════════════════════════
section "Connected Devices (PCI/USB)"
if has lspci; then
    echo "  PCI (key devices):"
    lspci -k 2>/dev/null \
        | awk '/^[0-9a-f]/{dev=$0; drv=""} /Kernel driver in use/{drv=$NF} drv!=""{print "    " dev " -> " drv; drv=""}' \
        | grep -Ei 'vga|3d|network|ethernet|non-volatile|audio|bluetooth|sd host|card' | head -n 12
fi
if has lsusb; then
    USB_N=$(lsusb 2>/dev/null | grep -vc 'root hub' || true)
    echo "  USB (${USB_N} external devices):"
    lsusb 2>/dev/null | grep -v 'root hub' | sed 's/^Bus [0-9]* Device [0-9]*: /    /'
fi
if has iw && [[ $IS_ROOT -eq 1 ]]; then
    iw dev 2>/dev/null | awk '/Interface/{print "  WiFi: " $2}'
fi

# ════════════════════════════════════════════════════════════════════════════
section "Power Management Services"
for svc in thermald power-profiles-daemon tlp tuned; do
    if has systemctl && systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}"; then
        st=$(systemctl is-active "${svc}" 2>/dev/null || echo inactive)
        printf '  %-38s : %s\n' "${svc}" "${st}"
        [[ $svc == thermald && $st != active ]] && warn "thermald not active (recommended on Intel hybrid CPUs)"
    fi
done
if [[ $IS_ROOT -eq 1 ]] && has dmidecode; then
    printf '  %-38s : %s (%s)\n' "BIOS" \
        "$(dmidecode -s bios-version 2>/dev/null)" \
        "$(dmidecode -s bios-release-date 2>/dev/null)"
fi
if has fwupdmgr; then
    echo "  [i] Check firmware updates: fwupdmgr get-updates"
fi

# ════════════════════════════════════════════════════════════════════════════
section "Suggested Configuration Targets"
cat <<'EOF'
  [CPU]     Governor intel_pstate: 'powersave' + EPP 'balance_power' on battery,
            'balance_performance' on AC. Keep thermald active (Intel hybrid CPUs).
  [BATTERY] Charge limits 75-80% maximise cycle life; 50-90% gives more runtime.
            Avoid discharges <10% and temps >40 °C.
  [NVME]    Check APST is active: nvme get-feature /dev/nvme0n1 -f 0x0c.
            Mount with noatime; enable periodic TRIM: systemctl enable fstrim.timer
  [RAM]     vm.swappiness=10 (with zram present); check with 'sysctl vm.swappiness'.
  [SENSORS] If telemetry is missing: sensors-detect --auto; modprobe dell-smm-hwmon
            coretemp nvme-hwmon spd5118
EOF

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "==================================================="
if ((${#CRIT_LIST[@]} == 0)) && ((${#WARN_LIST[@]} == 0)); then
    echo "SUMMARY: All components are within safe operating thresholds."
else
    if ((${#CRIT_LIST[@]})); then
        echo "CRITICAL (${#CRIT_LIST[@]}):"
        printf '  - %s\n' "${CRIT_LIST[@]}"
    fi
    if ((${#WARN_LIST[@]})); then
        echo "WARNINGS (${#WARN_LIST[@]}):"
        printf '  - %s\n' "${WARN_LIST[@]}"
    fi
    echo "Priority: thermals (thermal paste/airflow) > disk health > battery."
fi
echo "==================================================="
((${#CRIT_LIST[@]} == 0)) || exit 2
