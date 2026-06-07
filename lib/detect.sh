#!/usr/bin/env bash
# lib/detect.sh
# Detección de SO, hardware, entorno.
# Fuente única de verdad para variables de plataforma.

# ─── OS detection ───────────────────────────────────────────
DOTFILES_OS="unknown"
DOTFILES_OS_FAMILY="unknown"
DOTFILES_DISTRO="unknown"
DOTFILES_DISTRO_VERSION=""
DOTFILES_PKG_MANAGER="unknown"
DOTFILES_SHELL_DEFAULT=""
DOTFILES_INIT_SYSTEM=""
DOTFILES_DESKTOP_ENV=""

detect_os() {
  local kernel
  kernel="$(uname -s 2>/dev/null || echo Windows)"

  case "$kernel" in
    Linux)
      DOTFILES_OS="linux"
      DOTFILES_OS_FAMILY="linux"
      # Detectar distro
      if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DOTFILES_DISTRO="${ID:-unknown}"
        DOTFILES_DISTRO_VERSION="${VERSION_ID:-}"
      elif [ -f /etc/fedora-release ]; then
        DOTFILES_DISTRO="fedora"
      elif [ -f /etc/lsb-release ]; then
        # shellcheck disable=SC1091
        . /etc/lsb-release
        DOTFILES_DISTRO="${DISTRIB_ID:-ubuntu}"
        DOTFILES_DISTRO_VERSION="${DISTRIB_RELEASE:-}"
      fi
      DOTFILES_DISTRO="$(echo "$DOTFILES_DISTRO" | tr '[:upper:]' '[:lower:]')"

      # Init system
      if [ -d /run/systemd/system ]; then
        DOTFILES_INIT_SYSTEM="systemd"
      elif [ -f /sbin/openrc ]; then
        DOTFILES_INIT_SYSTEM="openrc"
      else
        DOTFILES_INIT_SYSTEM="unknown"
      fi

      # Package manager
      case "$DOTFILES_DISTRO" in
        fedora|rhel|centos|rocky|almalinux)
          if command -v dnf5 >/dev/null 2>&1; then
            DOTFILES_PKG_MANAGER="dnf5"
          else
            DOTFILES_PKG_MANAGER="dnf"
          fi
          ;;
        ubuntu|debian|pop|linuxmint|elementary)
          DOTFILES_PKG_MANAGER="apt"
          ;;
        arch|manjaro|endeavouros)
          DOTFILES_PKG_MANAGER="pacman"
          ;;
        opensuse*)
          DOTFILES_PKG_MANAGER="zypper"
          ;;
        alpine)
          DOTFILES_PKG_MANAGER="apk"
          ;;
        *)
          DOTFILES_PKG_MANAGER="unknown"
          ;;
      esac

      # Desktop env
      if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
        DOTFILES_DESKTOP_ENV="${XDG_CURRENT_DESKTOP,,}"
      elif [ -n "${DESKTOP_SESSION:-}" ]; then
        DOTFILES_DESKTOP_ENV="${DESKTOP_SESSION,,}"
      fi

      # Default shell
      DOTFILES_SHELL_DEFAULT="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || grep "^${USER}:" /etc/passwd 2>/dev/null | cut -d: -f7)"
      [ -z "$DOTFILES_SHELL_DEFAULT" ] && DOTFILES_SHELL_DEFAULT="$(basename "$SHELL")"
      DOTFILES_SHELL_DEFAULT="$(basename "$DOTFILES_SHELL_DEFAULT")"
      ;;

    Darwin)
      DOTFILES_OS="macos"
      DOTFILES_OS_FAMILY="unix"
      DOTFILES_DISTRO="macos"
      DOTFILES_DISTRO_VERSION="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
      DOTFILES_PKG_MANAGER="brew"
      DOTFILES_INIT_SYSTEM="launchd"
      DOTFILES_DESKTOP_ENV="aqua"
      DOTFILES_SHELL_DEFAULT="$(basename "$SHELL")"
      ;;

    FreeBSD)
      DOTFILES_OS="freebsd"
      DOTFILES_OS_FAMILY="bsd"
      DOTFILES_DISTRO="freebsd"
      DOTFILES_PKG_MANAGER="pkg"
      DOTFILES_SHELL_DEFAULT="$(basename "$SHELL")"
      ;;

    *)
      DOTFILES_OS="other"
      DOTFILES_OS_FAMILY="other"
      DOTFILES_PKG_MANAGER="unknown"
      DOTFILES_SHELL_DEFAULT="$(basename "$SHELL")"
      ;;
  esac

  export DOTFILES_OS DOTFILES_OS_FAMILY DOTFILES_DISTRO DOTFILES_DISTRO_VERSION
  export DOTFILES_PKG_MANAGER DOTFILES_INIT_SYSTEM DOTFILES_DESKTOP_ENV DOTFILES_SHELL_DEFAULT
}

# ─── Hardware detection ─────────────────────────────────────
DOTFILES_CPU_MODEL=""
DOTFILES_CPU_VENDOR=""
DOTFILES_CPU_CORES_PHYSICAL=0
DOTFILES_CPU_CORES_LOGICAL=0
DOTFILES_CPU_THREADS=0
DOTFILES_CPU_PROFILE="unknown"   # ryzen5 | ryzen9 | m2 | m4 | intel | other
DOTFILES_RAM_GB=0
DOTFILES_HAS_GPU_AMD=0
DOTFILES_HAS_GPU_NVIDIA=0
DOTFILES_HAS_GPU_APPLE=0
DOTFILES_IS_LAPTOP=0
DOTFILES_STORAGE_TYPE="hdd"      # ssd | nvme | hdd | apple_ssd | unknown
DOTFILES_SWAP_GB=0

detect_hardware() {
  detect_cpu
  detect_ram
  detect_gpu
  detect_form_factor
  detect_storage
  detect_swap
}

detect_cpu() {
  case "$DOTFILES_OS" in
    linux)
      if [ -r /proc/cpuinfo ]; then
        DOTFILES_CPU_MODEL="$(grep -m1 -E 'model name|Hardware' /proc/cpuinfo | sed -E 's/.*:[[:space:]]*//')"
        DOTFILES_CPU_VENDOR="$(grep -m1 -E 'vendor_id' /proc/cpuinfo | awk -F': ' '{print $2}')"
        DOTFILES_CPU_CORES_PHYSICAL="$(grep -c '^processor' /proc/cpuinfo)"
        DOTFILES_CPU_THREADS="$DOTFILES_CPU_CORES_PHYSICAL"
        # Hyperthreading
        local siblings cores
        siblings="$(grep -m1 'siblings' /proc/cpuinfo | awk -F': ' '{print $2}')"
        cores="$(grep -m1 'cpu cores' /proc/cpuinfo | awk -F': ' '{print $2}')"
        if [ -n "$siblings" ] && [ -n "$cores" ] && [ "$siblings" -gt 0 ]; then
          DOTFILES_CPU_CORES_LOGICAL="$((cores * (siblings / cores)))"
        else
          DOTFILES_CPU_CORES_LOGICAL="$DOTFILES_CPU_CORES_PHYSICAL"
        fi
      fi
      ;;

    macos)
      DOTFILES_CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
      DOTFILES_CPU_VENDOR="$(sysctl -n machdep.cpu.vendor 2>/dev/null)"
      DOTFILES_CPU_CORES_PHYSICAL="$(sysctl -n hw.physicalcpu 2>/dev/null)"
      DOTFILES_CPU_CORES_LOGICAL="$(sysctl -n hw.logicalcpu 2>/dev/null)"
      DOTFILES_CPU_THREADS="$DOTFILES_CPU_CORES_LOGICAL"
      ;;
  esac

  # Perfil por modelo
  local model_lc
  model_lc="$(echo "$DOTFILES_CPU_MODEL" | tr '[:upper:]' '[:lower:]')"
  case "$model_lc" in
    *ryzen*5*pro*)      DOTFILES_CPU_PROFILE="ryzen5" ;;
    *ryzen*5*)          DOTFILES_CPU_PROFILE="ryzen5" ;;
    *ryzen*9*)          DOTFILES_CPU_PROFILE="ryzen9" ;;
    *ryzen*7*)          DOTFILES_CPU_PROFILE="ryzen7" ;;
    *m2*|*apple*m2*)    DOTFILES_CPU_PROFILE="m2" ;;
    *m4*|*apple*m4*)    DOTFILES_CPU_PROFILE="m4" ;;
    *m1*|*apple*m1*)    DOTFILES_CPU_PROFILE="m1" ;;
    *core*|*intel*)     DOTFILES_CPU_PROFILE="intel" ;;
    *amd*)              DOTFILES_CPU_PROFILE="amd-other" ;;
    *)                  DOTFILES_CPU_PROFILE="other" ;;
  esac

  export DOTFILES_CPU_MODEL DOTFILES_CPU_VENDOR DOTFILES_CPU_CORES_PHYSICAL
  export DOTFILES_CPU_CORES_LOGICAL DOTFILES_CPU_THREADS DOTFILES_CPU_PROFILE
}

detect_ram() {
  local ram_kb
  case "$DOTFILES_OS" in
    linux)
      ram_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)"
      ;;
    macos)
      ram_kb="$(( $(sysctl -n hw.memsize 2>/dev/null) / 1024 ))"
      ;;
  esac
  if [ -n "$ram_kb" ] && [ "$ram_kb" -gt 0 ]; then
    DOTFILES_RAM_GB=$(( (ram_kb + 1024*1024 - 1) / (1024*1024) ))
  fi
  export DOTFILES_RAM_GB
}

detect_gpu() {
  case "$DOTFILES_OS" in
    linux)
      local lspci_out=""
      if command -v lspci >/dev/null 2>&1; then
        lspci_out="$(lspci 2>/dev/null)"
      fi
      if echo "$lspci_out" | grep -qi 'nvidia'; then
        DOTFILES_HAS_GPU_NVIDIA=1
      fi
      if echo "$lspci_out" | grep -qiE 'amd.*radeon|amd.*navi|amd.*vega'; then
        DOTFILES_HAS_GPU_AMD=1
      fi
      ;;
    macos)
      DOTFILES_HAS_GPU_APPLE=1
      ;;
  esac
  export DOTFILES_HAS_GPU_AMD DOTFILES_HAS_GPU_NVIDIA DOTFILES_HAS_GPU_APPLE
}

detect_form_factor() {
  case "$DOTFILES_OS" in
    linux)
      # Heurística: si existe batería, es laptop
      if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
        DOTFILES_IS_LAPTOP=1
      fi
      # O vía chassis
      if [ -r /sys/class/dmi/id/chassis_type ]; then
        local ct
        ct="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)"
        case "$ct" in
          8|9|10|11|14|30|31|32) DOTFILES_IS_LAPTOP=1 ;;
        esac
      fi
      ;;
    macos)
      # macOS no expone fácil. Asumimos macbook si modelo contiene MacBook
      local model
      model="$(sysctl -n hw.model 2>/dev/null)"
      if [[ "$model" == *MacBook* ]]; then
        DOTFILES_IS_LAPTOP=1
      fi
      ;;
  esac
  export DOTFILES_IS_LAPTOP
}

detect_storage() {
  case "$DOTFILES_OS" in
    linux)
      # NVMe
      if ls /sys/class/nvme/ 2>/dev/null | grep -q nvme; then
        DOTFILES_STORAGE_TYPE="nvme"
      elif lsblk -d -o rota 2>/dev/null | grep -q '^[[:space:]]*0'; then
        DOTFILES_STORAGE_TYPE="ssd"
      else
        DOTFILES_STORAGE_TYPE="hdd"
      fi
      ;;
    macos)
      DOTFILES_STORAGE_TYPE="apple_ssd"
      ;;
  esac
  export DOTFILES_STORAGE_TYPE
}

detect_swap() {
  case "$DOTFILES_OS" in
    linux)
      local total_kb=0
      while read -r size _; do
        total_kb=$((total_kb + size))
      done < <(awk '/^SwapTotal/ {print $2}' /proc/meminfo 2>/dev/null)
      DOTFILES_SWAP_GB=$(( (total_kb + 1024*1024 - 1) / (1024*1024) ))
      ;;
    macos)
      DOTFILES_SWAP_GB="$(sysctl -n vm.swapusage 2>/dev/null | awk -F'=' '{print $2}' | awk '{print $1}')"
      DOTFILES_SWAP_GB="${DOTFILES_SWAP_GB:-0}"
      ;;
  esac
  export DOTFILES_SWAP_GB
}

# ─── Helper: ¿es WSL? ───────────────────────────────────────
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSLENV:-}" ] || uname -r | grep -qi 'microsoft\|WSL'
}

# ─── Resumen imprimible ─────────────────────────────────────
print_environment() {
  cat <<EOF
┌─────────────────────────────────────────────────────┐
│  Detected Environment                                │
├─────────────────────────────────────────────────────┤
│  OS:        $DOTFILES_OS ($DOTFILES_DISTRO $DOTFILES_DISTRO_VERSION)
│  Family:    $DOTFILES_OS_FAMILY
│  PKG:       $DOTFILES_PKG_MANAGER
│  Init:      $DOTFILES_INIT_SYSTEM
│  DE:        $DOTFILES_DESKTOP_ENV
│  Shell:     $DOTFILES_SHELL_DEFAULT
├─────────────────────────────────────────────────────┤
│  CPU:       $DOTFILES_CPU_MODEL
│  Profile:   $DOTFILES_CPU_PROFILE
│  Cores:     $DOTFILES_CPU_CORES_PHYSICAL phys / $DOTFILES_CPU_THREADS threads
│  RAM:       ${DOTFILES_RAM_GB}GB
│  Swap:      ${DOTFILES_SWAP_GB}GB
│  Storage:   $DOTFILES_STORAGE_TYPE
│  Form:      $([ "$DOTFILES_IS_LAPTOP" -eq 1 ] && echo laptop || echo desktop)
│  GPU:       AMD=$DOTFILES_HAS_GPU_AMD NVIDIA=$DOTFILES_HAS_GPU_NVIDIA Apple=$DOTFILES_HAS_GPU_APPLE
└─────────────────────────────────────────────────────┘
EOF
}
