# Name: Setup VS Code Shell Integration
# Description: Enable VS Code terminal shell integration for PowerShell (command decorations, CWD detection, IntelliSense)
# Cmd: shell-integration
# Order: 18
# Icon: 🔗

<#
.SYNOPSIS
    Setup VS Code Shell Integration for PowerShell

.DESCRIPTION
    Adds the VS Code shell integration hook to your PowerShell profile so that
    terminals launched from VS Code get rich features:
      - Command decorations (success/fail indicators in the gutter)
      - CWD detection (accurate current working directory)
      - Terminal IntelliSense (file, folder, command suggestions)
      - Sticky scroll, command navigation (Ctrl+Up/Down)
      - Quick fixes and run-recent-command history
      - Extended keyboard shortcuts (Ctrl+Space, Shift+Enter, etc.)

    Targets the CurrentUserAllHosts profile:
      $PROFILE  (Microsoft.PowerShell_profile.ps1)

    The injected line is guarded by a TERM_PROGRAM check so it only activates
    inside VS Code terminals — no impact on regular PowerShell sessions.

.NOTES
    Docs: https://code.visualstudio.com/docs/terminal/shell-integration
#>

$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$integrationLine = 'if ($env:TERM_PROGRAM -eq "vscode") { . "$(code --locate-shell-integration-path pwsh)" }'
$profilePath     = $PROFILE   # CurrentUserAllHosts: Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
$marker          = '# VS Code shell integration'

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  Setup VS Code Shell Integration" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Profile: $profilePath" -ForegroundColor Gray
Write-Host ""

# ── Check if already installed ───────────────────────────────
if (Test-Path $profilePath) {
    $existing = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($existing -match [regex]::Escape('locate-shell-integration-path')) {
        Write-Host "  [OK] Shell integration already present in profile" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Current entry:" -ForegroundColor DarkGray
        $existing -split "`n" | Where-Object { $_ -match 'shell-integration|TERM_PROGRAM' } | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }
        Write-Host ""

        if (-not (Prompt-YesNo "  Reinstall / overwrite the existing entry?")) {
            Write-Host ""
            exit
        }

        # Remove old entry before re-adding
        $lines = Get-Content $profilePath
        $lines = $lines | Where-Object { $_ -notmatch 'shell-integration|locate-shell-integration-path|# VS Code shell integration' }
        Set-Content $profilePath -Value $lines -Encoding UTF8
        Write-Host "    [..] Old entry removed" -ForegroundColor DarkGray
    }
}

# ── Ensure profile directory exists ──────────────────────────
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Host "    [..] Created profile directory: $profileDir" -ForegroundColor DarkGray
}

# ── Verify code.cmd is accessible ────────────────────────────
$codeExe = Get-Command "code" -ErrorAction SilentlyContinue
if (-not $codeExe) {
    Write-Warning2 "'code' is not in PATH — shell integration requires VS Code's 'code' command to be available"
    Write-Host "  Add VS Code to PATH via: Help > Shell Command > Install 'code' command in PATH" -ForegroundColor DarkGray
    Write-Host ""
    if (-not (Prompt-YesNo "  Continue anyway?")) { exit }
}

# ── Append to profile ─────────────────────────────────────────
$block = @"


$marker
$integrationLine
"@

Add-Content -Path $profilePath -Value $block -Encoding UTF8
Write-Host "    [OK] Shell integration hook added to profile" -ForegroundColor Green

# ── Show what was added ───────────────────────────────────────
Write-Host ""
Write-Host "  Added to $profilePath :" -ForegroundColor White
Write-Host "    $marker" -ForegroundColor DarkGray
Write-Host "    $integrationLine" -ForegroundColor DarkGray
Write-Host ""

# ── Reload profile in this session ───────────────────────────
Write-Host "  Reloading profile in current session..." -ForegroundColor White
try {
    . $profilePath
    Write-Host "    [OK] Profile reloaded" -ForegroundColor Green
} catch {
    Write-Warning2 "Profile reload failed: $($_.Exception.Message)"
    Write-Host "  Open a new terminal for changes to take effect." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Success "Shell integration enabled — open a new VS Code terminal to activate"
Write-Host ""
Write-Host "  Features now available:" -ForegroundColor White
Write-Host "    - Command decorations (success/fail gutter icons)" -ForegroundColor DarkGray
Write-Host "    - CWD detection (accurate directory in tab title)" -ForegroundColor DarkGray
Write-Host "    - Terminal IntelliSense (Ctrl+Space)" -ForegroundColor DarkGray
Write-Host "    - Sticky scroll, command navigation (Ctrl+Up / Ctrl+Down)" -ForegroundColor DarkGray
Write-Host "    - Run recent command (Ctrl+Alt+R)" -ForegroundColor DarkGray
Write-Host "    - Quick fixes and command history" -ForegroundColor DarkGray
Write-Host ""
