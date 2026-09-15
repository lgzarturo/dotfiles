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
- 🛡️ **Seguro**: dry-run disponible, backups automáticos y sin ejecutar
  instaladores remotos no verificados

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
| `DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES` | Habilita aliases inseguros de forma explícita | `false` |
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
11. `agent-aliases` — Aliases inseguros solo por opt-in explícito
12. `matrix-fetch` — Fastfetch ultrarrápido (<15ms) estilo Matrix para inicio de terminal
13. `gnome` / `macos` / `windows` — Tweaks del SO
14. `sysctl` — Tuning de kernel
15. `ssd` — Optimización de almacenamiento
16. `ram` — ZRAM/swap
17. `network` — TCP BBR, fq, etc.
18. `dotfiles-link` — Symlinks de configs
19. `post-install` — Verificación final

## 🤖 Aliases de herramientas agenticas

El paso `agent-aliases` detecta qué herramientas están instaladas y configura
aliases inseguros **solo** cuando el usuario los habilita explícitamente con
`DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES=true` o `--enable-unsafe-agent-aliases`:

| Herramienta | Alias configurado |
| ----------- | ----------------- |
| `claude`    | `claude --allow-dangerously-skip-permissions` |
| `agy`       | `agy --dangerously-skip-permissions` |
| `opencode`  | `opencode --auto` |
| `codex`     | `codex --dangerously-bypass-approvals-and-sandbox` |

- **Linux / macOS / WSL**: aliases escritos en `~/.zshrc.local` (cargado por `.zshrc`)
- **Windows**: funciones wrapper escritas en `profile.local.ps1` junto a `$PROFILE`
- **Idempotente**: re-ejecutar el paso no duplica entradas (usa bloques centinela)
- **Seguro por defecto**: si no activas el opt-in, no se escribe ningún alias inseguro
- **Solo herramientas presentes**: si una herramienta no está en PATH, su alias no se configura

### Ejecutar solo este paso

```bash
# Linux / macOS / WSL
DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES=true ./setup.sh --only agent-aliases
./setup.sh --only agent-aliases
./setup.sh --only agent-aliases --dry-run   # preview sin modificar nada
```

```powershell
# Windows
.\setup.ps1 -Only agent-aliases -EnableUnsafeAgentAliases
.\setup.ps1 -Only agent-aliases
.\setup.ps1 -Only agent-aliases -DryRun     # preview sin modificar nada
```

## 🟩 Matrix Fastfetch (`matrix-fetch`)

Fastfetch ultrarrápido (<15ms) con diseño cyberpunk estilo Matrix que se ejecuta automáticamente al abrir una ventana de la terminal:

- **Estado del equipo**: Host, distro OS, kernel, uptime, CPU (modelo y cores), RAM con barra gráfica y almacenamiento en disco.
- **Carpeta actual**: Ruta compacta (`~`) y conteo acotado de elementos.
- **Repositorio Git**: Rama actual, estado (`● clean` / `▲ dirty` / `+untracked`) y sincronización remota (`↑ahead / ↓behind`).
- **Rendimiento**: Temporizador en milisegundos (`init X.Xms`) gracias a lectura directa de `/proc` sin forks pesados.
- **Configuración en instalación**: Paso `matrix-fetch` en `setup.sh` que escribe en `~/.zshrc.local` usando bloques centinela idempotentes.

```bash
# Ejecutar en cualquier momento
matrix-fetch
fetch                     # alias rápido configurado en .zshrc.local

# Opciones
matrix-fetch --compact    # forzar HUD compacto de una sola columna
matrix-fetch --short      # resumen en una sola línea
matrix-fetch --no-color   # sin secuencias de escape ANSI

# Configurar solo este paso
./setup.sh --only matrix-fetch
./setup.sh --only matrix-fetch --dry-run
```

## 🧪 Verificación

```bash
./scripts/verify.sh
./scripts/maintenance/repo-security-check.sh
./tests/test-fedora-maintenance.sh
```

- `./scripts/verify.sh` verifica el entorno instalado.
- `./scripts/maintenance/repo-security-check.sh` audita el repositorio en busca
  de secretos, rutas personales hardcodeadas y patrones inseguros de descarga +
  ejecución remota.
- `fedora-maintenance` ofrece mantenimiento interactivo de Fedora con
  configuración, snapshots y reporte: `fm-menu`, `fm-status`, `fm-dry` o
  `fm-logs`. Consulta la
  [guía de uso](USAGE.md#fedora-maintenance) antes de instalar el timer semanal.

## 📚 Documentación extendida

- [Arquitectura](docs/ARCHITECTURE.md)
- [Hardware soportado](docs/HARDWARE.md)
- [Setup por sistema](docs/PER-SETUP.md)
- [Configuración local de Git (skip-worktree)](GIT-LOCAL-CONFIG.md)
- [FAQ](docs/FAQ.md)
- [Inventario y migración de scripts](docs/SCRIPT-MIGRATION.md)

## ⚖️ Licencia

[MIT](LICENSE)

## Autor

Arturo López <lgzarturo@gmail.com>
