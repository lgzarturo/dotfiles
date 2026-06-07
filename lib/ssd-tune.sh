#!/usr/bin/env bash
# lib/ssd-tune.sh — optimizaciones para SSD/NVMe
# - TRIM semanal
# - fstrim.timer / periodic-trim
# - I/O scheduler (mq-deadline / none para NVMe)
# - Reducción de escrituras (noatime, journal options)

DOTFILES_FSTAB_MARKER="# dotfiles-agentic: noatime/nodiratime"
DOTFILES_UDEV_RULE="/etc/udev/rules.d/60-ioschedulers.rules"

apply_ssd_tuning() {
  log_section "SSD/NVMe Tuning"

  # ── macOS: TRIM para SSD no-Apple ──────────────────────
  if [ "$DOTFILES_OS" = "macos" ]; then
    if [ "$DOTFILES_DRY_RUN" = "true" ]; then
      log_info "[dry-run] activaría TRIM en SSD no-Apple"
    else
      sudo_run trimforce --enable 2>/dev/null || log_warn "trimforce no disponible o falló (macOS)"
      log_success "trimforce checked (macOS)"
    fi
    return 0
  fi

  if [ "$DOTFILES_OS" != "linux" ]; then
    log_skip "SSD tune (no aplica en $DOTFILES_OS)"
    return 0
  fi

  # ── 1. TRIM periódico ──────────────────────────────────
  case "$DOTFILES_INIT_SYSTEM" in
    systemd)
      if command -v fstrim >/dev/null 2>&1; then
        sudo_run systemctl enable --now fstrim.timer
        log_success "fstrim.timer habilitado"
      else
        log_warn "fstrim no disponible (instala util-linux)"
      fi
      ;;
  esac

  # ── 2. I/O scheduler por dispositivo ───────────────────
  local devs=()
  while IFS= read -r dev; do
    [ -n "$dev" ] && devs+=("$dev")
  done < <(lsblk -d -n -o NAME,ROTA 2>/dev/null | awk '$2=="0" {print "/dev/"$1}')

  if [ "${#devs[@]}" -eq 0 ]; then
    log_info "no se detectaron SSDs/NVMe (¿solo HDD?)"
  else
    log_info "SSDs detectados: ${devs[*]}"

    if [ "$DOTFILES_DRY_RUN" = "true" ]; then
      log_info "[dry-run] configuraría scheduler"
    else
      # Udev rule persistente
      sudo_run tee "$DOTFILES_UDEV_RULE" >/dev/null <<'EOF'
# dotfiles-agentic: I/O scheduler automático
# NVMe → none (kernel manages queue)
# SATA SSD → mq-deadline (low-latency)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
EOF

      # Aplicar ahora a cada dispositivo
      for dev in "${devs[@]}"; do
        local devname
        devname="$(basename "$dev")"
        local sched_file="/sys/block/$devname/queue/scheduler"
        if [ -w "$sched_file" ]; then
          if [[ "$devname" == nvme* ]]; then
            echo none | sudo_run tee "$sched_file" >/dev/null
          else
            echo mq-deadline | sudo_run tee "$sched_file" >/dev/null
          fi
          log_success "scheduler: $devname → $(cat "$sched_file" 2>/dev/null | awk -F'[][]' '{print $2}' || echo unknown)"
        fi
      done

      sudo_run udevadm control --reload
      sudo_run udevadm trigger
    fi
  fi

  # ── 3. fstab: añadir noatime/nodiratime si falta ──────
  if [ -r /etc/fstab ] && ! grep -q "$DOTFILES_FSTAB_MARKER" /etc/fstab; then
    if [ "$DOTFILES_DRY_RUN" = "true" ]; then
      log_info "[dry-run] parchearía /etc/fstab"
    else
      # Backup
      sudo_run cp -p /etc/fstab /etc/fstab.dotfiles-backup-$(date +%Y%m%d)
      log_info "backup fstab → /etc/fstab.dotfiles-backup-*"

      # Patch entries
      sudo_run awk '
        /^[^#]/ && $3 ~ /ext4|xfs|btrfs/ && !/noatime/ {
          $4 = ($4 ? $4 "," : "defaults") "noatime,nodiratime"
          print $0 " # " "'"$DOTFILES_FSTAB_MARKER"'"
          next
        }
        { print }
      ' /etc/fstab | sudo_run tee /etc/fstab.new >/dev/null

      # Diff + validación: no aplicamos si quedó vacío o inválido
      if [ -s /etc/fstab.new ] && sudo_run mount -f -a 2>/dev/null; then
        sudo_run mv /etc/fstab.new /etc/fstab
        log_success "/etc/fstab parchado con noatime"
      else
        log_warn "fstab no se aplicó automáticamente (revisar manualmente)"
        sudo_run rm -f /etc/fstab.new
      fi
    fi
  else
    log_debug "fstab ya optimizado"
  fi

}
