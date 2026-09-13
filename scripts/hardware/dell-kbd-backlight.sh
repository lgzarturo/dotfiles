#!/usr/bin/env bash
# ==============================================================================
# hardware/dell-kbd-backlight.sh — Keep keyboard backlight always on
#
# Description : Configures Dell keyboard backlight timeout to "Never" via
#               the dell-wmi-sysman BIOS interface and the
#               /sys/class/leds/dell::kbd_backlight kernel LED driver.
#               Installs a systemd oneshot service so the setting persists
#               across reboots, suspend, and hibernate.
#
# OS support  : Linux only
#               HARDWARE-SPECIFIC: Dell laptops with WMI Sysman support
#               (tested on Dell Latitude 5431 / Dell WMI Sysman / dell-laptop)
#               Will silently degrade if dell-wmi-sysman is not present.
#
# Dependencies: systemd (systemctl), bash 4+
#               Kernel modules: dell-laptop, dell-wmi-sysman (loaded automatically
#               on supported hardware)
#
# Usage       : sudo ./dell-kbd-backlight.sh --apply   → configure + install service
#               ./dell-kbd-backlight.sh --status        → show current state
#               sudo ./dell-kbd-backlight.sh --revert   → restore defaults + remove service
#               ./dell-kbd-backlight.sh --help
# ==============================================================================

set -euo pipefail

# ── Dell sysfs paths ──────────────────────────────────────────────────────────
SYSMAN_DIR="/sys/class/firmware-attributes/dell-wmi-sysman/attributes"
KBD_LED_DIR="/sys/class/leds/dell::kbd_backlight"
SERVICE_NAME="dell-kbd-backlight.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
SCRIPT_INSTALL_PATH="/usr/local/sbin/dell-kbd-backlight.sh"

# ── Colours ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'; YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'; NC=$'\033[0m'
else
  GREEN=''; BLUE=''; YELLOW=''; RED=''; NC=''
fi

show_help() {
    cat <<EOF
Usage: sudo $0 [OPTION]

Options:
  --apply        Set keyboard timeout to "Never", max brightness,
                 and install the persistent systemd service.
  --status       Show current BIOS WMI and kernel LED state.
  --revert       Restore default timeout (10s) and remove the service.
  --help         Show this help message.

Without an option, shows current status.
EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Root privileges required."
        echo -e "Run: ${YELLOW}sudo $0 $1${NC}"
        exit 1
    fi
}

get_status() {
    echo -e "${BLUE}=== Dell Keyboard Backlight Status ===${NC}"

    # 1. Dell WMI Sysman (BIOS)
    if [[ -d "${SYSMAN_DIR}" ]]; then
        echo -e "\n${GREEN}[BIOS Dell WMI (dell-wmi-sysman)]${NC}"

        if [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value" ]]; then
            if [[ -r "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value" ]]; then
                local timeout_ac
                timeout_ac=$(cat "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value" 2>/dev/null || echo "N/A")
                echo -e "  - Timeout on AC                     : ${YELLOW}${timeout_ac}${NC}"
            else
                echo -e "  - Timeout on AC                     : ${YELLOW}(sudo required to read)${NC}"
            fi
        fi

        if [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value" ]]; then
            if [[ -r "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value" ]]; then
                local timeout_batt
                timeout_batt=$(cat "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value" 2>/dev/null || echo "N/A")
                echo -e "  - Timeout on Battery                : ${YELLOW}${timeout_batt}${NC}"
            else
                echo -e "  - Timeout on Battery                : ${YELLOW}(sudo required to read)${NC}"
            fi
        fi

        if [[ -f "${SYSMAN_DIR}/KeyboardIllumination/current_value" ]]; then
            if [[ -r "${SYSMAN_DIR}/KeyboardIllumination/current_value" ]]; then
                local illumination
                illumination=$(cat "${SYSMAN_DIR}/KeyboardIllumination/current_value" 2>/dev/null || echo "N/A")
                echo -e "  - BIOS illumination level           : ${YELLOW}${illumination}${NC}"
            else
                echo -e "  - BIOS illumination level           : ${YELLOW}(sudo required to read)${NC}"
            fi
        fi
    else
        echo -e "\n${YELLOW}[!] dell-wmi-sysman interface not found.${NC}"
    fi

    # 2. Kernel LED Sysfs
    if [[ -d "${KBD_LED_DIR}" ]]; then
        echo -e "\n${GREEN}[Kernel Driver (dell::kbd_backlight)]${NC}"
        local brightness max_brightness stop_timeout triggers
        brightness=$(cat "${KBD_LED_DIR}/brightness" 2>/dev/null || echo "N/A")
        max_brightness=$(cat "${KBD_LED_DIR}/max_brightness" 2>/dev/null || echo "N/A")
        stop_timeout=$(cat "${KBD_LED_DIR}/stop_timeout" 2>/dev/null || echo "N/A")
        triggers=$(cat "${KBD_LED_DIR}/start_triggers" 2>/dev/null || echo "N/A")

        echo -e "  - Brightness / Max                  : ${YELLOW}${brightness} / ${max_brightness}${NC}"
        echo -e "  - Off timeout (stop_timeout)        : ${YELLOW}${stop_timeout}${NC}"
        echo -e "  - Activation triggers               : ${YELLOW}${triggers}${NC}"
    else
        echo -e "\n${YELLOW}[!] /sys/class/leds/dell::kbd_backlight not found.${NC}"
    fi

    # 3. Systemd service
    echo -e "\n${GREEN}[Systemd Persistence Service]${NC}"
    if systemctl is-enabled "${SERVICE_NAME}" &>/dev/null; then
        local svc_status
        svc_status=$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || echo "inactive")
        echo -e "  - Service status                    : ${GREEN}Enabled (${svc_status})${NC}"
    else
        echo -e "  - Service status                    : ${YELLOW}Not installed / disabled${NC}"
    fi
    echo ""
}

apply_settings() {
    check_root "--apply"
    echo -e "${BLUE}>> Configuring keyboard backlight to always-on…${NC}"

    # 1. BIOS via WMI Sysman
    if [[ -d "${SYSMAN_DIR}" ]]; then
        echo -e "-> Setting BIOS timeouts to 'Never' via dell-wmi-sysman…"
        [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value" ]] \
            && echo "Never" > "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value"
        [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value" ]] \
            && echo "Never" > "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value"
        [[ -f "${SYSMAN_DIR}/KeyboardIllumination/current_value" ]] \
            && echo "Bright" > "${SYSMAN_DIR}/KeyboardIllumination/current_value"
    fi

    # 2. Kernel LED — set max brightness and disable stop_timeout
    if [[ -d "${KBD_LED_DIR}" ]]; then
        echo -e "-> Activating keyboard at maximum brightness…"
        local max_brightness
        max_brightness=$(cat "${KBD_LED_DIR}/max_brightness" 2>/dev/null || echo "2")
        echo "${max_brightness}" > "${KBD_LED_DIR}/brightness" 2>/dev/null || true
        [[ -f "${KBD_LED_DIR}/stop_timeout" ]] \
            && echo "0s" > "${KBD_LED_DIR}/stop_timeout" 2>/dev/null || true
    fi

    # 3. Install persistent script to /usr/local/sbin/
    echo -e "-> Installing script to ${SCRIPT_INSTALL_PATH}…"
    cp "$0" "${SCRIPT_INSTALL_PATH}"
    chmod 755 "${SCRIPT_INSTALL_PATH}"

    # 4. Create systemd service (runs on boot and after suspend/hibernate)
    echo -e "-> Creating systemd service (${SERVICE_PATH})…"
    cat <<EOF > "${SERVICE_PATH}"
[Unit]
Description=Dell Keyboard Backlight Always On
After=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
PartOf=sleep.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_INSTALL_PATH} --apply-silent
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}"

    echo -e "${GREEN}✓ Backlight configured permanently to 'Never' (always on).${NC}"
    echo -e "  Persists on AC, battery, and after suspend/hibernate."
}

apply_silent() {
    # Called silently by systemd — no stdout output
    if [[ -d "${SYSMAN_DIR}" ]]; then
        [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value" ]] \
            && echo "Never" > "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value" 2>/dev/null || true
        [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value" ]] \
            && echo "Never" > "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value" 2>/dev/null || true
        [[ -f "${SYSMAN_DIR}/KeyboardIllumination/current_value" ]] \
            && echo "Bright" > "${SYSMAN_DIR}/KeyboardIllumination/current_value" 2>/dev/null || true
    fi
    if [[ -d "${KBD_LED_DIR}" ]]; then
        local max_b
        max_b=$(cat "${KBD_LED_DIR}/max_brightness" 2>/dev/null || echo "2")
        echo "${max_b}" > "${KBD_LED_DIR}/brightness" 2>/dev/null || true
        [[ -f "${KBD_LED_DIR}/stop_timeout" ]] \
            && echo "0s" > "${KBD_LED_DIR}/stop_timeout" 2>/dev/null || true
    fi
}

revert_settings() {
    check_root "--revert"
    echo -e "${YELLOW}>> Restoring defaults (10s timeout)…${NC}"

    if [[ -d "${SYSMAN_DIR}" ]]; then
        [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value" ]] \
            && echo "10s" > "${SYSMAN_DIR}/KbdBacklightTimeoutAc/current_value"
        [[ -f "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value" ]] \
            && echo "10s" > "${SYSMAN_DIR}/KbdBacklightTimeoutBatt/current_value"
    fi

    if systemctl is-enabled "${SERVICE_NAME}" &>/dev/null; then
        echo -e "-> Disabling systemd service…"
        systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
        rm -f "${SERVICE_PATH}"
        systemctl daemon-reload
    fi

    rm -f "${SCRIPT_INSTALL_PATH}"
    echo -e "${GREEN}✓ Defaults restored (10s) and service removed.${NC}"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
case "${1:-}" in
    --apply)        apply_settings ;;
    --apply-silent) apply_silent ;;
    --status)       get_status ;;
    --revert)       revert_settings ;;
    --help|-h)      show_help ;;
    "")
        get_status
        echo -e "To enable permanent backlight, run:"
        echo -e "  ${YELLOW}sudo $0 --apply${NC}\n"
        ;;
    *)
        echo -e "${RED}[ERROR] Unknown option: $1${NC}"
        show_help
        exit 1
        ;;
esac
