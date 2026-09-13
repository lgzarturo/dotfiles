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
    [switch]$EnableUnsafeAgentAliases,
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
$Script:EnableUnsafeAgentAliases = [bool]$EnableUnsafeAgentAliases

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

# ─── Step runner (lifecycle + tracking) ────────────────
$Script:StepNames   = [System.Collections.Generic.List[string]]::new()
$Script:StepStates  = [System.Collections.Generic.List[string]]::new()
$Script:StepHints   = [System.Collections.Generic.List[string]]::new()
$Script:StepCurrent = 0
$Script:TotalSteps  = 0

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Critical = "optional",
        [scriptblock]$Action
    )
    $Script:StepCurrent++
    $Script:StepNames.Add($Name)

    Write-Host ""
    Write-Host "$([char]0x1B)[1m[$($Script:StepCurrent)/$($Script:TotalSteps)]$([char]0x1B)[0m $Description" -ForegroundColor White

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $stepFailed = $false

    try {
        & $Action
    }
    catch {
        $stepFailed = $true
        Log-Error "$Description FALLÓ: $_"
    }

    $sw.Stop()
    $elapsed = $sw.Elapsed
    $elapsedFmt = "{0:mm\m {0:ss\s}" -f $elapsed

    if (-not $stepFailed) {
        $Script:StepStates.Add("ok")
        $Script:StepHints.Add("")
        Log-Success "$Description ($elapsedFmt)"
    }
    else {
        if ($Critical -eq "critical") {
            $Script:StepStates.Add("fatal")
            Log-Error "$Description FALLÓ (crítico)"
            Log-Hint "reintentar: .\setup.ps1 -Only $Name"
            Log-Hint "ver log: $LogFile"
            Log-Hint "ver soporte: docs\FAQ.md"
            exit 1
        }
        else {
            $Script:StepStates.Add("failed")
            $Script:StepHints.Add(".\setup.ps1 -Only $Name")
            Log-Warn "$Description falló (no crítico) — continuando"
            Log-Hint "reintentar: .\setup.ps1 -Only $Name"
            Log-Hint "ver log: $LogFile"
            Log-Hint "ver soporte: docs\FAQ.md"
        }
    }
}

function Show-StepSummary {
    Log-Section "Resumen de instalación"
    Write-Host ""
    Write-Host "  $($("─" * 25))  $($("─" * 10))" -ForegroundColor DarkGray
    Write-Host "  $('PASO'.PadRight(25))  $('ESTADO'.PadRight(10))"
    Write-Host "  $($("─" * 25))  $($("─" * 10))" -ForegroundColor DarkGray

    $ok = 0; $failedCount = 0
    for ($i = 0; $i -lt $Script:StepNames.Count; $i++) {
        $icon = switch ($Script:StepStates[$i]) {
            "ok"     { $ok++; "✓ OK" }
            "failed" { $failedCount++; "✗ FALLO" }
            "fatal"  { $failedCount++; "✗ FATAL" }
            "skipped" { "○ SKIP" }
        }
        $color = switch ($Script:StepStates[$i]) {
            "ok"     { "Green" }
            "failed" { "Yellow" }
            "fatal"  { "Red" }
            "skipped" { "Yellow" }
        }
        Write-Host "  $($Script:StepNames[$i].PadRight(25))  " -NoNewline
        Write-Host $icon -ForegroundColor $color
    }

    Write-Host ""
    Log-Info "pasos completados: $ok"
    if ($failedCount -gt 0) {
        Log-Warn "pasos fallidos: $failedCount — ejecuta .\setup.ps1 -Only <paso> para reintentar"
        for ($i = 0; $i -lt $Script:StepNames.Count; $i++) {
            if ($Script:StepStates[$i] -eq "failed" -or $Script:StepStates[$i] -eq "fatal") {
                Log-Hint "reintentar: .\setup.ps1 -Only $($Script:StepNames[$i])"
            }
        }
    }
    Log-Info "log: $LogFile"
    Log-Info "backup: $BackupDir"
}

function Install-WingetPackage {
    param([string]$Id)
    if ($Script:DryRun) {
        Log-Info "winget [dry-run]: $Id"
        return $true
    }

    # Verificar si ya está instalado (usando winget list en vez de parsear texto)
    $listOutput = winget list --id $Id --accept-source-agreements 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $listOutput -match $Id) {
        Log-Skip "$Id"
        return $true
    }

    $output = winget install --id $Id --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Log-Success "winget: $Id"
        return $true
    }
    Log-Warn "winget: falló instalación de $Id"
    if ($output.Trim()) { Log-Info "winget: $($output.Trim())" }
    return $false
}

# ─── Admin check ────────────────────────────────────────
$skipAdmin = @()
if (-not (Test-IsAdmin)) {
    Log-Warn "no se ejecuta como administrador — se saltarán pasos que requieren permisos elevados"
    $skipAdmin = @("windows-tweaks", "ssd", "network")
    foreach ($s in $skipAdmin) {
        Log-Hint "omitido (admin): $s"
    }
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
    "agent-aliases",
    "matrix-fetch",
    "windows-tweaks",
    "ssd",
    "ram",
    "network",
    "git-config",
    "dotfiles-link",
    "post-install"
)
$Script:TotalSteps = $steps.Count

if (-not $Script:DryRun -and -not $Script:AssumeYes) {
    $resp = Read-Host "continuar con la instalación? [Y/n]"
    if ($resp -match "^[nN]") { exit 1 }
}

# ── 1. preflight ──
if (-not (Test-StepSkipped "preflight")) {
    Invoke-Step -Name "preflight" -Description "Pre-flight" -Critical "critical" -Action {
        if ($os.IsWSL) {
            Log-Info "detectado WSL — algunas optimizaciones se saltarán"
        }
        if (-not (Test-NetConnection -ComputerName github.com -InformationLevel Quiet -WarningAction SilentlyContinue)) {
            Log-Warn "sin conectividad a GitHub"
            Log-Hint "verifica tu conexión de red o proxy"
        }
    }
}

# ── 2. backup ──
if (-not (Test-StepSkipped "backup")) {
    Invoke-Step -Name "backup" -Description "Backup" -Action {
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
}

# ── 3. windows update ──
if (-not (Test-StepSkipped "windows-update")) {
    Invoke-Step -Name "windows-update" -Description "Windows update (informativo)" -Action {
        Log-Info "no instalamos actualizaciones del SO automáticamente"
        Log-Info "ejecuta 'Windows Update' desde Settings para actualizar"
    }
}

# ── 4. core packages ──
if (-not (Test-StepSkipped "core-packages")) {
    Invoke-Step -Name "core-packages" -Description "Core packages (winget)" -Critical "critical" -Action {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Log-Info "actualizando fuentes de winget..."
            winget source update --silent 2>&1 | Out-Null
            $pkgs = @(
                "Git.Git",
                "Neovim.Neovim",
                "Microsoft.WindowsTerminal",
                "junegunn.fzf",
                "sharkdp.bat",
                "BurntSushi.ripgrep.MSVC",
                "sharkdp.fd"
            )
            foreach ($p in $pkgs) {
                Install-WingetPackage $p
            }
        }
        else {
            Log-Warn "winget no está disponible — instala App Installer desde Microsoft Store"
            Log-Hint "descarga: https://aka.ms/getwinget"
        }
    }
}

# ── 5. shell ──
if (-not (Test-StepSkipped "shell")) {
    Invoke-Step -Name "shell" -Description "Shell (PowerShell + Starship)" -Action {
        if (-not (Get-Command starship -ErrorAction SilentlyContinue)) {
            Install-WingetPackage "Starship.Starship"
        }
        $profileSrc = Join-Path $ConfigDir "powershell\Microsoft.PowerShell_profile.ps1"
        $profileDst = $PROFILE
        if ([string]::IsNullOrWhiteSpace($profileDst)) {
            Log-Warn "`$PROFILE is empty — shell profile linking skipped"
            Log-Hint "verifica tu instalación de PowerShell"
        }
        elseif ((Test-Path $profileSrc) -and -not $DryRun) {
            $profileDir = Split-Path $profileDst -Parent
            if ([string]::IsNullOrWhiteSpace($profileDir)) {
                Log-Warn "`$PROFILE no contiene directorio ('$profileDst') — enlace omitido"
            }
            else {
                if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
                if (Test-Path $profileDst) { Copy-Item $profileDst "$profileDst.dotfiles-backup" -Force }
                New-Item -ItemType SymbolicLink -Path $profileDst -Target $profileSrc -Force | Out-Null
                Log-Success "PowerShell profile enlazado"
            }
        }
    }
}

# ── 6. terminal ──
if (-not (Test-StepSkipped "terminal")) {
    Invoke-Step -Name "terminal" -Description "Windows Terminal" -Action {
        if (Get-Command wt -ErrorAction SilentlyContinue) {
            Log-Success "Windows Terminal: ya instalado"
        }
        else {
            Install-WingetPackage "Microsoft.WindowsTerminal"
        }
    }
}

# ── 7. multiplexer ──
if (-not (Test-StepSkipped "multiplexer")) {
    Invoke-Step -Name "multiplexer" -Description "tmux (via WSL si aplica, o nativo)" -Action {
        if ($os.IsWSL) {
            Log-Info "WSL: tmux se instala vía setup.sh"
        }
        else {
            Log-Warn "tmux nativo Windows: usa WSL para mejor experiencia"
            Log-Hint "instala WSL: wsl --install"
            Install-WingetPackage "Cygwin.Cygwin"
        }
    }
}

# ── 8. dev-tools ──
if (-not (Test-StepSkipped "dev-tools")) {
    Invoke-Step -Name "dev-tools" -Description "Dev tools (scoop o winget)" -Action {
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
            Log-Hint "instala scoop manualmente desde https://scoop.sh/ si realmente lo necesitas"
        }
    }
}

# ── 9. runtimes ──
if (-not (Test-StepSkipped "runtimes")) {
    Invoke-Step -Name "runtimes" -Description "Runtimes (Node, Python)" -Action {
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            Install-WingetPackage "OpenJS.NodeJS.LTS"
        }
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            if (-not (Install-WingetPackage "astral-sh.uv")) {
                Log-Warn "uv no disponible vía winget"
                Log-Hint "instálalo manualmente desde la documentación oficial"
            }
        }
    }
}

# ── 10. agent-tools ──
if (-not (Test-StepSkipped "agent-tools")) {
    Invoke-Step -Name "agent-tools" -Description "Agent tools" -Action {
        if (Get-Command npm -ErrorAction SilentlyContinue -and -not $DryRun) {
            $claude = Get-Command claude -ErrorAction SilentlyContinue
            if (-not $claude) {
                npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
                Log-Success "Claude Code instalado"
            }
            else {
                Log-Info "Claude Code ya instalado — actualizando"
                npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
            }
        }

        if ($InstallOllama) {
            Install-WingetPackage "Ollama.Ollama"
        }

        $agentsDir = "$HOME\agents"
        foreach ($sub in @("workspaces", "scratch", "memory", "prompts", "tools", "templates")) {
            $p = Join-Path $agentsDir $sub
            if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
        }
    }
}

# ── 10b. agent-aliases ──
if (-not (Test-StepSkipped "agent-aliases")) {
    Invoke-Step -Name "agent-aliases" -Description "Agent aliases (claude, agy, opencode, codex)" -Action {
        if (-not $Script:EnableUnsafeAgentAliases) {
            Log-Info "aliases inseguros deshabilitados por defecto"
            Log-Hint "usa -EnableUnsafeAgentAliases solo si realmente quieres habilitarlos"
            return
        }

        $profileDir   = Split-Path $PROFILE -Parent
        $profileLocal = Join-Path $profileDir "profile.local.ps1"
        $markerBegin  = "# ─── DOTFILES:AGENT-ALIASES BEGIN ──"
        $markerEnd    = "# ─── DOTFILES:AGENT-ALIASES END ────"

        $toolsMap = [ordered]@{
            "claude"       = "--allow-dangerously-skip-permissions"
            "agy"          = "--dangerously-skip-permissions"
            "cline"        = "--auto-approve true"
            "cursor"       = "agent --yolo"
            "cursor-agent" = "--yolo"
            "opencode"     = "--auto"
            "codex"        = "--dangerously-bypass-approvals-and-sandbox"
        }

        $foundTools = [System.Collections.Generic.List[string]]::new()
        foreach ($tool in $toolsMap.Keys) {
            if (Get-Command $tool -ErrorAction SilentlyContinue) {
                $foundTools.Add($tool)
                if ($DryRun) {
                    $flags = $toolsMap[$tool]
                    Log-Info "[dry-run] alias: function $tool { & <exe> $flags @args }"
                }
            }
            else {
                Log-Info "agent-alias: $tool no instalado — omitiendo"
            }
        }

        if ($DryRun) {
            if ($foundTools.Count -eq 0) { Log-Info "[dry-run] ninguna herramienta agentica detectada — sin aliases" }
        }
        elseif ($foundTools.Count -eq 0) {
            Log-Info "ninguna herramienta agentica detectada — sin aliases que configurar"
        }
        else {
            if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

            if (Test-Path $profileLocal) {
                $existingLines = Get-Content $profileLocal -ErrorAction SilentlyContinue
                $newLines = [System.Collections.Generic.List[string]]::new()
                $inBlock = $false
                foreach ($line in $existingLines) {
                    if ($line -match [regex]::Escape($markerBegin)) { $inBlock = $true; continue }
                    if ($line -match [regex]::Escape($markerEnd))   { $inBlock = $false; continue }
                    if (-not $inBlock) { $newLines.Add($line) }
                }
                $newLines | Set-Content $profileLocal -Encoding UTF8
            }

            $block = [System.Collections.Generic.List[string]]::new()
            $block.Add("")
            $block.Add($markerBegin)
            $block.Add("# Gestionado por dotfiles — no editar manualmente")
            foreach ($tool in $foundTools) {
                $flags = $toolsMap[$tool]
                $block.Add("function $tool {")
                $block.Add("    `$_exe = (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue).Source")
                $block.Add("    if (`$_exe) { & `$_exe $flags @args } else { Write-Error `"$tool no encontrado en PATH`" }")
                $block.Add("}")
            }
            $block.Add($markerEnd)

            Add-Content -Path $profileLocal -Value $block -Encoding UTF8
            Log-Success "agent aliases configurados en $profileLocal ($($foundTools.Count) alias)"
        }
    }
}

# ── 10c. matrix-fetch ──
if (-not (Test-StepSkipped "matrix-fetch")) {
    Invoke-Step -Name "matrix-fetch" -Description "Matrix fastfetch setup" -Action {
        $profileDir   = Split-Path $PROFILE -Parent
        $profileLocal = Join-Path $profileDir "profile.local.ps1"
        $markerBegin  = "# ─── DOTFILES:MATRIX-FETCH BEGIN ──"
        $markerEnd    = "# ─── DOTFILES:MATRIX-FETCH END ────"

        if ($DryRun) {
            Log-Info "[dry-run] configuraría matrix-fetch en $profileLocal"
            return
        }

        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

        if (Test-Path $profileLocal) {
            $existingLines = Get-Content $profileLocal -ErrorAction SilentlyContinue
            $newLines = [System.Collections.Generic.List[string]]::new()
            $inBlock = $false
            foreach ($line in $existingLines) {
                if ($line -match [regex]::Escape($markerBegin)) { $inBlock = $true; continue }
                if ($line -match [regex]::Escape($markerEnd))   { $inBlock = $false; continue }
                if (-not $inBlock) { $newLines.Add($line) }
            }
            $newLines | Set-Content $profileLocal -Encoding UTF8
        }

        $block = [System.Collections.Generic.List[string]]::new()
        $block.Add("")
        $block.Add($markerBegin)
        $block.Add("# Gestionado por dotfiles — no editar manualmente")
        $block.Add("function matrix-fetch {")
        $block.Add("    if (Get-Command bash -ErrorAction SilentlyContinue) { & bash `"$PSScriptRoot\bin\matrix-fetch`" @args }")
        $block.Add("}")
        $block.Add("Set-Alias -Name fetch -Value matrix-fetch -ErrorAction SilentlyContinue")
        $block.Add("if (`$Host.UI.RawUI -and -not (`$env:TERM -eq 'dumb')) { matrix-fetch }")
        $block.Add($markerEnd)

        Add-Content -Path $profileLocal -Value $block -Encoding UTF8
        Log-Success "matrix-fetch configurado en $profileLocal"
    }
}

# ── 11. windows-tweaks ──
if (-not (Test-StepSkipped "windows-tweaks")) {
    Invoke-Step -Name "windows-tweaks" -Description "Windows tweaks" -Action {
        if (-not $DryRun) {
            if (-not (Test-IsAdmin)) {
                throw "requiere administrador"
            }
            powercfg -h off 2>&1 | Out-Null
            Log-Info "hibernación desactivada (libera ~8GB)"

            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
            Log-Info "plan de energía: Alto rendimiento"

            $telemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $telemetryPath)) { New-Item -Path $telemetryPath -Force | Out-Null }
            Set-ItemProperty -Path $telemetryPath -Name AllowTelemetry -Value 0
            Log-Info "telemetría: mínima"
        }
    }
}

# ── 12. SSD ──
if (-not (Test-StepSkipped "ssd")) {
    Invoke-Step -Name "ssd" -Description "SSD optimization" -Action {
        if (-not $DryRun) {
            if (-not (Test-IsAdmin)) {
                throw "requiere administrador"
            }
            fsutil behavior query DisableDeleteNotify
            Log-Info "TRIM status arriba (0=TRIM activo)"

            $sysmain = Get-Service -Name SysMain -ErrorAction SilentlyContinue
            if ($sysmain -and $sysmain.Status -eq "Running") {
                Stop-Service -Name SysMain -Force
                Set-Service -Name SysMain -StartupType Disabled
                Log-Info "SysMain (Superfetch) desactivado en SSD"
            }
        }
    }
}

# ── 13. ram ──
if (-not (Test-StepSkipped "ram")) {
    Invoke-Step -Name "ram" -Description "RAM & virtual memory" -Action {
        if (-not $DryRun) {
            $totalGB = [math]::Round($hw.RamGB)
            if ($totalGB -lt 32) {
                Log-Info "RAM ${totalGB}GB: considera ZRAM via WSL o más RAM física"
                Log-Hint "más info: docs/HARDWARE.md"
            }
            else {
                Log-Info "RAM ${totalGB}GB: suficiente, sin swap adicional"
            }
        }
    }
}

# ── 14. network ──
if (-not (Test-StepSkipped "network")) {
    Invoke-Step -Name "network" -Description "Network tuning" -Action {
        if (-not $DryRun) {
            if (-not (Test-IsAdmin)) {
                throw "requiere administrador"
            }
            netsh int tcp set global autotuninglevel=normal
            netsh int tcp set global chimney=disabled
            netsh int tcp set global rss=enabled
            Log-Success "TCP tuning aplicado"
        }
    }
}

# ── 15. git-config ──
if (-not (Test-StepSkipped "git-config")) {
    Invoke-Step -Name "git-config" -Description "Git user config" -Action {
        $tmpl = Join-Path $ConfigDir "git\.gitconfig"

        $PLACEHOLDER_NAME  = "Tu Nombre"
        $PLACEHOLDER_EMAIL = "tu@email.com"

        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Log-Warn "git no disponible — se saltará configuración de usuario"
            Log-Hint "instala Git: winget install Git.Git"
        }
        elseif (-not (Test-Path $tmpl)) {
            Log-Warn "template $tmpl no encontrado — se saltará"
        }
        else {
            $tmplName  = & git config --file $tmpl user.name  2>$null
            $tmplEmail = & git config --file $tmpl user.email 2>$null

            $sysName  = & git config --global user.name  2>$null
            $sysEmail = & git config --global user.email 2>$null

            $defaultName = $null
            $defaultEmail = $null
            if ($sysName  -and $sysName  -ne $PLACEHOLDER_NAME)  { $defaultName  = $sysName  }
            elseif ($tmplName  -and $tmplName  -ne $PLACEHOLDER_NAME)  { $defaultName  = $tmplName  }
            if ($sysEmail -and $sysEmail -ne $PLACEHOLDER_EMAIL) { $defaultEmail = $sysEmail }
            elseif ($tmplEmail -and $tmplEmail -ne $PLACEHOLDER_EMAIL) { $defaultEmail = $tmplEmail }

            $gitName = $null; $gitEmail = $null

            if ($Script:AssumeYes) {
                if ($defaultName -and $defaultEmail) {
                    Log-Info "git user: $defaultName <$defaultEmail> (detectado, sin prompt)"
                    $gitName  = $defaultName
                    $gitEmail = $defaultEmail
                }
                else {
                    Log-Warn "git-config: -Yes activo pero no hay valores válidos; configura git manualmente"
                    Log-Hint "edita: $tmpl"
                }
            }
            else {
                $prompt = if ($defaultName)  { "  Git name  [$defaultName]"  } else { "  Git name"  }
                $gitName = Read-Host $prompt
                if ([string]::IsNullOrWhiteSpace($gitName))  { $gitName  = $defaultName  }

                $prompt = if ($defaultEmail) { "  Git email [$defaultEmail]" } else { "  Git email" }
                $gitEmail = Read-Host $prompt
                if ([string]::IsNullOrWhiteSpace($gitEmail)) { $gitEmail = $defaultEmail }
            }

            if ($gitName -and $gitEmail) {
                if ($Script:DryRun) {
                    Log-Info "[dry-run] git config user.name  = $gitName"
                    Log-Info "[dry-run] git config user.email = $gitEmail"
                }
                else {
                    & git config --file $tmpl user.name  "$gitName"
                    & git config --file $tmpl user.email "$gitEmail"
                    Log-Success "git user: $gitName <$gitEmail>"
                }
            }
            else {
                Log-Warn "git user config incompleto — edita $tmpl manualmente"
                Log-Hint "edita: $tmpl"
            }
        }
    }
}

# ── 16. dotfiles-link ──
if (-not (Test-StepSkipped "dotfiles-link")) {
    Invoke-Step -Name "dotfiles-link" -Description "Linking dotfiles" -Critical "critical" -Action {
        $links = @(
            @{ Src = (Join-Path $ConfigDir "git\.gitconfig"); Dst = "$env:USERPROFILE\.gitconfig" },
            @{ Src = (Join-Path $ConfigDir "git\.gitignore_global"); Dst = "$env:USERPROFILE\.gitignore_global" }
        )
        foreach ($l in $links) {
            if ((Test-Path $l.Src) -and -not $DryRun) {
                $dstDir = Split-Path $l.Dst -Parent
                if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
                if (Test-Path $l.Dst) { Copy-Item $l.Dst "$($l.Dst).dotfiles-backup" -Force }
                New-Item -ItemType SymbolicLink -Path $l.Dst -Target $l.Src -Force | Out-Null
                Log-Success "linked: $($l.Dst)"
            }
        }

        $userBin = "$env:USERPROFILE\bin"
        if (-not $DryRun) {
            if (-not (Test-Path $userBin)) { New-Item -ItemType Directory -Path $userBin -Force | Out-Null }
            Get-ChildItem "$BinDir\*" -File | ForEach-Object {
                Copy-Item $_.FullName $userBin -Force
            }
        }
    }
}

# ── 17. post-install ──
if (-not (Test-StepSkipped "post-install")) {
    Invoke-Step -Name "post-install" -Description "Post-install verification" -Action {
        $checks = @(
            @{ Name = "git";      Cmd = "git" },
            @{ Name = "node";     Cmd = "node" },
            @{ Name = "npm";      Cmd = "npm" },
            @{ Name = "claude";   Cmd = "claude" },
            @{ Name = "fzf";      Cmd = "fzf" },
            @{ Name = "ripgrep";  Cmd = "rg" },
            @{ Name = "fd";       Cmd = "fd" },
            @{ Name = "bat";      Cmd = "bat" },
            @{ Name = "eza";      Cmd = "eza" },
            @{ Name = "btop";     Cmd = "btop" },
            @{ Name = "neovim";   Cmd = "nvim" },
            @{ Name = "starship"; Cmd = "starship" },
            @{ Name = "uv";       Cmd = "uv" },
            @{ Name = "scoop";    Cmd = "scoop" },
            @{ Name = "winget";   Cmd = "winget" }
        )
        $pass = 0; $fail = 0
        foreach ($c in $checks) {
            if (Get-Command $c.Cmd -ErrorAction SilentlyContinue) {
                Log-Success $c.Name
                $pass++
            }
            else {
                Log-Warn "$($c.Name) (no instalado)"
                $fail++
            }
        }
        Log-Info "verificación: $pass OK, $fail faltantes"
    }
}

# ─── Summary ────────────────────────────────────────────
Show-StepSummary

Write-Host @"

próximos pasos:
  1. reinicia PowerShell o ejecuta: . `$PROFILE
  2. abre Windows Terminal
  3. clona también el setup.sh en WSL (recomendado para tmux/Claude)
  4. autentícate con 'claude'
  5. lee docs/FAQ.md

"@ -ForegroundColor Cyan
