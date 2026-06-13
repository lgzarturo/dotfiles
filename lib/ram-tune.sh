#!/usr/bin/env bash
# lib/ram-tune.sh — ZRAM, swap, swappiness práctico
# - Configura zram-generator (systemd) para Linux moderno
# - Crea swapfile si RAM < 16GB
# - En macOS solo aplica a swap dinámico (no se toca)

apply_ram_tuning() {
  log_section "RAM & Swap Tuning"

  case "$DOTFILES_OS" in
    linux)
      _apply_zram_linux
      _apply_swapfile_linux
      ;;
    macos)
      _apply_swap_macos
      ;;
    *)
      log_skip "RAM tune (no aplica en $DOTFILES_OS)"
      ;;
  esac
}

_apply_zram_linux() {
  local zram_conf="/etc/systemd/zram-generator.conf"
  local zram_size="ram / 2"

  # Perfil: workstation = zram más agresivo
  case "${DOTFILES_PROFILE:-auto}" in
    workstation) zram_size="ram * 3 / 4" ;;
    laptop)      zram_size="ram / 3" ;;
    minimal)     zram_size="ram / 4" ;;
  esac

  # Si ya existe y está marcado, skip
  if [ -f "$zram_conf" ] && grep -q "dotfiles-agentic" "$zram_conf"; then
    log_debug "zram ya configurado"
    return 0
  fi

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] crearía $zram_conf con size=$zram_size"
    return 0
  fi

  log_info "configurando zram (size = $zram_size)"

  sudo_run mkdir -p /etc/systemd
  sudo_run tee "$zram_conf" >/dev/null <<EOF
# dotfiles-agentic — zram tuning
# Hardware: $DOTFILES_CPU_PROFILE / ${DOTFILES_RAM_GB}GB

[zram0]
zram-size = $zram_size
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

  sudo_run systemctl daemon-reload
  sudo_run systemctl start systemd-zram-setup@zram0 2>/dev/null || true
  log_success "zram configurado ($zram_size, zstd)"
}

_apply_swapfile_linux() {
  # Si la RAM es >= 32GB, no creamos swapfile (zram es suficiente)
  if [ "$DOTFILES_RAM_GB" -ge 32 ]; then
    log_info "RAM ${DOTFILES_RAM_GB}GB ≥ 32GB, no se crea swapfile"
    return 0
  fi

  # Si ya hay swapfile dotfiles, no duplicar
  if swapon --show=NAME 2>/dev/null | grep -q "dotfiles-swapfile"; then
    log_debug "swapfile ya existe"
    return 0
  fi

  # Tamaño: max(RAM/4, 4GB) para workstations
  local target_gb=4
  case "${DOTFILES_PROFILE:-auto}" in
    workstation) target_gb=8 ;;
    laptop)      target_gb=4 ;;
  esac
  if [ "$DOTFILES_RAM_GB" -lt 16 ] && [ "$target_gb" -lt 4 ]; then
    target_gb=4
  fi

  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] crearía swapfile de ${target_gb}GB"
    return 0
  fi

  local swapfile="/swap-dotfiles"
  if [ -f "$swapfile" ]; then
    log_warn "$swapfile ya existe, saltando"
    return 0
  fi

  log_info "creando swapfile de ${target_gb}GB en $swapfile"

  # Detectar si el sistema de archivos es Btrfs
  local swapfile_dir="$(dirname "$swapfile")"
  local fstype
  fstype=$(findmnt -no FSTYPE -T "$swapfile_dir" 2>/dev/null || df -T "$swapfile_dir" 2>/dev/null | awk 'NR==2 {print $2}')

  if [ "$fstype" = "btrfs" ]; then
    log_info "Btrfs detectado en $swapfile_dir, aplicando configuración específica de swapfile"
    if btrfs filesystem --help 2>&1 | grep -q "mkswapfile"; then
      sudo_run btrfs filesystem mkswapfile --size "${target_gb}g" "$swapfile"
    else
      # Creación manual No-COW para versiones antiguas de Btrfs
      sudo_run truncate -s 0 "$swapfile"
      sudo_run chattr +C "$swapfile"
      sudo_run btrfs property set "$swapfile" compression none 2>/dev/null || true
      if ! sudo_run fallocate -l "${target_gb}G" "$swapfile" 2>/dev/null; then
        sudo_run dd if=/dev/zero of="$swapfile" bs=1M count=$((target_gb * 1024)) status=none
      fi
      sudo_run chmod 600 "$swapfile"
      sudo_run mkswap "$swapfile" >/dev/null
    fi
  else
    # Creación estándar para otros sistemas de archivos (ext4, xfs, etc.)
    if ! sudo_run fallocate -l "${target_gb}G" "$swapfile" 2>/dev/null; then
      log_warn "fallocate falló, intentando con dd"
      sudo_run dd if=/dev/zero of="$swapfile" bs=1M count=$((target_gb * 1024)) status=none
    fi
    sudo_run chmod 600 "$swapfile"
    sudo_run mkswap "$swapfile" >/dev/null
  fi

  sudo_run swapon "$swapfile"

  # Persistente
  if ! grep -q "$swapfile" /etc/fstab; then
    echo "$swapfile none swap sw,pri=10 0 0" | sudo_run tee -a /etc/fstab >/dev/null
  fi
  log_success "swapfile ${target_gb}GB creado"
}

_apply_swap_macos() {
  # macOS maneja swap dinámicamente, no se debe tocar
  # Pero podemos verificar presión de memoria
  if [ "$DOTFILES_DRY_RUN" = "true" ]; then
    log_info "[dry-run] verificaría presión memoria macOS"
    return 0
  fi

  # Asegurar que swap dinámico está activo
  local dynamic
  dynamic="$(sysctl -n vm.swapusage 2>/dev/null || true)"
  log_info "macOS swap: ${dynamic:-no info}"
  log_debug "macOS no requiere tuning de swap manual"
}
