# lib/logger.ps1 — logging con colores para Windows PowerShell

$Script:LogFile = $null
$Script:DryRun = $false

function Log-Trace { param([string]$Msg) Log-Write "TRACE" $Msg Cyan }
function Log-Debug { param([string]$Msg) Log-Write "DEBUG" $Msg Cyan }
function Log-Info { param([string]$Msg) Log-Write "INFO"  $Msg Blue }
function Log-Warn { param([string]$Msg) Log-Write "WARN"  $Msg Yellow }
function Log-Error { param([string]$Msg) Log-Write "ERROR" $Msg Red }
function Log-Success { param([string]$Msg) Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Log-Skip { param([string]$Msg) Write-Host "  ○ $Msg (skipped)" -ForegroundColor Yellow }

function Log-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══ $Title ═══" -ForegroundColor Magenta
    Write-Host ""
}

function Log-Write {
    param(
        [string]$Level,
        [string]$Msg,
        [string]$Color
    )
    $ts = Get-Date -Format "HH:mm:ss"
    $isoTs = Get-Date -Format "s"
    Write-Host "$Level [$ts] $Msg" -ForegroundColor $Color
    if ($Script:LogFile) {
        Add-Content -Path $Script:LogFile -Value "[$isoTs] $Level $Msg"
    }
}
