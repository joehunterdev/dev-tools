# Name: Kill Services
# Description: Force kill Apache and MySQL processes
# Icon: 🔪
# Cmd: kill
# Order: 15
# Hidden: false

<#
.SYNOPSIS
    Kill Services - Force stop Apache and MySQL processes

.DESCRIPTION
    Forcefully terminates Apache and MySQL processes:
    - Kills all httpd.exe processes (Apache)
    - Kills all mysqld.exe processes (MySQL)
    - Frees up ports 80, 443, 3306, 8080
    - Useful when XAMPP Control Panel can't stop services
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:Services = @{
    "apache" = @{
        Name = "Apache"
        ProcessName = "httpd"
        Icon = "🌐"
        Ports = @(80, 443, 8080)
        Color = "Cyan"
    }
    "mysql" = @{
        Name = "MySQL"
        ProcessName = "mysqld"
        Icon = "🗄️"
        Ports = @(3306)
        Color = "Yellow"
    }
}

# ============================================================
# FUNCTIONS
# ============================================================

function Get-ProcessesByName {
    param([string]$ProcessName)
    
    return Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
}

function Get-PortProcesses {
    param([int]$Port)
    
    $connections = netstat -ano | Select-String ":$Port "
    $pids = @()
    
    foreach ($line in $connections) {
        if ($line -match '\s+(\d+)\s*$') {
            $pids += $matches[1]
        }
    }
    
    return $pids | Select-Object -Unique
}

function Stop-ServiceProcesses {
    param(
        [string]$ServiceKey,
        [switch]$Force
    )
    
    $service = $script:Services[$ServiceKey]
    $processes = Get-ProcessesByName -ProcessName $service.ProcessName
    
    if (-not $processes) {
        Write-Info "$($service.Icon) $($service.Name): No processes running"
        return 0
    }
    
    $count = ($processes | Measure-Object).Count
    
    Write-Host "  $($service.Icon) $($service.Name): " -NoNewline -ForegroundColor $service.Color
    Write-Host "Found $count process(es)" -ForegroundColor White
    
    foreach ($proc in $processes) {
        try {
            Write-Host "    • Killing PID $($proc.Id)... " -NoNewline -ForegroundColor Gray
            
            if ($Force) {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            } else {
                $proc.Kill()
            }
            
            Write-Host "✓" -ForegroundColor Green
        } catch {
            Write-Host "✗ $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Wait and verify
    Start-Sleep -Seconds 1
    $remaining = Get-ProcessesByName -ProcessName $service.ProcessName
    
    if ($remaining) {
        Write-Warning "    Some processes still running"
        return ($remaining | Measure-Object).Count
    } else {
        Write-Success "  $($service.Icon) $($service.Name) stopped"
        return 0
    }
}

function Show-PortStatus {
    Write-Host ""
    Write-Host "  Port Status:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    foreach ($svc in $script:Services.Values) {
        foreach ($port in $svc.Ports) {
            $pids = Get-PortProcesses -Port $port
            
            if ($pids) {
                Write-Host "  Port $port : " -NoNewline -ForegroundColor White
                Write-Host "IN USE " -NoNewline -ForegroundColor Red
                Write-Host "(PIDs: $($pids -join ', '))" -ForegroundColor Gray
            } else {
                Write-Host "  Port $port : " -NoNewline -ForegroundColor White
                Write-Host "FREE" -ForegroundColor Green
            }
        }
    }
}

function Show-ServiceStatus {
    Write-Host ""
    Write-Host "  Service Status:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    foreach ($svc in $script:Services.Values) {
        $processes = Get-ProcessesByName -ProcessName $svc.ProcessName
        
        if ($processes) {
            $count = ($processes | Measure-Object).Count
            Write-Host "  $($svc.Icon) $($svc.Name): " -NoNewline -ForegroundColor $svc.Color
            Write-Host "RUNNING " -NoNewline -ForegroundColor Green
            Write-Host "($count process(es))" -ForegroundColor Gray
        } else {
            Write-Host "  $($svc.Icon) $($svc.Name): " -NoNewline -ForegroundColor $svc.Color
            Write-Host "STOPPED" -ForegroundColor DarkGray
        }
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🔪 Kill Services" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Show current status
Show-ServiceStatus
Show-PortStatus

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Menu
Write-Host "  Options:" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  1. Kill Apache only" -ForegroundColor Gray
Write-Host "  2. Kill MySQL only" -ForegroundColor Gray
Write-Host "  3. Kill both Apache and MySQL" -ForegroundColor Gray
Write-Host "  4. Kill all processes on specific port" -ForegroundColor Gray
Write-Host "  5. Refresh status" -ForegroundColor Gray
Write-Host "  6. Exit" -ForegroundColor Gray
Write-Host ""

$choice = (Read-Host "  Select option (1-6)").Trim()

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

switch ($choice) {
    "1" {
        Write-Host "  Killing Apache..." -ForegroundColor White
        Write-Host ""
        Stop-ServiceProcesses -ServiceKey "apache" -Force
    }
    "2" {
        Write-Host "  Killing MySQL..." -ForegroundColor White
        Write-Host ""
        Stop-ServiceProcesses -ServiceKey "mysql" -Force
    }
    "3" {
        Write-Host "  Killing all services..." -ForegroundColor White
        Write-Host ""
        Stop-ServiceProcesses -ServiceKey "apache" -Force
        Write-Host ""
        Stop-ServiceProcesses -ServiceKey "mysql" -Force
    }
    "4" {
        Write-Host "  Enter port number:" -ForegroundColor White
        $port = (Read-Host "  > ").Trim()
        
        if ($port -match '^\d+$') {
            Write-Host ""
            $pids = Get-PortProcesses -Port $port
            
            if ($pids) {
                Write-Host "  Processes using port $port" -ForegroundColor Yellow
                Write-Host ""
                
                foreach ($pid in $pids) {
                    try {
                        $proc = Get-Process -Id $pid -ErrorAction Stop
                        Write-Host "    • $($proc.ProcessName) (PID: $pid) " -NoNewline -ForegroundColor Gray
                        
                        Stop-Process -Id $pid -Force -ErrorAction Stop
                        Write-Host "✓ Killed" -ForegroundColor Green
                    } catch {
                        Write-Host "✗ Error" -ForegroundColor Red
                    }
                }
            } else {
                Write-Info "No processes found on port $port"
            }
        } else {
            Write-Error2 "Invalid port number"
        }
    }
    "5" {
        Write-Host "  Refreshing..." -ForegroundColor White
        Show-ServiceStatus
        Show-PortStatus
    }
    "6" {
        Write-Info "Exiting"
        exit
    }
    default {
        Write-Error2 "Invalid option"
        exit
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Show final status
Write-Host "  Final Status:" -ForegroundColor White
Write-Host ""
Show-ServiceStatus
Show-PortStatus

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
