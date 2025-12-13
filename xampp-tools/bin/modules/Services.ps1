# Name: Services
# Description: Start/Stop Apache & MySQL
# Cmd: services
# Order: 2

<#
.SYNOPSIS
    Service Manager Module - Start/Stop XAMPP services using native batch scripts
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

Show-Header
Write-Host "  Service Manager" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray

Show-ServiceStatus

Write-Host "    1) Start All" -ForegroundColor Gray
Write-Host "    2) Stop All" -ForegroundColor Gray
Write-Host "    3) Restart All" -ForegroundColor Gray
Write-Host ""
Write-Host "    0) Back" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "  Select option"

switch ($choice) {
    '1' {
        Write-Info "Starting services..."
        # Use XAMPP's native batch scripts
        $apacheStart = Join-Path $xamppRoot "apache_start.bat"
        $mysqlStart = Join-Path $xamppRoot "mysql_start.bat"
        
        if (Test-Path $apacheStart) { 
            & cmd /c $apacheStart 2>&1 | Out-Null &
        }
        if (Test-Path $mysqlStart) { 
            & cmd /c $mysqlStart 2>&1 | Out-Null &
        }
        Start-Sleep -Seconds 3
        Show-ServiceStatus
        Write-Success "Services started"
    }
    '2' {
        Write-Info "Stopping services..."
        # Stop Apache and MySQL processes
        $apache = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
        if ($apache) { $apache | Stop-Process -Force }
        
        $mysql = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
        if ($mysql) { $mysql | Stop-Process -Force }
        
        Start-Sleep -Seconds 2
        Show-ServiceStatus
        Write-Success "Services stopped"
    }
    '3' {
        Write-Info "Restarting services..."
        # Stop services
        $apache = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
        if ($apache) { $apache | Stop-Process -Force }
        
        $mysql = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
        if ($mysql) { $mysql | Stop-Process -Force }
        
        Start-Sleep -Seconds 2
        
        # Start services using XAMPP batch scripts
        $apacheStart = Join-Path $xamppRoot "apache_start.bat"
        $mysqlStart = Join-Path $xamppRoot "mysql_start.bat"
        
        if (Test-Path $apacheStart) { 
            & cmd /c $apacheStart 2>&1 | Out-Null &
        }
        if (Test-Path $mysqlStart) { 
            & cmd /c $mysqlStart 2>&1 | Out-Null &
        }
        
        Start-Sleep -Seconds 3
        Show-ServiceStatus
        Write-Success "Services restarted"
    }
}
