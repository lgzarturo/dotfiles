#!/usr/bin/env bash
# ==============================================================================
# hardware/fix-howdy.sh — Activate Howdy face-unlock on KDE Plasma 6 lockscreen
#
# Description : Patches /etc/pam.d/kde to include pam_howdy.so as a sufficient
#               auth method, and ensures Howdy's config points to the persistent
#               IR camera device path (by-path symlink, not /dev/videoN index).
#
# OS support  : Linux only
#               DESKTOP-SPECIFIC: KDE Plasma 6 (requires /etc/pam.d/kde)
#               Tested on Fedora with Howdy installed via dnf/COPR.
#               Will not work on GNOME (different PAM file: /etc/pam.d/gdm-*).
#
# Dependencies: Howdy installed (pam_howdy.so, /etc/howdy/config.ini),
#               sudo (root required)
#
# Usage       : sudo ./fix-howdy.sh
#
# Post-install test:
#               /usr/libexec/kscreenlocker_greet --testing
#               or lock the session: Meta + L
# ==============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with root privileges." >&2
  echo "Usage: sudo $0" >&2
  exit 1
fi

KDE_PAM="/etc/pam.d/kde"
HOWDY_CONF="/etc/howdy/config.ini"
# Persistent by-path symlink for the IR camera — adjust this if your hardware differs.
# Find your device: ls -la /dev/v4l/by-path/ and identify the IR camera index.
IR_DEVICE_PATH="/dev/v4l/by-path/pci-0000:00:14.0-usb-0:6:1.2-video-index0"

echo "[+] 1. Checking PAM configuration for KDE Plasma 6…"

if [ ! -f "${KDE_PAM}" ]; then
  echo "Error: ${KDE_PAM} not found" >&2
  echo "Is KDE Plasma installed? Is this a KDE system?" >&2
  exit 1
fi

if grep -q "pam_howdy.so" "${KDE_PAM}"; then
  echo "  -> pam_howdy.so already configured in ${KDE_PAM}."
else
  echo "  -> Creating backup of ${KDE_PAM}…"
  cp "${KDE_PAM}" "${KDE_PAM}.bak.$(date +%Y%m%d%H%M%S)"

  echo "  -> Adding 'auth sufficient pam_howdy.so' at the top of ${KDE_PAM}…"
  sed -i '1s/^/auth        sufficient    pam_howdy.so\n/' "${KDE_PAM}"
  echo "  -> PAM configuration updated successfully."
fi

echo "[+] 2. Checking persistent IR camera path in Howdy config…"
if [ -f "${HOWDY_CONF}" ]; then
  if [ -e "${IR_DEVICE_PATH}" ]; then
    CURRENT_PATH=$(grep "^device_path" "${HOWDY_CONF}" | head -n1 | cut -d'=' -f2 | tr -d ' ')
    echo "  -> Current configured path: ${CURRENT_PATH}"
    if [ "${CURRENT_PATH}" != "${IR_DEVICE_PATH}" ]; then
      echo "  -> Updating 'device_path' to persistent by-path symlink…"
      sed -i "s|^device_path = .*|device_path = ${IR_DEVICE_PATH}|" "${HOWDY_CONF}"
      echo "  -> Path updated to: ${IR_DEVICE_PATH}"
    else
      echo "  -> Persistent by-path symlink already configured correctly."
    fi
  else
    echo "  -> WARNING: ${IR_DEVICE_PATH} does not exist on this system."
    echo "     Check 'ls -la /dev/v4l/by-path/' and update IR_DEVICE_PATH in this script."
  fi
else
  echo "  -> WARNING: ${HOWDY_CONF} not found. Is Howdy installed?"
  echo "     Install: sudo dnf install python3-howdy (Fedora COPR atim/howdy)"
fi

echo ""
echo "=== Verification complete ==="
echo "Test the lock screen by running:"
echo "  /usr/libexec/kscreenlocker_greet --testing"
echo "Or simply lock: Meta + L"
