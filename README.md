# 🛠️ dotfiles

Configuración integral y portable para entorno de desarrollo agentico (Claude
Code, Ollama, etc.). Soporta: **Fedora / Ubuntu / macOS / Windows 11 (WSL2
nativo)**, con detección automática de hardware (Ryzen 5, Ryzen 9, Apple M2/M4)
y optimizaciones específicas para SSD, RAM, CPU y red.

## ✨ Características

- 🔍 **Detección automática de SO** (distro, versión, gestor de paquetes, shell)
- 🧠 **Detección de hardware** (CPU, RAM, SSD/NVMe, GPU, swap)
- ⚡ **Optimizaciones por perfil**: `laptop`, `desktop`, `workstation`
- 🖥️ **Tuning por plataforma**: Fedora, Ubuntu, macOS, Windows (PowerShell)
- 🤖 **Tooling agentico pre-instalado**: Claude Code, Ollama, Open WebUI
  opcional
- 🔁 **Idempotente**: se puede correr múltiples veces sin romper nada
- 🧱 **Modular**: cada paso puede saltarse con `--skip` o `--only`
- 🛡️ **Seguro**: dry-run disponible, backups automáticos de configs previas

## 📁 Estructura

```text
dotfiles/
├── setup.sh              # entry point Unix (Linux/macOS/WSL)
├── setup.ps1             # entry point Windows (PowerShell nativo)
├── lib/
│   ├── detect.sh         # detección de SO, hardware, shell
│   ├── detect.ps1        # equivalente Windows
│   ├── logger.sh         # logging con colores
│   ├── logger.ps1        # logging Windows
│   ├── package-managers.sh  # apt | dnf | brew | pacman
│   ├── sysctl-tune.sh    # optimizaciones kernel
│   ├── ssd-tune.sh       # optimizaciones SSD/NVMe
│   ├── ram-tune.sh       # zram/swap tuning
│   └── agent-tools.sh    # instalación Claude Code, Ollama, etc.
├── config/
│   ├── zsh/              # .zshrc + plugins
│   ├── tmux/             # .tmux.conf + plugins
│   ├── kitty/            # kitty.conf
│   ├── starship/         # starship.toml
│   ├── powershell/       # Microsoft.PowerShell_profile.ps1
│   └── git/              # .gitconfig + .gitignore_global
├── bin/                  # scripts auxiliares
│   ├── new-agent-project
│   ├── safe-claude
│   ├── agent-log
│   └── sync-dotfiles
├── docs/
│   ├── ARCHITECTURE.md
│   ├── HARDWARE.md
│   ├── PER-SETUP.md
│   └── FAQ.md
└── assets/               # capturas, diagramas
```

## 🚀 Uso rápido

### Linux / macOS / WSL

```bash
git clone https://github.com/lgzarturo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
chmod +x setup.sh
./setup.sh                # modo interactivo
./setup.sh --yes          # aceptar todo
./setup.sh --dry-run      # solo mostrar lo que haría
./setup.sh --skip ssd     # saltar paso SSD
./setup.sh --only shell   # solo instalar shell stack
```

### Windows (PowerShell nativo, fuera de WSL)

Requiere **PowerShell 7+** (pwsh) en Windows 11.

```powershell
git clone https://github.com/lgzarturo/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
.\setup.ps1               # interactivo
.\setup.ps1 -Yes          # aceptar todo
.\setup.ps1 -DryRun       # preview (no modifica el sistema)
.\setup.ps1 -Skip shell   # saltar paso shell
.\setup.ps1 -Only preflight,backup  # solo estos pasos
```

## 🧭 Perfiles

| Perfil        | Uso                          | Optimizaciones                                        |
| ------------- | ---------------------------- | ----------------------------------------------------- |
| `laptop`      | Portátil                     | Battery aware, energía, thermal throttling            |
| `desktop`     | PC de escritorio             | Performance agresiva, sin thermal concerns            |
| `workstation` | Estación de trabajo IA       | Todo al máximo, llama.cpp con ROCm/Metal, ZRAM máximo |
| `minimal`     | Sin optimizaciones agresivas | Solo tooling y shell                                  |

## 🔧 Variables de entorno reconocidas

| Variable            | Descripción                           | Default     |
| ------------------- | ------------------------------------- | ----------- |
| `DOTFILES_PROFILE`  | laptop, desktop, workstation, minimal | auto-detect |
| `DOTFILES_SKIP`     | Coma-separado de pasos a saltar       | (vacío)     |
| `DOTFILES_ONLY`     | Solo correr estos pasos               | (vacío)     |
| `ANTHROPIC_API_KEY` | API key de Claude                     | (vacío)     |
| `DOTFILES_DRY_RUN`  | Solo simular                          | `false`     |

## 📋 Lista de pasos (orden de ejecución)

1. `preflight` — Verifica requisitos
2. `backup` — Backup de configs existentes
3. `system-update` — Actualiza SO
4. `core-packages` — Paquetes base
5. `shell` — Zsh/Bash + Starship + plugins
6. `terminal` — Kitty (o Warp/iTerm2 en macOS, Windows Terminal)
7. `multiplexer` — tmux + plugins
8. `dev-tools` — rg, fd, bat, eza, fzf, lazygit, etc.
9. `runtimes` — mise/uv/node/python
10. `agent-tools` — Claude Code, Ollama (opcional)
11. `agent-aliases` — Aliases de herramientas agenticas con flags de permisividad
12. `gnome` / `macos` / `windows` — Tweaks del SO
13. `sysctl` — Tuning de kernel
14. `ssd` — Optimización de almacenamiento
15. `ram` — ZRAM/swap
16. `network` — TCP BBR, fq, etc.
17. `dotfiles-link` — Symlinks de configs
18. `post-install` — Verificación final

## 🤖 Aliases de herramientas agenticas

El paso `agent-aliases` detecta qué herramientas están instaladas y configura
automáticamente aliases con sus flags de permisividad:

| Herramienta | Alias configurado |
| ----------- | ----------------- |
| `claude`    | `claude --allow-dangerously-skip-permissions` |
| `agy`       | `agy --dangerously-skip-permissions` |
| `opencode`  | `opencode --auto` |
| `codex`     | `codex --dangerously-bypass-approvals-and-sandbox` |

- **Linux / macOS / WSL**: aliases escritos en `~/.zshrc.local` (cargado por `.zshrc`)
- **Windows**: funciones wrapper escritas en `profile.local.ps1` junto a `$PROFILE`
- **Idempotente**: re-ejecutar el paso no duplica entradas (usa bloques centinela)
- **Solo herramientas presentes**: si una herramienta no está en PATH, su alias no se configura

### Ejecutar solo este paso

```bash
# Linux / macOS / WSL
./setup.sh --only agent-aliases
./setup.sh --only agent-aliases --dry-run   # preview sin modificar nada
```

```powershell
# Windows
.\setup.ps1 -Only agent-aliases
.\setup.ps1 -Only agent-aliases -DryRun     # preview sin modificar nada
```

## 🧪 Verificación

```bash
./scripts/verify.sh
```

Verifica que cada componente quedó instalado y configurado correctamente.

## 📚 Documentación extendida

- [Arquitectura](docs/ARCHITECTURE.md)
- [Hardware soportado](docs/HARDWARE.md)
- [Setup por sistema](docs/PER-SETUP.md)
- [FAQ](docs/FAQ.md)

## ⚖️ Licencia

[MIT](LICENSE)

## Autor

Arturo López <lgzarturo@gmail.com>
