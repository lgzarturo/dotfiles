# ─────────────────────────────────────────────
# PowerShell profile — dotfiles
# ─────────────────────────────────────────────

# PSReadLine settings (si está disponible)
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -EditMode Vi
    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineKeyHandler -Chord Ctrl+R -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Chord Ctrl+P -Function HistorySearchForward
}

# Starship prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# Aliases agenticos
$aliases = @{
    'll'           = 'Get-ChildItem -Force | Format-Table -AutoSize'
    'cat'          = 'Get-Content'
    'grep'         = 'Select-String'
    'top'          = 'btop'
    'lg'           = 'lazygit'
    'g'            = 'git'
    'vim'          = 'nvim'
    'claude-fresh' = 'tmux new-session -d -s claude; tmux send-keys -t claude "claude" Enter; tmux attach -t claude'
}
foreach ($k in $aliases.Keys) {
    Set-Alias -Name $k -Value $aliases[$k] -Scope Global -Force -ErrorAction SilentlyContinue
}

# Path
$env:Path = "$env:USERPROFILE\bin;$env:Path"

# Local overrides
if (Test-Path "$PSScriptRoot\profile.local.ps1") {
    . "$PSScriptRoot\profile.local.ps1"
}
