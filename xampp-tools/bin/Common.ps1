# ============================================================
# Common.ps1 - Shared helper functions for XAMPP Tools
# ============================================================

function Show-Signature {
    param([string]$Color = "DarkCyan")
    
    # Use $script:BinDir set by Xampp-Tools.ps1, fallback to calculating from script location
    $binDir = if ($script:BinDir) { $script:BinDir } else { Split-Path -Parent $PSCommandPath }
    $signaturePath = Join-Path $binDir "signature-lg.txt"
    
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

