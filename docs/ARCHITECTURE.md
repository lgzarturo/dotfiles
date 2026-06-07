# Arquitectura del dotfiles

## Filosofía de diseño

1. **Detección, no asunción** — Cada script detecta SO, hardware y entorno antes
   de actuar.
2. **Idempotencia** — Correr el script múltiples veces produce el mismo
   resultado.
3. **Modularidad** — Cada paso es independiente. `--skip` o `--only` permite
   granularidad.
4. **Reversibilidad** — Backups automáticos de todo lo modificado. Marcadores
   `# managed by dotfiles` para identificar archivos.
5. **Perfiles** — `laptop` (energía), `desktop` (balance), `workstation`
   (agresivo), `minimal` (conservador).

## Capas de ejecución

```text
setup.sh
├── lib/ (librerías compartidas)
│   ├── detect.sh         ← fuente única de verdad para variables
│   ├── logger.sh         ← logging con colores, dry-run
│   ├── package-managers.sh ← abstracción (apt/dnf/brew/pacman)
│   ├── sysctl-tune.sh    ← optimizaciones kernel
│   ├── ssd-tune.sh       ← TRIM, scheduler, noatime
│   ├── ram-tune.sh       ← zram + swapfile
│   └── agent-tools.sh    ← Claude Code, Ollama
│
├── steps (definidos en setup.sh)
│   ├── preflight
│   ├── backup
│   ├── system-update
│   ├── core-packages
│   ├── shell             ← Zsh + Starship + Zap
│   ├── terminal          ← Kitty + Nerd Font
│   ├── multiplexer       ← tmux + TPM
│   ├── dev-tools         ← rg, fd, bat, eza, fzf, lazygit
│   ├── runtimes          ← mise, uv, node
│   ├── agent-tools       ← Claude Code, Ollama
│   ├── gnome / macos     ← tweaks del SO
│   ├── sysctl            ← kernel tuning
│   ├── ssd               ← storage
│   ├── ram               ← zram + swap
│   ├── network           ← TCP BBR
│   ├── dotfiles-link     ← symlinks
│   └── post-install      ← verificación
│
├── config/ (archivos versionados)
│   ├── zsh/.zshrc
│   ├── tmux/.tmux.conf
│   ├── kitty/kitty.conf
│   ├── starship/starship.toml
│   ├── git/.gitconfig
│   └── powershell/Microsoft.PowerShell_profile.ps1
│
└── bin/ (scripts auxiliares, linkeados a ~/bin)
    ├── new-agent-project
    ├── safe-claude
    ├── agent-log
    └── sync-dotfiles
```

## Variables exportadas (detect.sh)

```bash
DOTFILES_OS              # linux | macos | windows | freebsd | other
DOTFILES_OS_FAMILY       # linux | unix | bsd | other
DOTFILES_DISTRO          # fedora | ubuntu | macos | ...
DOTFILES_DISTRO_VERSION
DOTFILES_PKG_MANAGER     # dnf | dnf5 | apt | brew | pacman | winget
DOTFILES_INIT_SYSTEM     # systemd | launchd | openrc
DOTFILES_DESKTOP_ENV     # gnome | aqua | kde | ...
DOTFILES_SHELL_DEFAULT   # bash | zsh | fish

DOTFILES_CPU_MODEL
DOTFILES_CPU_VENDOR
DOTFILES_CPU_CORES_PHYSICAL
DOTFILES_CPU_CORES_LOGICAL
DOTFILES_CPU_THREADS
DOTFILES_CPU_PROFILE      # ryzen5 | ryzen9 | m2 | m4 | intel | other
DOTFILES_RAM_GB
DOTFILES_HAS_GPU_AMD
DOTFILES_HAS_GPU_NVIDIA
DOTFILES_HAS_GPU_APPLE
DOTFILES_IS_LAPTOP        # 0 | 1
DOTFILES_STORAGE_TYPE     # ssd | nvme | hdd | apple_ssd
DOTFILES_SWAP_GB
```

## Perfiles

| Perfil        | Uso                      | Características                                          |
| ------------- | ------------------------ | -------------------------------------------------------- |
| `laptop`      | Ryzen 5/9 PRO, batería   | Swappiness 20, scheduler conservador, ZRAM moderado      |
| `desktop`     | Ryzen 5/9, 32GB+         | Swappiness 10, scheduler mq-deadline, sin ahorro energía |
| `workstation` | Epyc/Threadripper, 64GB+ | Swappiness 5, ZRAM 3/4 RAM, 1M inotify watches           |
| `minimal`     | Cualquiera               | Solo tooling y shell, sin tuning de kernel               |

## Marcadores

Cada archivo generado lleva un marcador para identificación y no-duplicación:

- `/etc/sysctl.d/99-dotfiles-agentic.conf` → `# managed by dotfiles-agentic`
- `/etc/systemd/zram-generator.conf` → `# dotfiles-agentic — zram tuning`
- `/etc/udev/rules.d/60-ioschedulers.rules` →
  `# dotfiles-agentic: I/O scheduler`
- `/etc/fstab` → `# dotfiles-agentic: noatime/nodiratime`

Para verificar si algo fue tocado por dotfiles:

```bash
grep -r "dotfiles-agentic" /etc /usr/local/bin ~/ 2>/dev/null
```

## Dry-run

```bash
./setup.sh --dry-run
```

Muestra todos los comandos sin ejecutarlos. Útil para auditar antes de aplicar.

## Logs

```bash
$DOTFILES_LOG_FILE  # default: ~/.dotfiles-install.log
```

Cada paso registra: timestamp, nivel, mensaje.
