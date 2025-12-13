# Name: Services
# Description: Start/Stop Apache & MySQL
# Icon: 🔄
# Cmd: services
# Order: 2

<#
.SYNOPSIS
    Service Manager Module - Start/Stop XAMPP services
#>

function Show-ServiceStatus {
    $apache = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
    $mysql = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    
    Write-Host ""
    Write-Host "  Current Status:" -ForegroundColor White
    Write-Host "    Apache: $(if ($apache) { '🟢 Running' } else { '⚫ Stopped' })" -ForegroundColor Gray
    Write-Host "    MySQL:  $(if ($mysql) { '🟢 Running' } else { '⚫ Stopped' })" -ForegroundColor Gray
    Write-Host ""
}

# Get XAMPP root from .env
$envVars = Load-EnvFile $script:EnvFile
$xamppRoot = if ($envVars['XAMPP_ROOT_DIR']) { $envVars['XAMPP_ROOT_DIR'] } else { "C:\xampp" }
$apacheExe = Join-Path $xamppRoot "apache\bin\httpd.exe"
$mysqlExe = Join-Path $xamppRoot "mysql\bin\mysqld.exe"

Show-Header
Write-Host "  🔄 Service Manager" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray

Show-ServiceStatus

Write-Host "    1) ▶️  Start All" -ForegroundColor Gray
Write-Host "    2) ⏹️  Stop All" -ForegroundColor Gray
Write-Host "    3) 🔄 Restart All" -ForegroundColor Gray
Write-Host ""
Write-Host "    0) ← Back" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "  Select option"

switch ($choice) {
    '1' {
        Write-Info "Starting services..."
        # Start Apache
        if (Test-Path $apacheExe) { 
            & $apacheExe -k start 2>&1 | Out-Null
        }
        # Start MySQL
        if (Test-Path $mysqlExe) {
            & $mysqlExe --datadir="$xamppRoot\mysql\data" 2>&1 | Out-Null &
        }
        Start-Sleep -Seconds 3
        Show-ServiceStatus
        Write-Success "Services started"
    }
    '2' {
        Write-Info "Stopping services..."
        # Stop Apache
        if (Test-Path $apacheExe) { 
            & $apacheExe -k stop 2>&1 | Out-Null
        }
        # Stop MySQL
        $mysql = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
        if ($mysql) { $mysql | Stop-Process -Force }
        Start-Sleep -Seconds 2
        Show-ServiceStatus
        Write-Success "Services stopped"
    }
    '3' {
        Write-Info "Restarting services..."
        # Stop Apache
        if (Test-Path $apacheExe) { 
            & $apacheExe -k stop 2>&1 | Out-Null
        }
        # Stop MySQL
        $mysql = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
        if ($mysql) { $mysql | Stop-Process -Force }
        Start-Sleep -Seconds 2
        
        # Start Apache
        if (Test-Path $apacheExe) { 
            & $apacheExe -k start 2>&1 | Out-Null
        }
        # Start MySQL
        if (Test-Path $mysqlExe) {
            & $mysqlExe --datadir="$xamppRoot\mysql\data" 2>&1 | Out-Null &
        }
        Start-Sleep -Seconds 3
        Show-ServiceStatus
        Write-Success "Services restarted"
    }
}
