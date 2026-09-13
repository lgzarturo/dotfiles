# Scripts — Guía de Uso (USAGE.md)

> Repositorio: `~/.dotfiles`  
> Ubicación de scripts ejecutables: `~/.dotfiles/bin/` (disponibles en `$PATH`)  
> Ubicación de scripts de configuración: `~/.dotfiles/scripts/`

---

## Índice

- [Scripts disponibles en la terminal (bin/)](#scripts-disponibles-en-la-terminal-bin)
  - [gen-apikey](#gen-apikey)
  - [gen-password](#gen-password)
  - [gwt](#gwt)
  - [gwt-clean](#gwt-clean)
  - [ai-agent](#ai-agent)
  - [png2webp](#png2webp)
  - [img-optimize](#img-optimize)
  - [img-batch-webp](#img-batch-webp)
  - [validate-domain](#validate-domain)
- [Scripts de configuración (scripts/)](#scripts-de-configuración-scripts)
  - [setup/bootstrap.sh](#setupbootstrapsh)
  - [setup/dev-setup.sh](#setupdev-setupsh)
  - [setup/git-tools.sh](#setupgit-toolssh)
  - [setup/install-fonts.sh](#setupinstall-fontssh)
  - [maintenance/repo-security-check.sh](#maintenancerepo-security-checksh)
  - [maintenance/system-audit.sh](#maintenancesystem-auditsh)
  - [maintenance/system-optimize.sh](#maintenancesystem-optimizesh)
  - [hardware/dell-kbd-backlight.sh](#hardwaredell-kbd-backlightsh)
  - [hardware/fix-howdy.sh](#hardwarefix-howdysh)
  - [desktop/switch-dm.sh](#desktopswitch-dmsh)
- [Cómo agregar más scripts](#cómo-agregar-más-scripts)

---

## Scripts disponibles en la terminal (`bin/`)

> Todos estos scripts están en `~/.dotfiles/bin/` y se pueden ejecutar directamente desde la terminal sin ruta completa gracias al `$PATH` configurado en `.zshrc`.

---

### `gen-apikey`

**Generador seguro de API Keys y secretos**

Genera claves criptográficamente seguras usando `/dev/urandom` o `openssl`. Compatible con Linux y macOS.

```bash
# Uso básico
gen-apikey JWT_SECRET:32
gen-apikey JWT_SECRET:32,JWT_REFRESH_SECRET:32,API_KEY_SALT:16

# Formato hex
gen-apikey --hex API_HASH:32

# Salida JSON
gen-apikey --json JWT_SECRET:32,REFRESH_SECRET:32

# Salida como export (para .env)
gen-apikey --export SECRET:64

# Solo valores (sin nombre)
gen-apikey --values-only DB_PASSWORD:24

# Ver ayuda
gen-apikey --help
```

**Opciones disponibles:**

| Opción | Descripción |
|--------|-------------|
| `-l, --length NUM` | Longitud por defecto |
| `-a, --alphanumeric` | Solo A-Z, a-z, 0-9 (por defecto) |
| `-x, --hex` | Hexadecimal en minúsculas |
| `-X, --HEX` | Hexadecimal en mayúsculas |
| `-b, --base64url` | Caracteres seguros para URL |
| `-s, --symbols` | Incluir símbolos especiales |
| `-j, --json` | Salida en JSON |
| `-e, --export` | Salida con `export KEY="VALUE"` |
| `-v, --values-only` | Solo valores, sin nombres |

---

### `gen-password`

**Generador seguro de contraseñas**

```bash
# Por defecto: 32 caracteres con símbolos
gen-password

# 64 caracteres
gen-password -l 64

# Solo alfanuméricos (sin símbolos)
gen-password -a -l 16

# Con símbolos explícito
gen-password -s -l 20

# Ver ayuda
gen-password -h
```

**Dependencias:** `/dev/urandom` (estándar en Linux/macOS)

---

### `gwt`

**Git Worktree Manager — crea un worktree y una sesión Tmux aislada**

Ideal para trabajar en múltiples ramas simultáneamente sin contaminar el entorno de trabajo.

```bash
# Crear worktree para feature/auth desde main
gwt feature/auth

# Crear worktree desde una rama base específica
gwt feature/auth develop

# Crear hotfix desde main
gwt hotfix/bug-123 main
```

**Qué hace:**
1. Sincroniza el repositorio remoto (`git fetch --all --prune`)
2. Crea el worktree en `../nombre-de-rama/`
3. Copia el `.env` si existe en el directorio actual
4. Abre una sesión Tmux aislada apuntando al nuevo worktree

**Dependencias:** `git`, `tmux` (opcional pero recomendado)

---

### `gwt-clean`

**Limpieza de Git Worktrees y ramas ya fusionadas**

Elimina automáticamente los worktrees y ramas que ya fueron fusionadas a la rama actual.

```bash
# Ejecutar desde la rama principal (main, develop, etc.)
gwt-clean
```

**Qué hace:**
1. Sincroniza el repositorio (`git fetch --all --prune`)
2. Detecta ramas fusionadas (excluyendo `main`, `master`, `develop`)
3. Elimina el worktree del sistema de archivos
4. Elimina la rama local
5. Cierra la sesión Tmux correspondiente (si existe)
6. Ejecuta `git worktree prune`

**Dependencias:** `git`, `tmux` (opcional)

---

### `ai-agent`

**CLI Controller para Agentes de IA Local (Ollama)**

Interfaz para consultar modelos de IA locales mediante Ollama.

```bash
# Agente arquitecto de software
ai-agent architect "Diseña una API REST para pagos con idempotencia"

# Agente codificador
ai-agent coder "Implementa función de hash seguro en Go"

# Generador de pruebas
ai-agent test ./src/auth.py

# Validador/auditor de seguridad
ai-agent validate ./src/api.py

# Pipe: analizar el diff actual
git diff | ai-agent validate

# Pipe: analizar código de un archivo
cat main.go | ai-agent validate

# Estado del servicio Ollama
ai-agent status

# Benchmark de velocidad
ai-agent benchmark

# Listar agentes disponibles
ai-agent list
```

**Configuración mediante variables de entorno:**

```bash
export OLLAMA_HOST="http://127.0.0.1:11434"  # URL del servidor (por defecto)
export OLLAMA_BIN="$HOME/.local/bin/ollama"   # Ruta al binario (por defecto)
```

**Dependencias:** `ollama`, `curl`, `jq`

> **Nota:** Requiere que el servidor Ollama esté ejecutándose:  
> `systemctl --user start ollama.service`

---

### `png2webp`

**Convertir un archivo PNG a WebP**

```bash
# Conversión con calidad por defecto (82)
png2webp foto.png

# Con calidad personalizada
png2webp foto.png 90

# Convertir múltiples archivos
png2webp *.png
```

**Dependencias:** ImageMagick 7+ (`magick`) o ImageMagick 6 (`convert`)

```bash
# Instalar dependencias
sudo dnf install ImageMagick      # Fedora
sudo apt install imagemagick      # Ubuntu/Debian
sudo pacman -S imagemagick        # Arch
brew install imagemagick          # macOS
```

---

### `img-optimize`

**Optimizar una imagen PNG a WebP en múltiples resoluciones**

Genera automáticamente variantes responsivas: desktop, tablet y mobile.

```bash
img-optimize hero.png
img-optimize banner.png
```

**Genera en `./processed_assets/`:**
- `hero-desktop.webp` — 1920px, calidad 85
- `hero-tablet.webp` — 1024px, calidad 80
- `hero-mobile.webp` — 600px, calidad 75

**Dependencias:** ImageMagick (ver [png2webp](#png2webp))

---

### `img-batch-webp`

**Convertir por lotes todos los PNG de un directorio a WebP responsivo**

```bash
# Convertir todos los PNG del directorio actual → ./webp/
img-batch-webp

# Especificar directorio de entrada y salida
img-batch-webp ./assets ./output
```

**Por cada archivo `nombre.png` genera:**
- `nombre.webp` — 1920px, calidad 85
- `nombre-tablet.webp` — 1024px, calidad 82
- `nombre-mobile.webp` — 600px, calidad 80

**Dependencias:** ImageMagick (ver [png2webp](#png2webp))

---

### `validate-domain`

**Validación completa de dominio: DNS, HTTPS, TLS, Cloudflare**

```bash
# Validar un dominio
validate-domain ejemplo.com

# Validar con verificación de IP esperada
validate-domain ejemplo.com 159.65.171.181

# Validar subdominio
validate-domain sub.ejemplo.com
```

**Validaciones realizadas:**
1. Resolución DNS (registro A)
2. Verificación de proxy Cloudflare
3. Ping a IP esperada (si se proporciona)
4. HTTPS activo
5. Certificado TLS (emisor y fecha de expiración)
6. Redirección HTTP → HTTPS

**Dependencias:** `dig`, `curl`, `openssl`, `ping`

```bash
# Instalar dependencias
sudo dnf install bind-utils curl openssl   # Fedora
sudo apt install dnsutils curl openssl     # Ubuntu/Debian
```

---

## Scripts de configuración (`scripts/`)

> Estos scripts son para configurar el sistema y no se ejecutan directamente desde la terminal. Se llaman con su ruta completa o desde el directorio de dotfiles.

---

### `setup/bootstrap.sh`

**Configuración base del sistema (cross-distro)**

Instala herramientas fundamentales: `git`, `curl`, `wget`, `zsh`, `neovim`, `tmux`, Docker CE, `thermald` (Intel), y Mise (gestor de versiones).

**Compatible con:** Fedora, Ubuntu/Debian, Arch Linux

```bash
sudo scripts/setup/bootstrap.sh

# Sin confirmaciones
sudo scripts/setup/bootstrap.sh --yes

# Modo simulación (sin cambios)
sudo scripts/setup/bootstrap.sh --dry-run
```

> ⚠️ **Requiere** ejecutar como `root` (`sudo`).

---

### `setup/dev-setup.sh`

**Entorno de desarrollo completo (cross-distro)**

Instala: ripgrep, fd, fzf, bat, eza/lsd, btop, Starship prompt, LazyVim para Neovim.

**Compatible con:** Fedora, Ubuntu/Debian, Arch Linux, macOS

```bash
scripts/setup/dev-setup.sh

# Solo instalar herramientas CLI
scripts/setup/dev-setup.sh --tools-only

# Omitir Starship
scripts/setup/dev-setup.sh --skip-starship

# Omitir LazyVim
scripts/setup/dev-setup.sh --skip-lazyvim
```

---

### `setup/git-tools.sh`

**Instalar GitHub CLI y LazyGit (cross-distro)**

```bash
scripts/setup/git-tools.sh
```

**Instala:**
- `gh` (GitHub CLI) — desde repositorio oficial según distro
- `lazygit` — desde COPR (Fedora), binario (Ubuntu), pacman (Arch), brew (macOS)
- Aliases en `.zshrc`: `lg`, `gpr`, `gcreate`

---

### `setup/install-fonts.sh`

**Instalar fuentes Nerd Fonts (cross-distro)**

Instala automáticamente desde GitHub Releases:
- Monaspace
- Hack Nerd Font
- FiraCode Nerd Font
- Victor Mono
- Cascadia Code
- Iosevka

```bash
scripts/setup/install-fonts.sh
```

**Compatible con:** Linux (`~/.local/share/fonts`), macOS (`~/Library/Fonts`)

---

### `maintenance/repo-security-check.sh`

**Auditoría rápida del repositorio antes de publicarlo**

Busca patrones de secretos, rutas personales hardcodeadas y combinaciones de
descarga + ejecución remota en scripts del repositorio.

```bash
scripts/maintenance/repo-security-check.sh
```

Debe ejecutarse antes de compartir cambios sensibles o publicar nuevas
automatizaciones de setup.

---

### `maintenance/system-audit.sh`

**Auditoría de hardware y diagnóstico del sistema**

Analiza sin hacer cambios: temperatura CPU/NVMe, RAM, almacenamiento SMART, batería, servicios de energía.

```bash
# Sin root (limitado — sin SMART)
scripts/maintenance/system-audit.sh

# Con root (acceso completo SMART, sensores)
sudo scripts/maintenance/system-audit.sh
```

**Código de salida:**
- `0` — Sistema sano, sin críticos
- `2` — Hay condiciones críticas detectadas

**Dependencias (opcionales):** `smartmontools`, `lm_sensors`

```bash
sudo dnf install smartmontools lm_sensors    # Fedora
sudo apt install smartmontools lm-sensors    # Ubuntu
```

---

### `maintenance/system-optimize.sh`

**Aplicar optimizaciones al sistema Linux**

Configura: perfil tuned dinámico (AC/batería), `vm.swappiness`, APST NVMe, `fstrim.timer`.

```bash
# Ver qué haría (sin cambios)
sudo scripts/maintenance/system-optimize.sh

# Aplicar con confirmación por módulo
sudo scripts/maintenance/system-optimize.sh --apply

# Aplicar todo sin confirmación
sudo scripts/maintenance/system-optimize.sh --apply --yes

# Restaurar último backup
sudo scripts/maintenance/system-optimize.sh --revert
```

> ⚠️ **Requiere** `tuned` instalado y activo: `sudo systemctl enable --now tuned`

---

### `hardware/dell-kbd-backlight.sh`

**Retroiluminación del teclado siempre encendida (laptops Dell)**

> 🔵 **Solo compatible con laptops Dell** con módulo `dell-wmi-sysman`.

```bash
# Ver estado actual
scripts/hardware/dell-kbd-backlight.sh --status

# Activar retroiluminación permanente + servicio systemd
sudo scripts/hardware/dell-kbd-backlight.sh --apply

# Restaurar configuración por defecto (10s timeout)
sudo scripts/hardware/dell-kbd-backlight.sh --revert
```

---

### `hardware/fix-howdy.sh`

**Activar reconocimiento facial IR en pantalla de bloqueo**

> 🔵 **Específico para KDE Plasma 6.** Configura PAM para usar `pam_howdy.so`.

```bash
sudo scripts/hardware/fix-howdy.sh
```

**Requisitos:** `howdy` instalado y cámara IR disponible.

```bash
# Fedora
sudo dnf copr enable principis/howdy && sudo dnf install howdy

# Ubuntu
sudo add-apt-repository ppa:boltgolt/howdy && sudo apt install howdy
```

---

### `desktop/switch-dm.sh`

**Alternar el Display Manager activo**

Compatible con: `plasmalogin` (KDE), `cosmic-greeter` (COSMIC), `gdm` (GNOME), `sddm`, `lightdm`.

```bash
# Ver DM activo
scripts/desktop/switch-dm.sh status

# Cambiar a KDE Plasma
sudo scripts/desktop/switch-dm.sh kde

# Cambiar a COSMIC Desktop
sudo scripts/desktop/switch-dm.sh cosmic

# Cambiar a GNOME/GDM
sudo scripts/desktop/switch-dm.sh gdm

# Cambiar a SDDM
sudo scripts/desktop/switch-dm.sh sddm
```

> ⚠️ El cambio surte efecto en el próximo reinicio.

---

## Cómo agregar más scripts

### Para herramientas/utilidades disponibles en terminal:

1. Crear el script en `bin/` **sin extensión**:
   ```bash
   # Ejemplo: ~/.dotfiles/bin/mi-herramienta
   touch bin/mi-herramienta
   chmod +x bin/mi-herramienta
   ```

2. Agregar shebang y `set -euo pipefail`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   # Tu código aquí...
   ```

3. Estará disponible automáticamente en la terminal (el `$PATH` ya está configurado en `.zshrc`).

### Para scripts de setup/instalación:

1. Crear el script en la carpeta apropiada de `scripts/`:
   - `scripts/setup/` — instalación de software
   - `scripts/maintenance/` — mantenimiento del sistema
   - `scripts/hardware/` — configuración de hardware específico
   - `scripts/desktop/` — entorno de escritorio

2. Documentarlo en este `USAGE.md`.

### Para detección de OS/hardware en scripts:

```bash
# Al inicio del script, cargar las librerías disponibles:
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
source "$DOTFILES_DIR/lib/detect.sh"
source "$DOTFILES_DIR/lib/logger.sh"
source "$DOTFILES_DIR/lib/package-managers.sh"

# Detectar entorno
detect_os
detect_hardware

# Usar variables detectadas:
# $DOTFILES_OS            → linux | macos | freebsd
# $DOTFILES_DISTRO        → fedora | ubuntu | arch | macos
# $DOTFILES_PKG_MANAGER   → dnf | apt | pacman | brew
# $DOTFILES_CPU_PROFILE   → intel | ryzen5 | ryzen9 | m2 | m4
# $DOTFILES_RAM_GB        → cantidad de RAM en GB
# $DOTFILES_IS_LAPTOP     → 1 si es laptop, 0 si es desktop
```

---

*Documentación generada automáticamente — actualizar al agregar nuevos scripts.*
