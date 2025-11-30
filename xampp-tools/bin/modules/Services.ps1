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
        $apacheStart = Join-Path $xamppRoot "apache_start.bat"
        $mysqlStart = Join-Path $xamppRoot "mysql_start.bat"
        if (Test-Path $apacheStart) { Start-Process -FilePath $apacheStart -WindowStyle Hidden }
        if (Test-Path $mysqlStart) { Start-Process -FilePath $mysqlStart -WindowStyle Hidden }
        Start-Sleep -Seconds 3
        Show-ServiceStatus
        Write-Success "Start commands sent"
    }
    '2' {
        Write-Info "Stopping services..."
        $apacheStop = Join-Path $xamppRoot "apache_stop.bat"
        $mysqlStop = Join-Path $xamppRoot "mysql_stop.bat"
        if (Test-Path $apacheStop) { Start-Process -FilePath $apacheStop -WindowStyle Hidden }
        if (Test-Path $mysqlStop) { Start-Process -FilePath $mysqlStop -WindowStyle Hidden }
        Start-Sleep -Seconds 2
        Show-ServiceStatus
        Write-Success "Services stopped"
    }
    '3' {
        Write-Info "Restarting services..."
        $apacheStop = Join-Path $xamppRoot "apache_stop.bat"
        $mysqlStop = Join-Path $xamppRoot "mysql_stop.bat"
        if (Test-Path $apacheStop) { Start-Process -FilePath $apacheStop -WindowStyle Hidden -Wait }
        if (Test-Path $mysqlStop) { Start-Process -FilePath $mysqlStop -WindowStyle Hidden -Wait }
        Start-Sleep -Seconds 2
        $apacheStart = Join-Path $xamppRoot "apache_start.bat"
        $mysqlStart = Join-Path $xamppRoot "mysql_start.bat"
        if (Test-Path $apacheStart) { Start-Process -FilePath $apacheStart -WindowStyle Hidden }
        if (Test-Path $mysqlStart) { Start-Process -FilePath $mysqlStart -WindowStyle Hidden }
        Start-Sleep -Seconds 3
        Show-ServiceStatus
        Write-Success "Services restarted"
    }
}
