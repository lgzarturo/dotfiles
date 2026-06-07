# FAQ

## ¿Es seguro correr setup.sh en mi sistema?

Sí, con caveats:

- Hace **backup automático** de configs modificadas
- Cada archivo generado lleva un marcador `# dotfiles` para identificación
- `--dry-run` permite ver qué haría sin ejecutar
- **Nunca** toca: `/boot`, kernel, BIOS, particiones, formateo
- **Sí** modifica: paquetes del sistema, configs en `/etc/`, configs de usuario

Comandos potencialmente destructivos:

- `dnf5 upgrade -y` → actualiza paquetes
- `dd` solo se usa como fallback si `fallocate` falla
- `killall cfprefsd` en macOS es inofensivo (es daemon de preferences)

## ¿Cómo desinstalo?

Los archivos con marcador dotfiles:

```bash
# Linux
sudo rm -f /etc/sysctl.d/99-dotfiles-agentic.conf
sudo rm -f /etc/systemd/zram-generator.conf
sudo rm -f /etc/udev/rules.d/60-ioschedulers.rules
sudo sed -i '/dotfiles-agentic: noatime/d' /etc/fstab
sudo sysctl --system

# Restaurar fstab desde backup
sudo cp /etc/fstab.dotfiles-backup-* /etc/fstab
```

Restaurar configs de usuario:

```bash
ls ~/.dotfiles-backup/
# Copia los que quieras restaurar
```

## ¿Por qué no usan GNU Stow?

Stow es excelente para dotfiles puros, pero:

- Mi estructura incluye **scripts de instalación** que tocan `/etc/`
- Necesito `setup.sh` ejecutable desde cualquier lado
- Los symlinks de dotfiles son solo una parte

Si prefieres Stow puro, los configs en `config/` funcionan con:

```bash
cd ~/.dotfiles
stow zsh tmux kitty starship git
```

## ¿Cómo extiendo?

1. Crea un nuevo step en `setup.sh`:\
   ```bash
   step_mi_tool() {
     should_run mi_tool || return 0
     log_section "Mi tool"
     # tu código
   }
   ```
2. Agrégalo al pipeline en `main()`
3. Agrégalo a la lista de steps disponibles en `usage()`

## ¿Por qué no usar Ansible/Salt/Nix?

- **Ansible**: overkill para setup personal, requiere Python.
- **Nix**: hermosa pero cambia todo el modelo mental.
- **Bash + PowerShell**: 100% portable, sin dependencias raras, 2 archivos entry
  point.

## ¿Funciona con Fish?

Parcialmente. `setup.sh` cambia el shell default a Zsh en Linux. Para Fish, los
plugins de `~/.zshrc` no aplican, pero el resto (tmux, kitty, dev-tools) sí.
Edita `config/zsh/.zshrc` y copia lo que aplique a `~/.config/fish/config.fish`.

## ¿Cómo actualizo?

```bash
cd ~/.dotfiles
git pull
./setup.sh
```

El script es idempotente — corre lo que falte.

## ¿Funciona con Zsh en Windows (WSL)?

Sí. WSL2 con Ubuntu/Fedora adentro, `setup.sh` corre normal.

## ¿Por qué Kitty y no Alacritty/WezTerm?

- **Kitty**: GPU-accelerated, image preview, protocolo de graphics estable.
- **Alacritty**: similar pero más simple, scrollback limitado.
- **WezTerm**: Lua-based, muy flexible, pero más lento.

Si prefieres Alacritty, reemplaza `config/kitty/kitty.conf` por tu
`alacritty.toml` y actualiza `_install_nerd_font` en `setup.sh`.

## ¿Cómo agrego un monitor de sistema?

`btop` ya viene. Alternativas GUI:

- **Mission Center** (Linux, GNOME):
  `flatpak install flathub io.missioncenter.MissionCenter`
- **iStat Menus** (macOS, comercial): $15
- **HWiNFO64** (Windows): gratis

## ¿Por qué `ripgrep` en lugar de `grep`?

- 5-10x más rápido en codebases grandes
- Respeta `.gitignore` por default
- Output coloreado

## ¿Cómo desactivo un paso temporalmente?

```bash
./setup.sh --skip ssd,ram
# o
DOTFILES_SKIP=ssd,ram ./setup.sh
```

## ¿Cómo veo solo los pasos disponibles?

```bash
./setup.sh --help
```

## ¿Cómo funciona la detección de hardware en máquinas virtuales?

Detección es heurística:

- VMs reportan CPU genérico (QEMU Virtual CPU)
- `DOTFILES_CPU_PROFILE=other`
- `DOTFILES_RAM_GB` se detecta correctamente
- `DOTFILES_IS_LAPTOP=0` (chassis = 1 = Other)
- `DOTFILES_STORAGE_TYPE=ssd` (default VMs usan virtual disk)

Las optimizaciones aplican igual, pero algunas (scheduler, governor) pueden no
tener efecto.

## ¿Es código abierto?

Sí, MIT. Fork, modifica, redistribuye.

## ¿Cómo reporto un bug?

Abre un issue con:

- Output de `./setup.sh --dry-run` (la parte que falla)
- `~/.dotfiles-install.log` (últimas 100 líneas)
- SO y versión (`cat /etc/os-release` o `sw_vers`)
- Hardware (`lscpu`, `free -h`)
