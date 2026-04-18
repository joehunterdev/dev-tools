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
. (Join-Path $moduleRoot "bin\Service-Helpers.ps1")

function Open-XamppControl {
    $control = Join-Path $script:XamppRoot "xampp-control.exe"
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
