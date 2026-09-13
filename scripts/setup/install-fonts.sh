#!/usr/bin/env bash
# ==============================================================================
# setup/install-fonts.sh — Install programming & Nerd Fonts
#
# Description : Downloads and installs the following font families from GitHub:
#               Monaspace · Hack Nerd Font · FiraCode Nerd Font ·
#               Victor Mono · Cascadia Code · Iosevka
#               Propietarias (Skia, Gill Sans) are intentionally skipped.
#
# OS support  : Linux (any distro) · macOS
#               Uses ~/.local/share/fonts on Linux, ~/Library/Fonts on macOS.
#               fc-cache is only called on Linux (macOS refreshes automatically).
#
# Dependencies: wget or curl, unzip, fc-cache (Linux only)
#
# Usage       : ./install-fonts.sh
# ==============================================================================

set -euo pipefail

# ── Resolve dotfiles root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Source libraries ─────────────────────────────────────────────────────────
# shellcheck source=../../lib/detect.sh
source "${DOTFILES_ROOT}/lib/detect.sh"
# shellcheck source=../../lib/logger.sh
source "${DOTFILES_ROOT}/lib/logger.sh"

detect_os

# ── Font directory: Linux vs macOS ──────────────────────────────────────────
if [[ "${DOTFILES_OS}" == "macos" ]]; then
  FONT_DIR="${HOME}/Library/Fonts"
else
  FONT_DIR="${HOME}/.local/share/fonts"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${FONT_DIR}"
log_info "Font directory: ${FONT_DIR}"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Fetch JSON from GitHub releases API using wget or curl (whichever is available)
_fetch() {
  local url="$1"
  if command -v curl &>/dev/null; then
    curl -fsSL "${url}"
  elif command -v wget &>/dev/null; then
    wget -qO- "${url}"
  else
    log_fatal "Neither curl nor wget found. Install one of them first."
  fi
}

# Download a file to a target path
_download() {
  local url="$1" dest="$2"
  if command -v wget &>/dev/null; then
    wget -q --show-progress "${url}" -O "${dest}"
  else
    curl -L --progress-bar "${url}" -o "${dest}"
  fi
}

# Return the browser_download_url matching $pattern from a GitHub repo's latest release
get_latest_url() {
  local repo="$1"
  local pattern="$2"
  _fetch "https://api.github.com/repos/${repo}/releases/latest" \
    | grep "browser_download_url" \
    | grep -i "${pattern}" \
    | cut -d '"' -f 4 \
    | head -n 1
}

# Install a font from a zip URL. Skips gracefully if the font is already present.
install_font() {
  local font_name="$1"
  local url="$2"
  local zip_name="${3:-${font_name}}"

  if [[ -z "${url}" ]]; then
    log_warn "No download URL found for ${font_name} — skipping"
    return 1
  fi

  # Check whether the font is already installed (fc-list is Linux only)
  if [[ "${DOTFILES_OS}" != "macos" ]] && command -v fc-list &>/dev/null; then
    if fc-list | grep -qi "${font_name}"; then
      log_skip "${font_name} already installed"
      return 0
    fi
  elif [[ "${DOTFILES_OS}" == "macos" ]]; then
    # On macOS check the font directory directly
    if ls "${FONT_DIR}" 2>/dev/null | grep -qi "${font_name}"; then
      log_skip "${font_name} already installed"
      return 0
    fi
  fi

  log_info "Downloading ${font_name}…"
  _download "${url}" "${TMP_DIR}/${zip_name}.zip"

  log_info "Extracting ${font_name}…"
  mkdir -p "${TMP_DIR}/${zip_name}"
  unzip -q -o "${TMP_DIR}/${zip_name}.zip" -d "${TMP_DIR}/${zip_name}"

  log_info "Installing ${font_name}…"
  find "${TMP_DIR}/${zip_name}" -type f \( -name "*.ttf" -o -name "*.otf" \) \
    -exec cp {} "${FONT_DIR}/" \;

  log_success "${font_name} installed"
}

# ── Installation ─────────────────────────────────────────────────────────────
log_section "Font installation"

# 1. Monaspace
url_monaspace="$(get_latest_url "githubnext/monaspace" ".zip")"
install_font "Monaspace" "${url_monaspace}"

# 2. Hack Nerd Font
url_hack="$(get_latest_url "ryanoasis/nerd-fonts" "Hack.zip")"
install_font "Hack Nerd Font" "${url_hack}" "Hack"

# 3. Skia — proprietary (Apple/Microsoft), no public download
log_warn "Skia is proprietary — install manually if you have a license"

# 4. Gill Sans — proprietary
log_warn "Gill Sans is proprietary — install manually if you have a license"

# 5. FiraCode Nerd Font
url_firacode="$(get_latest_url "ryanoasis/nerd-fonts" "FiraCode.zip")"
install_font "FiraCode Nerd Font" "${url_firacode}" "FiraCode"

# 6. Victor Mono
url_victor="$(get_latest_url "rubjo/victor-mono" ".zip")"
install_font "Victor Mono" "${url_victor}"

# 7. Cascadia Code
url_cascadia="$(get_latest_url "microsoft/cascadia-code" ".zip")"
install_font "Cascadia Code" "${url_cascadia}"

# 8. Iosevka
url_iosevka="$(get_latest_url "be5invis/Iosevka" "PkgTTC-Iosevka-.*.zip")"
install_font "Iosevka" "${url_iosevka}"

# ── Refresh font cache (Linux only) ─────────────────────────────────────────
if [[ "${DOTFILES_OS}" == "linux" ]]; then
  if command -v fc-cache &>/dev/null; then
    log_info "Refreshing font cache…"
    fc-cache -fv > /dev/null
    log_success "Font cache updated"
  else
    log_warn "fc-cache not found — install fontconfig to refresh the cache"
  fi
else
  log_hint "macOS refreshes fonts automatically. No fc-cache needed."
fi

log_section "Done — fonts installed to ${FONT_DIR}"
