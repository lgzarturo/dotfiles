#!/usr/bin/env bash
# lib/sysctl-tune.sh — tuning de kernel
# Crea /etc/sysctl.d/99-dotfiles-agentic.conf de forma idempotente.

DOTFILES_SYSCTL_FILE="/etc/sysctl.d/99-dotfiles-agentic.conf"
DOTFILES_SYSCTL_MARKER="# managed by dotfiles-agentic"

apply_sysctl_tuning() {
  if [ "$DOTFILES_OS" != "linux" ]; then
    log_skip "sysctl tune (no aplica en $DOTFILES_OS)"
    return 0
  fi

  # Detección: si ya está aplicado, no-op
  if [ -f "$DOTFILES_SYSCTL_FILE" ] && grep -q "$DOTFILES_SYSCTL_MARKER" "$DOTFILES_SYSCTL_FILE"; then
    log_debug "sysctl tune: ya aplicado"
    return 0
  fi

  log_section "Sysctl Tuning"

  # Ajustes dinámicos según RAM y perfil
  local max_watches=524288
  local max_instances=8192
  local swappiness=10
  local vfs_cache_pressure=50

  case "$DOTFILES_RAM_GB" in
    0|1|2|3|4)
      swappiness=60
      vfs_cache_pressure=100
      ;;
    5|6|7|8)
      swappiness=30
      vfs_cache_pressure=80
      ;;
    9|10|11|12|13|14|15|16)
      swappiness=15
      vfs_cache_pressure=50
      ;;
    *)
      swappiness=10
      vfs_cache_pressure=50
      ;;
  esac

  # Perfil
  case "${DOTFILES_PROFILE:-auto}" in
    workstation)
      swappiness=5
      max_watches=1048576
      ;;
    laptop)
      swappiness=20
      ;;
    minimal)
      log_skip "sysctl tune (perfil minimal)"
      return 0
      ;;
  esac

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] escribiría $DOTFILES_SYSCTL_FILE"
    return 0
  fi

  sudo_run tee "$DOTFILES_SYSCTL_FILE" >/dev/null <<EOF
$DOTFILES_SYSCTL_MARKER
# Generado automáticamente por dotfiles-agentic
# Hardware: $DOTFILES_CPU_PROFILE / ${DOTFILES_RAM_GB}GB / $DOTFILES_STORAGE_TYPE

# ── File watchers (IDES, linters, agentes AI) ──
fs.inotify.max_user_watches = $max_watches
fs.inotify.max_user_instances = $max_instances

# ── Memoria virtual ──
vm.swappiness = $swappiness
vm.vfs_cache_pressure = $vfs_cache_pressure
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# ── Network: TCP BBR + fq qdisc (mejor para APIs IA) ──
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0

# ── Buffers y conexiones ──
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_tw_reuse = 1

# ── Seguridad (no rompe nada) ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ── Kernel ──
kernel.pid_max = 4194304
kernel.threads-max = 4194304
EOF

  sudo_run sysctl --system >/dev/null 2>&1
  log_success "sysctl tune aplicado a $DOTFILES_SYSCTL_FILE"
}
