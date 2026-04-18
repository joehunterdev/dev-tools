# ============================================================
# Common.ps1 - Shared helper functions for XAMPP Tools
# ============================================================

function Show-Signature {
    param([string]$Color = "DarkCyan")
    
    # Use $script:BinDir set by Xampp-Tools.ps1, fallback to calculating from script location
    $binDir = if ($script:BinDir) { $script:BinDir } else { Split-Path -Parent $PSCommandPath }
    $signaturePath = Join-Path $binDir "assets\signature-lg.txt"
    
    if (Test-Path $signaturePath) {
        $lines = Get-Content $signaturePath
        foreach ($line in $lines) {
            Write-Host $line -ForegroundColor $Color
        }
    }
}

function Show-Header {
    Clear-Host
    Show-Signature -Color "DarkCyan"
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                         XAMPP Tools                                              ║" -ForegroundColor Cyan
    Write-Host "║                            by Joe Hunter - github.com/joehunterdev                               ║" -ForegroundColor Cyan
    Write-Host "║                               'Slow is Smooth, Smooth is Fast'                                   ║" -ForegroundColor DarkGray
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Step {
    param([string]$Number, [string]$Title, [string]$Status = "pending")
    
    $icon = switch ($Status) {
        "done"    { "✅" }
        "current" { "👉" }
        "pending" { "⬜" }
        "error"   { "❌" }
        default   { "⬜" }
    }
    
    $color = switch ($Status) {
        "done"    { "Green" }
        "current" { "Yellow" }
        "pending" { "DarkGray" }
        "error"   { "Red" }
        default   { "White" }
    }
    
    Write-Host "  $icon Step $Number : $Title" -ForegroundColor $color
}

function Write-Info {
    param([string]$Message)
    Write-Host "     ℹ️  $Message" -ForegroundColor DarkGray
}

function Write-Success {
    param([string]$Message)
    Write-Host "     ✅ $Message" -ForegroundColor Green
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "     ❌ $Message" -ForegroundColor Red
}

function Write-Warning2 {
    param([string]$Message)
    Write-Host "     ⚠️  $Message" -ForegroundColor Yellow
}

function Prompt-YesNo {
    param([string]$Question, [bool]$Default = $true)
    
    $defaultText = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $response = Read-Host "     $Question $defaultText"
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    
    return $response -match '^[Yy]'
}

function Prompt-Continue {
    Write-Host ""
    Read-Host "     Press Enter to continue"
}

function Load-EnvFile {
    param([string]$Path)
    
    $vars = @{}
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                $vars[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    return $vars
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Load-FilesConfig {
    param([string]$ModuleRoot)
    
    $configPath = Join-Path $ModuleRoot "config\config.json"
    if (-not (Test-Path $configPath)) {
        return $null
    }
    
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        return $config
    } catch {
        return $null
    }
}

function Write-AuditLog {
    param(
        [string]$Issue,
        [string]$Apply,
        [string]$Result,
        [string]$LogDir
    )
    
    # Create log directory if needed
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    
    $logPath = Join-Path $LogDir "srp-audit.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $logEntry = @"
[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]
Issue: $Issue
Apply: $Apply
Result: $Result
---

"@
    
    Add-Content -Path $logPath -Value $logEntry -Force

    return $logPath
}

# ============================================================
# SYSTEM DETECTION
# ============================================================

function Get-WindowsPhpConfig {
    <# Detects OS arch, build, and installed VS C++ runtimes. Used by Build-Configs and Switch-PHP. #>
    $arch = if ([System.Environment]::Is64BitOperatingSystem) {
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    } else { 'x86' }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $osCaption = if ($os) { $os.Caption } else { "Unknown Windows" }
    $osBuild   = if ($os) { $os.BuildNumber } else { "?" }

    $redistributables = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' `
                        -ErrorAction SilentlyContinue |
                        Get-ItemProperty -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -match 'Visual C\+\+ \d{4}.*(Redistributable|Runtime)' } |
                        Select-Object DisplayName, DisplayVersion

    $runtimes = @()
    foreach ($r in $redistributables) {
        if ($r.DisplayName -match '2015|2017|2019') { $runtimes += 'vc15'; $runtimes += 'vs16' }
        if ($r.DisplayName -match '2022')            { $runtimes += 'vs17' }
    }
    $runtimes = $runtimes | Select-Object -Unique

    return [PSCustomObject]@{
        Arch        = $arch
        OS          = $osCaption
        BuildNumber = $osBuild
        Runtimes    = $runtimes
    }
}

function Show-WindowsPhpConfig {
    $cfg = Get-WindowsPhpConfig
    Write-Host "  System" -ForegroundColor White
    Write-Host "    OS      : $($cfg.OS) (build $($cfg.BuildNumber))" -ForegroundColor Gray
    Write-Host "    Arch    : $($cfg.Arch)" -ForegroundColor Gray
    if ($cfg.Runtimes.Count -gt 0) {
        Write-Host "    Runtime : $($cfg.Runtimes -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "    Runtime : None detected" -ForegroundColor Yellow
        Write-Host "      https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor DarkGray
    }
}