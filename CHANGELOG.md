# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **`git-config` step** in `setup.sh` and `setup.ps1`: interactively prompts for `user.name` and `user.email` during setup and writes them to `config/git/.gitconfig` using `git config --file`. Runs before `dotfiles-link` so values are correct when the symlink is created.
  - Detects existing values from the system's global git config as prompt defaults.
  - Placeholder-aware: `"Tu Nombre"` / `"tu@email.com"` are never used as defaults.
  - Respects `--yes` / `-Yes` (skips prompt if valid defaults exist), `--dry-run` / `-DryRun` (shows what would be written without modifying files), `--skip git-config` / `-Skip git-config` (skips the step entirely).
- `Install-WingetPackage` helper in `setup.ps1`: centralises winget invocations and correctly handles the non-zero exit code (`0x8A150101`) returned when a package is already installed and up to date.
- `winget source update` before the core-packages loop in `setup.ps1` to ensure the local package catalog is current.

### Fixed
- **`lib/agent-tools.sh` — npm y node desactualizados al instalar Agent Tools**: se añade `_update_node_npm()` que ejecuta `npm install -g npm@latest` (best-effort) y `mise upgrade node` antes de instalar paquetes globales. Además, `ensure_claude_code` ahora actualiza Claude Code cuando ya está instalado en lugar de retornar sin hacer nada.
- **`setup.sh` — `Unknown option: -s` al instalar Starship**: la llamada era `sh "$tmp" -s -- -y`; el instalador de Starship recibía `-s` como opción desconocida y abortaba. Corregido a `sh "$tmp" --yes` (flag documentado: `-y`/`--yes`).
- **`setup.sh` — argumentos inválidos al instalar Zap**: la llamada era `zsh "$tmp" "" --silent`; `--silent` no existe en el instalador de Zap y `""` es un argumento vacío inesperado. Corregido a `zsh "$tmp" --branch release-v1 --keep-zshrc` para instalar la rama estable y preservar el `.zshrc` ya enlazado por dotfiles.
- **`setup.sh` — `E: Unable to locate package xz` en Ubuntu/Debian**: el nombre correcto del paquete en sistemas APT es `xz-utils`, no `xz`. Corregido en la lista de core packages del bloque `linux)` (el bloque `fedora|rhel|...` ya usaba el nombre correcto para RPM).
- **`setup.sh` — `$'\r': command not found` en WSL**: cuando el repo se clona en Windows con `core.autocrlf=true`, los scripts `lib/*.sh` quedan con CRLF en disco y bash falla al cargarlos vía `/mnt/c/...`. Se añade un bucle `sed -i 's/\r$//'` en `setup.sh` antes de cualquier `source`, normalizando todos los scripts de lib en tiempo de ejecución como red de seguridad.
- **`setup.ps1` — winget false-negative WARNs**: packages already installed and up to date were incorrectly logged as failures. Fixed by detecting "ya instalado / ninguna actualización" in winget output.
- **`setup.ps1` — `BurntSushi.ripgrep` package not found**: corrected winget ID to `BurntSushi.ripgrep.MSVC` (the correct community package for Windows).
- **`setup.ps1` — `Cannot bind argument to parameter 'Path' because it is an empty string`**: `Split-Path -Parent` returns `""` for bare filenames; added null guard before `New-Item` in the shell/profile linking step.
- **`setup.ps1` — string interpolation bug**: `"$l.Dst.dotfiles-backup"` expanded `$l` as the hashtable string literal. Fixed to `"$($l.Dst).dotfiles-backup"`.
- **`lib/detect.ps1` — `IsWSL` always `$true`**: `wsl --status` returning 0 means WSL is *installed*, not that PowerShell is running *inside* WSL. `IsWSL` is now always `$false` in the PowerShell script (correct for native Windows execution).
- **`setup.ps1` — Starship winget call missing agreement flags**: added `--accept-source-agreements --accept-package-agreements`.
