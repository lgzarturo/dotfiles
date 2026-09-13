#!/usr/bin/env bash
# ==============================================================================
# desktop/switch-dm.sh — Toggle between Display Managers
#
# Description : Utility to switch the systemd Display Manager between
#               KDE Plasma (plasmalogin) and COSMIC Desktop (cosmic-greeter)
#               by re-linking /etc/systemd/system/display-manager.service.
#
# OS support  : Linux only (systemd required)
#               Tested on Fedora 44 with KDE Plasma 6 and COSMIC Desktop.
#               Other systemd-based distros should work if the DM service
#               files are installed.
#
# Dependencies: systemd (systemctl), sudo (root required for set operations)
#
# Usage       : switch-dm status               → show current DM
#               sudo switch-dm kde             → switch to KDE Plasma
#               sudo switch-dm cosmic          → switch to COSMIC Desktop
#               switch-dm --help
# ==============================================================================

set -euo pipefail

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'
  YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; BLUE=''; YELLOW=''; CYAN=''; NC=''
fi

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    cat <<'HELP'
Usage: switch-dm [kde|cosmic|status]

Commands:
  kde        Set plasmalogin (KDE Plasma) as the default Display Manager.
  cosmic     Set cosmic-greeter (COSMIC Desktop) as the default Display Manager.
  status     Show the currently active and enabled Display Manager.
  -h, --help Show this help.

Examples:
  sudo switch-dm cosmic
  sudo switch-dm kde
  switch-dm status
HELP
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "This operation requires root privileges."
        echo "Run: sudo $0 $1"
        exit 1
    fi
}

get_current_dm() {
    local target
    if [[ -L /etc/systemd/system/display-manager.service ]]; then
        target=$(readlink -f /etc/systemd/system/display-manager.service)
        basename "${target}"
    else
        echo "none"
    fi
}

show_status() {
    local current
    current=$(get_current_dm)
    echo -e "${CYAN}====================================================${NC}"
    echo -e "         ${CYAN}CURRENT DISPLAY MANAGER STATUS${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "Symlink : ${BLUE}/etc/systemd/system/display-manager.service${NC} -> ${GREEN}${current}${NC}"

    if [[ "${current}" == *"plasmalogin"* ]]; then
        echo -e "Active  : ${GREEN}KDE Plasma (plasmalogin)${NC}"
    elif [[ "${current}" == *"cosmic-greeter"* ]]; then
        echo -e "Active  : ${GREEN}COSMIC Desktop (cosmic-greeter)${NC}"
    else
        echo -e "Active  : ${YELLOW}${current}${NC}"
    fi

    echo ""
    echo "Installed services:"
    for s in plasmalogin.service cosmic-greeter.service; do
        if systemctl list-unit-files "${s}" &>/dev/null; then
            local enabled_status
            enabled_status=$(systemctl is-enabled "${s}" 2>/dev/null || echo "disabled/not configured")
            echo -e " - ${s}: ${BLUE}${enabled_status}${NC}"
        else
            echo -e " - ${s}: ${YELLOW}not installed${NC}"
        fi
    done
    echo -e "${CYAN}====================================================${NC}"
}

set_dm() {
    local target_dm="$1"
    check_root "${target_dm}"

    case "${target_dm}" in
        kde|plasma|plasmalogin)
            log "Setting KDE Plasma (plasmalogin.service) as default Display Manager…"
            systemctl disable cosmic-greeter.service 2>/dev/null || true
            systemctl enable plasmalogin.service
            ok "KDE Plasma Login Manager enabled as the default Display Manager."
            warn "Change takes effect on next reboot or graphical restart."
            ;;
        cosmic|cosmic-greeter)
            if ! systemctl list-unit-files cosmic-greeter.service &>/dev/null; then
                err "cosmic-greeter.service is not installed."
                echo "Install COSMIC Desktop first, then re-run this script."
                exit 1
            fi
            log "Setting COSMIC Desktop (cosmic-greeter.service) as default Display Manager…"
            systemctl disable plasmalogin.service 2>/dev/null || true
            systemctl enable cosmic-greeter.service
            ok "COSMIC Greeter enabled as the default Display Manager."
            warn "Change takes effect on next reboot or graphical restart."
            ;;
        *)
            err "Invalid option: '${target_dm}'"
            show_help
            exit 1
            ;;
    esac
}

ACTION="${1:-status}"

case "${ACTION}" in
    status)
        show_status
        ;;
    kde|plasma|plasmalogin|cosmic|cosmic-greeter)
        set_dm "${ACTION}"
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        err "Unknown option: '${ACTION}'"
        show_help
        exit 1
        ;;
esac
