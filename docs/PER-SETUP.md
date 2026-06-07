# Setup por Sistema

## Fedora 44 (caso principal)

```bash
# Pre-requisitos
sudo dnf5 install -y git curl

# Clone
git clone https://github.com/lgzarturo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Ejecutar
chmod +x setup.sh
./setup.sh
```

### Particularidades de Fedora

- **dmg5** es el gestor moderno (disponible en Fedora 41+)
- **RPM Fusion** necesario para algunos paquetes (no se instala automáticamente
  — descomentar en lib/package-managers.sh si lo necesitas)
- **SELinux** permanece enforcing (no tocamos)
- **Wayland** es default en GNOME
- **PipeWire** ya viene, no se reemplaza

### Qué cambia respecto a Ubuntu

- `dnf5` en lugar de `apt`
- `dnf5 copr enable` para repos comunitarios
- `/etc/sysconfig/` en lugar de `/etc/default/`

## Ubuntu 24.04 LTS

```bash
sudo apt update
sudo apt install -y git curl

git clone https://github.com/lgzarturo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
chmod +x setup.sh
./setup.sh
```

### Particularidades de Ubuntu

- **APT** + **Snap** coexisten
- **GNOME** es el DE por defecto en Desktop
- **eza** se instala desde repo custom de gierens.de
- **Nerd Font** vía descarga directa (no hay paquete oficial)

## macOS (Apple Silicon M2/M4 o Intel)

```bash
# Pre-requisitos: Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

git clone https://github.com/lgzarturo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
chmod +x setup.sh
./setup.sh --profile laptop    # si es MacBook
./setup.sh --profile workstation  # si es Mac mini/studio con M2/M4 Max
```

### Particularidades de macOS

- **brew** es el único gestor soportado
- **Kitty** se instala como cask
- **Nerd Font** igual que Linux
- **iTerm2** opcional (Kitty es multiplataforma, mejor consistencia)
- **defaults write** para tweaks de Finder, Dock, etc.
- **TRIM** en SSDs no-Apple: `sudo trimforce --enable` (con riesgo)

### M2/M4 específico

- Ollama con Metal (auto)
- `arch -arm64 brew install ...` si necesitas solo ARM
- No hay ZRAM, no se tunnea swap

## Windows 11

```powershell
# Pre-requisitos: winget (incluido en Windows 11)
git clone https://github.com/lgzarturo/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
.\setup.ps1
```

### Opciones para Windows

#### Opción A: WSL2 (recomendado)

WSL2 con Fedora o Ubuntu adentro. Corres `setup.sh` dentro de WSL. Mejor
experiencia para tmux, agentes Linux.

```powershell
wsl --install -d Ubuntu-24.04
# Dentro de WSL:
git clone ...
./setup.sh
```

#### Opción B: PowerShell nativo

- Kitty no está en Windows por defecto — usamos **Windows Terminal**
- tmux requiere WSL o Cygwin
- Claude Code funciona nativo
- Algunas optimizaciones de kernel no aplican

### Hardware-specific Windows

**M2/M4 con Asahi Linux:** correr `setup.sh` dentro de Asahi, no Windows.
**Ryzen:** igual que Linux, `setup.sh` dentro de WSL. **Intel:** igual.

## Ejecutar con perfil custom

```bash
# Forzar perfil
DOTFILES_PROFILE=workstation ./setup.sh

# Saltar SSD (si no quieres que toque fstab)
./setup.sh --skip ssd,ram

# Solo instalar shell + tmux + tools
./setup.sh --only shell,terminal,multiplexer,dev-tools

# Dry-run para ver qué haría
./setup.sh --dry-run
```

## Sincronización entre máquinas

```bash
# Máquina A: cambios
cd ~/.dotfiles
$EDITOR config/zsh/.zshrc
./bin/sync-dotfiles push

# Máquina B: aplicar
cd ~/.dotfiles
./bin/sync-dotfiles pull
./setup.sh --only dotfiles-link
```

## Troubleshooting

### "Permission denied" en setup.sh

```bash
chmod +x setup.sh
```

### "sudo: command not found" en Fedora minimal

```bash
# Fedora minimal no trae sudo. Usa root o:
su -c "dnf install -y sudo && usermod -aG wheel $USER"
```

### Nerd Font no aparece en Kitty

```bash
fc-cache -fv
# Reinicia Kitty
```

### tmux plugins no se instalan

```bash
# Dentro de tmux:
prefix + I
# default prefix es Ctrl+b en tmux default, Ctrl+a en este config
```

### Ollama no detecta GPU

```bash
# Linux: verifica ROCm/CUDA
ollama run llama3 "test" --verbose
# Mira logs: journalctl -u ollama -f
```

### "Cannot connect to Docker daemon"

```bash
# WSL2:
sudo systemctl start docker
# O si usas rootless:
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
```
