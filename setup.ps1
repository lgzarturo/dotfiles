# setup.ps1 — entry point para Windows 11
# Detecta: PowerShell version, WSL disponible, hardware, GPU.
# Ejecuta: optimizaciones Windows, instala tooling, prepara estructura agentica.

[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$DryRun,
    [ValidateSet("auto", "laptop", "desktop", "workstation", "minimal")]
    [string]$Profile = "auto",
    [string[]]$Skip = @(),
    [string[]]$Only = @(),
    [switch]$InstallOllama,
    [string]$LogFile = "$HOME\dotfiles-install.log",
    [string]$BackupDir = "$HOME\dotfiles-backup\$((Get-Date -Format 'yyyyMMdd-HHmmss'))"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ─── Paths ────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path $ScriptDir "lib"
$ConfigDir = Join-Path $ScriptDir "config"
$BinDir = Join-Path $ScriptDir "bin"

. (Join-Path $LibDir "detect.ps1")
. (Join-Path $LibDir "logger.ps1")

# ─── Version ──────────────────────────────────────────────
$DotfilesVersion = "unknown"
$versionFile = Join-Path $ScriptDir "VERSION"
if (Test-Path $versionFile) {
    $DotfilesVersion = (Get-Content $versionFile -Raw).Trim()
}

# ─── Banner ──────────────────────────────────────────────
Write-Host @"

  +-----------------------------------------------+
  |  dotfiles (Windows) v$DotfilesVersion         |
  +-----------------------------------------------+

"@ -ForegroundColor Magenta

# ─── Detección ──────────────────────────────────────────
$os = Get-DotfilesOS
$hw = Get-DotfilesHardware

Write-Host @"

  Hardware:
    CPU      : $($hw.CpuModel) ($($hw.CpuProfile), $($hw.CpuCores)c/$($hw.CpuThreads)t)
    RAM      : $($hw.RamGB) GB
    GPU      : $(if ($hw.GpuName) { $hw.GpuName } else { 'not detected' })
    Storage  : $(if ($hw.StorageType) { $hw.StorageType.ToUpper() } else { 'UNKNOWN' })
    Form     : $(if ($hw.IsLaptop) { 'Laptop' } else { 'Desktop' })

"@ -ForegroundColor Cyan

if ($DryRun) { $Script:DryRun = $true } else { $Script:DryRun = $false }
if ($Yes) { $Script:AssumeYes = $true } else { $Script:AssumeYes = $false }
$Script:LogFile = $LogFile
$Script:BackupDir = $BackupDir
$Script:Profile = $Profile
$Script:SkipSteps = $Skip
$Script:OnlySteps = $Only
$Script:InstallOllama = [bool]$InstallOllama

if ($Profile -eq "auto") {
    $Script:Profile = if ($hw.IsLaptop) { "laptop" } elseif ($hw.RamGB -ge 64) { "workstation" } else { "desktop" }
}

Log-Info "perfil: $Script:Profile"
Log-Info "dry-run: $Script:DryRun"

# ─── Helpers ────────────────────────────────────────────
function Test-StepSkipped {
    param([string]$Name)
    if ($Skip -contains $Name) { return $true }
    if ($Only.Count -gt 0 -and $Only -notcontains $Name) { return $true }
    return $false
}

function Test-IsAdmin {
    return $os.IsAdmin
}

function Confirm-Step {
    param([string]$Prompt, [string]$Default = "y")
    if ($Script:DryRun) { return $true }
    if ($Script:AssumeYes) { return $true }
    $resp = Read-Host "$Prompt [$(if ($Default -eq 'y') {'Y/n'} else {'y/N'})]"
    if ([string]::IsNullOrWhiteSpace($resp)) { $resp = $Default }
    return ($resp -match "^[yY]")
}

# ─── Steps ──────────────────────────────────────────────
$steps = @(
    "preflight",
    "backup",
    "windows-update",
    "core-packages",
    "shell",
    "terminal",
    "multiplexer",
    "dev-tools",
    "runtimes",
    "agent-tools",
    "windows-tweaks",
    "ssd",
    "ram",
    "network",
    "dotfiles-link",
    "post-install"
)

if (-not $Script:DryRun -and -not $Script:AssumeYes) {
    $resp = Read-Host "continuar con la instalación? [Y/n]"
    if ($resp -match "^[nN]") { exit 1 }
}

# ── 1. preflight ──
if (-not (Test-StepSkipped "preflight")) {
    Log-Section "Pre-flight"
    if ($os.IsWSL) {
        Log-Info "detectado WSL — algunas optimizaciones se saltarán"
    }
    if (-not (Test-NetConnection -ComputerName github.com -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        Log-Warn "sin conectividad a GitHub"
    }
    Log-Success "preflight OK"
}

# ── 2. backup ──
if (-not (Test-StepSkipped "backup")) {
    Log-Section "Backup"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        $files = @(
            "$env:USERPROFILE\.gitconfig",
            "$env:USERPROFILE\.gitignore_global",
            "$env:APPDATA\kitty\kitty.conf",
            "$env:LOCALAPPDATA\starship\config.toml",
            "$env:USERPROFILE\.zshrc",
            "$env:USERPROFILE\.tmux.conf"
        )
        foreach ($f in $files) {
            if (Test-Path $f) {
                $rel = $f.Replace($env:USERPROFILE, "")
                $dest = Join-Path $BackupDir $rel
                $destDir = Split-Path $dest -Parent
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                Copy-Item -Path $f -Destination $dest -Force
                Log-Success "backed up: $f"
            }
        }
    }
}

# ── 3. windows update ──
if (-not (Test-StepSkipped "windows-update")) {
    Log-Section "Windows update (informativo)"
    Log-Info "no instalamos actualizaciones del SO automáticamente"
    Log-Info "ejecuta 'Windows Update' desde Settings para actualizar"
}

# ── 4. core packages ──
if (-not (Test-StepSkipped "core-packages")) {
    Log-Section "Core packages (winget)"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $pkgs = @(
            "Git.Git",
            "Neovim.Neovim",
            "Microsoft.WindowsTerminal",
            "junegunn.fzf",
            "sharkdp.bat",
            "BurntSushi.ripgrep",
            "sharkdp.fd"
        )
        foreach ($p in $pkgs) {
            if (-not $DryRun) {
                $wingetOutput = winget install --id $p --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Log-Warn "winget: falló instalación de $p"
                    if ($wingetOutput.Trim()) { Log-Info "winget: $($wingetOutput.Trim())" }
                }
            }
            Log-Info "winget: $p"
        }
    }
    else {
        Log-Warn "winget no está disponible (¿Windows 11?)"
    }
}

# ── 5. shell ──
if (-not (Test-StepSkipped "shell")) {
    Log-Section "Shell (PowerShell + Starship)"
    if (-not (Get-Command starship -ErrorAction SilentlyContinue)) {
        if (-not $DryRun) {
            $wingetOutput = winget install --id Starship.Starship --silent 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                Log-Warn "winget: falló instalación de Starship.Starship"
                if ($wingetOutput.Trim()) { Log-Info "winget: $($wingetOutput.Trim())" }
            }
        }
    }
    # Linkear $PROFILE
    $profileSrc = Join-Path $ConfigDir "powershell\Microsoft.PowerShell_profile.ps1"
    $profileDst = $PROFILE
    if ([string]::IsNullOrWhiteSpace($profileDst)) {
        Log-Warn "`$PROFILE is empty — shell profile linking skipped"
    }
    elseif ((Test-Path $profileSrc) -and -not $DryRun) {
        $profileDir = Split-Path $profileDst -Parent
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        if (Test-Path $profileDst) { Copy-Item $profileDst "$profileDst.dotfiles-backup" -Force }
        New-Item -ItemType SymbolicLink -Path $profileDst -Target $profileSrc -Force | Out-Null
        Log-Success "PowerShell profile enlazado"
    }
}

# ── 6. terminal ──
if (-not (Test-StepSkipped "terminal")) {
    Log-Section "Windows Terminal"
    if (Get-Command wt -ErrorAction SilentlyContinue) {
        Log-Success "Windows Terminal: ya instalado"
    }
    else {
        if (-not $DryRun) {
            $wingetOutput = winget install --id Microsoft.WindowsTerminal --silent 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                Log-Warn "winget: falló instalación de Microsoft.WindowsTerminal"
                if ($wingetOutput.Trim()) { Log-Info "winget: $($wingetOutput.Trim())" }
            }
        }
    }
}

# ── 7. multiplexer ──
if (-not (Test-StepSkipped "multiplexer")) {
    Log-Section "tmux (via WSL si aplica, o nativo)"
    if ($os.IsWSL) {
        # tmux ya debería estar en el WSL setup
        Log-Info "WSL: tmux se instala vía setup.sh"
    }
    else {
        Log-Warn "tmux nativo Windows: usa WSL para mejor experiencia"
        if (-not $DryRun) {
            $wingetOutput = winget install --id Cygwin.Cygwin --silent 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                Log-Warn "winget: falló instalación de Cygwin.Cygwin"
                if ($wingetOutput.Trim()) { Log-Info "winget: $($wingetOutput.Trim())" }
            }
        }
    }
}

# ── 8. dev-tools ──
if (-not (Test-StepSkipped "dev-tools")) {
    Log-Section "Dev tools (scoop o winget)"
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        $pkgs = @("eza", "zoxide", "btop", "duf", "dust", "lazygit", "delta", "jq", "yq", "tldr")
        foreach ($p in $pkgs) {
            if (-not $DryRun) {
                scoop install $p 2>&1 | Out-Null
            }
        }
    }
    else {
        Log-Warn "scoop no detectado — algunas herramientas no se instalarán"
        Log-Info "instala scoop desde https://scoop.sh para dev tools completos"
    }
}

# ── 9. runtimes ──
if (-not (Test-StepSkipped "runtimes")) {
    Log-Section "Runtimes (Node, Python)"
    if (-not (Get-Command node -ErrorAction SilentlyContinue) -and -not $DryRun) {
        $wingetOutput = winget install --id OpenJS.NodeJS.LTS --silent 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Log-Warn "winget: falló instalación de OpenJS.NodeJS.LTS"
            if ($wingetOutput.Trim()) { Log-Info "winget: $($wingetOutput.Trim())" }
        }
    }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue) -and -not $DryRun) {
        Log-Info "instalando uv"
        $uvTmp = Join-Path $env:TEMP "uv-install.ps1"
        try {
            Invoke-WebRequest -Uri https://astral.sh/uv/install.ps1 -OutFile $uvTmp -UseBasicParsing
            & $uvTmp
        }
        catch {
            Log-Warn "falló descarga de uv"
        }
        finally {
            Remove-Item $uvTmp -ErrorAction SilentlyContinue
        }
    }
}

# ── 10. agent-tools ──
if (-not (Test-StepSkipped "agent-tools")) {
    Log-Section "Agent tools"
    if (Get-Command npm -ErrorAction SilentlyContinue -and -not $DryRun) {
        $claude = Get-Command claude -ErrorAction SilentlyContinue
        if (-not $claude) {
            npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
            Log-Success "Claude Code instalado"
        }
    }

    if ($InstallOllama -and -not $DryRun) {
        $wingetOutput = winget install --id Ollama.Ollama --silent 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Log-Warn "winget: falló instalación de Ollama.Ollama"
            if ($wingetOutput.Trim()) { Log-Info "winget: $($wingetOutput.Trim())" }
        }
    }

    $agentsDir = "$HOME\agents"
    foreach ($sub in @("workspaces", "scratch", "memory", "prompts", "tools", "templates")) {
        $p = Join-Path $agentsDir $sub
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}

# ── 11. windows-tweaks ──
if (-not (Test-StepSkipped "windows-tweaks")) {
    Log-Section "Windows tweaks"
    if (-not $DryRun) {
        # Desactivar hibernación (libera espacio en SSD)
        powercfg -h off 2>&1 | Out-Null
        Log-Info "hibernación desactivada (libera ~8GB)"

        # Power plan
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
        Log-Info "plan de energía: Alto rendimiento"

        # Desactivar telemetría no esencial (requiere admin)
        if (Test-IsAdmin) {
            $telemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $telemetryPath)) { New-Item -Path $telemetryPath -Force | Out-Null }
            Set-ItemProperty -Path $telemetryPath -Name AllowTelemetry -Value 0
            Log-Info "telemetría: mínima"
        }
        else {
            Log-Warn "telemetría: omitido (requiere administrador)"
        }
    }
}

# ── 12. SSD ──
if (-not (Test-StepSkipped "ssd")) {
    Log-Section "SSD optimization"
    if (-not $DryRun) {
        if (Test-IsAdmin) {
            # TRIM optimization
            fsutil behavior query DisableDeleteNotify
            Log-Info "TRIM status arriba (0=TRIM activo)"

            # Disable Superfetch/SysMain en SSD
            $sysmain = Get-Service -Name SysMain -ErrorAction SilentlyContinue
            if ($sysmain -and $sysmain.Status -eq "Running") {
                Stop-Service -Name SysMain -Force
                Set-Service -Name SysMain -StartupType Disabled
                Log-Info "SysMain (Superfetch) desactivado en SSD"
            }
        }
        else {
            Log-Warn "SSD: omitido (fsutil y SysMain requieren administrador)"
        }
    }
}

# ── 13. ram ──
if (-not (Test-StepSkipped "ram")) {
    Log-Section "RAM & virtual memory"
    if (-not $DryRun) {
        $totalGB = [math]::Round($hw.RamGB)
        if ($totalGB -lt 32) {
            Log-Info "RAM ${totalGB}GB: considera ZRAM via WSL o más RAM física"
        }
        else {
            Log-Info "RAM ${totalGB}GB: suficiente, sin swap adicional"
        }
        # Desactivar memory compression si molesta
        # (mac-style compression, opcional)
    }
}

# ── 14. network ──
if (-not (Test-StepSkipped "network")) {
    Log-Section "Network tuning"
    if (-not $DryRun) {
        if (Test-IsAdmin) {
            # TCP optimizations vía netsh
            netsh int tcp set global autotuninglevel=normal
            netsh int tcp set global chimney=disabled
            netsh int tcp set global rss=enabled
            Log-Success "TCP tuning aplicado"
        }
        else {
            Log-Warn "network: omitido (netsh requiere administrador)"
        }
    }
}

# ── 15. dotfiles-link ──
if (-not (Test-StepSkipped "dotfiles-link")) {
    Log-Section "Linking dotfiles"
    $links = @(
        @{ Src = (Join-Path $ConfigDir "git\.gitconfig"); Dst = "$env:USERPROFILE\.gitconfig" },
        @{ Src = (Join-Path $ConfigDir "git\.gitignore_global"); Dst = "$env:USERPROFILE\.gitignore_global" }
    )
    foreach ($l in $links) {
        if ((Test-Path $l.Src) -and -not $DryRun) {
            $dstDir = Split-Path $l.Dst -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            if (Test-Path $l.Dst) { Copy-Item $l.Dst "$l.Dst.dotfiles-backup" -Force }
            New-Item -ItemType SymbolicLink -Path $l.Dst -Target $l.Src -Force | Out-Null
            Log-Success "linked: $($l.Dst)"
        }
    }

    # Copiar bin/ a ~/bin
    $userBin = "$env:USERPROFILE\bin"
    if (-not $DryRun) {
        if (-not (Test-Path $userBin)) { New-Item -ItemType Directory -Path $userBin -Force | Out-Null }
        Get-ChildItem "$BinDir\*" -File | ForEach-Object {
            Copy-Item $_.FullName $userBin -Force
        }
    }
}

# ── 16. post-install ──
if (-not (Test-StepSkipped "post-install")) {
    Log-Section "Post-install verification"
    $checks = @(
        "git", "node", "npm", "nvm", "claude", "fzf", "rg", "fd", "bat", "eza",
        "btop", "neovim", "starship", "uv", "scoop", "winget"
    )
    $pass = 0
    $fail = 0
    foreach ($c in $checks) {
        if (Get-Command $c -ErrorAction SilentlyContinue) {
            Log-Success $c
            $pass++
        }
        else {
            Log-Warn "$c (no instalado)"
            $fail++
        }
    }
    Log-Info "verificación: $pass OK, $fail faltantes"
    Log-Info "log: $LogFile"
    Log-Info "backup: $BackupDir"
}

Log-Section "Instalación completada"
Write-Host @"
próximos pasos:
  1. reinicia PowerShell o ejecuta: . `$PROFILE
  2. abre Windows Terminal
  3. clona también el setup.sh en WSL (recomendado para tmux/Claude)
  4. autentícate con 'claude'
  5. lee docs/FAQ.md

"@ -ForegroundColor Cyan
