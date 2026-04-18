# Name: Xampp Controller
# Description: Start/Stop/Restart XAMPP services and open the XAMPP control panel
# Cmd: xampp
# Order: 1

<#
.SYNOPSIS
    XAMPP Controller - Manage Apache & MySQL and open the XAMPP GUI
.DESCRIPTION
    Provides start, stop, restart, and status commands for XAMPP services.
    Exposes helper functions (Invoke-XamppStart, Invoke-XamppStop, etc.)
    that can be called by other modules before/after their own operations.
#>

# ============================================================
# PATHS
# ============================================================

$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

$envVars   = Load-EnvFile (Join-Path $moduleRoot ".env")
$xamppRoot = if ($envVars['XAMPP_ROOT_DIR']) { $envVars['XAMPP_ROOT_DIR'] } else { "C:\xampp" }

# ============================================================
# HELPER FUNCTIONS (importable by other modules)
# ============================================================

function Get-XamppStatus {
    $apache = Get-Process -Name "httpd"  -ErrorAction SilentlyContinue
    $mysql  = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    return @{ Apache = [bool]$apache; MySQL = [bool]$mysql }
}

function Show-XamppStatus {
    $s = Get-XamppStatus
    Write-Host ""
    Write-Host "  Current Status:" -ForegroundColor White
    Write-Host "    Apache : $(if ($s.Apache) { '🟢 Running' } else { '⚫ Stopped' })" -ForegroundColor Gray
    Write-Host "    MySQL  : $(if ($s.MySQL)  { '🟢 Running' } else { '⚫ Stopped' })" -ForegroundColor Gray
    Write-Host ""
}

function Invoke-XamppStart {
    param([switch]$Silent)
    $apacheStart = Join-Path $xamppRoot "apache_start.bat"
    $mysqlStart  = Join-Path $xamppRoot "mysql_start.bat"

    if (Test-Path $apacheStart) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$apacheStart`"" -WindowStyle Hidden
    } else {
        if (-not $Silent) { Write-Warning "apache_start.bat not found at $apacheStart" }
    }

    if (Test-Path $mysqlStart) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$mysqlStart`"" -WindowStyle Hidden
    } else {
        if (-not $Silent) { Write-Warning "mysql_start.bat not found at $mysqlStart" }
    }

    Start-Sleep -Seconds 3
}

function Invoke-XamppStop {
    param([switch]$Silent)
    $apacheStop = Join-Path $xamppRoot "apache_stop.bat"
    $mysqlStop  = Join-Path $xamppRoot "mysql_stop.bat"

    if (Test-Path $apacheStop) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$apacheStop`"" -WindowStyle Hidden
        Start-Sleep -Seconds 1
    }

    if (Test-Path $mysqlStop) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$mysqlStop`"" -WindowStyle Hidden
        Start-Sleep -Seconds 1
    }

    # Fallback: kill processes directly if batch scripts didn't work
    $apache = Get-Process -Name "httpd"  -ErrorAction SilentlyContinue
    $mysql  = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    if ($apache) { $apache | Stop-Process -Force -ErrorAction SilentlyContinue }
    if ($mysql)  { $mysql  | Stop-Process -Force -ErrorAction SilentlyContinue }

    Start-Sleep -Seconds 2
}

function Invoke-XamppRestart {
    Invoke-XamppStop
    Invoke-XamppStart
}

function Open-XamppControl {
    $control = Join-Path $xamppRoot "xampp-control.exe"
    if (Test-Path $control) {
        Start-Process -FilePath $control
        Write-Success "XAMPP Control Panel opened"
    } else {
        Write-Error2 "xampp-control.exe not found at $control"
    }
}

# ============================================================
# UI
# ============================================================

Show-Header
Write-Host "  XAMPP Controller" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray

Show-XamppStatus

Write-Host "    1) Start All" -ForegroundColor Gray
Write-Host "    2) Stop All" -ForegroundColor Gray
Write-Host "    3) Restart All" -ForegroundColor Gray
Write-Host "    4) Open XAMPP Control Panel" -ForegroundColor Gray
Write-Host "    5) Refresh Status" -ForegroundColor Gray
Write-Host ""
Write-Host "    0) Back" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "  Select option"

switch ($choice) {
    '1' {
        Write-Info "Starting Apache and MySQL..."
        Invoke-XamppStart
        Show-XamppStatus
        Write-Success "Services started"
    }
    '2' {
        Write-Info "Stopping Apache and MySQL..."
        Invoke-XamppStop
        Show-XamppStatus
        Write-Success "Services stopped"
    }
    '3' {
        Write-Info "Restarting Apache and MySQL..."
        Invoke-XamppRestart
        Show-XamppStatus
        Write-Success "Services restarted"
    }
    '4' {
        Open-XamppControl
    }
    '5' {
        Show-XamppStatus
    }
    '0' { return }
    default {
        Write-Warning "Invalid option"
    }
}
