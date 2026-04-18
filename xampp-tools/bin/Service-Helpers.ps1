# ============================================================
# Service-Helpers.ps1 - Shared XAMPP service management functions
# ============================================================
# Dot-source this from any module that needs to check, start,
# stop, or restart Apache/MySQL without triggering a UI.
#
# Usage:  . (Join-Path $moduleRoot "bin\Service-Helpers.ps1")
# ============================================================

# Resolve XAMPP root once (caller may have already loaded env)
if (-not $script:_ServiceHelpersLoaded) {

    $script:_ServiceHelpersLoaded = $true
    $_shModuleRoot = if ($moduleRoot) { $moduleRoot } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
    . (Join-Path $_shModuleRoot "bin\Common.ps1")

    $_shEnv = Load-EnvFile (Join-Path $_shModuleRoot ".env")
    $script:XamppRoot = if ($_shEnv['XAMPP_ROOT_DIR']) { $_shEnv['XAMPP_ROOT_DIR'] } else { "C:\xampp" }
}

# ── Status ────────────────────────────────────────────────────

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

# ── Start / Stop / Restart ────────────────────────────────────

function Invoke-XamppStart {
    param([switch]$Silent)
    $apacheStart = Join-Path $script:XamppRoot "apache_start.bat"
    $mysqlStart  = Join-Path $script:XamppRoot "mysql_start.bat"

    if (Test-Path $apacheStart) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$apacheStart`"" -WindowStyle Hidden
    } elseif (-not $Silent) { Write-Warning "apache_start.bat not found" }

    if (Test-Path $mysqlStart) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$mysqlStart`"" -WindowStyle Hidden
    } elseif (-not $Silent) { Write-Warning "mysql_start.bat not found" }

    Start-Sleep -Seconds 3
}

function Invoke-XamppStop {
    param([switch]$Silent)
    $apacheStop = Join-Path $script:XamppRoot "apache_stop.bat"
    $mysqlStop  = Join-Path $script:XamppRoot "mysql_stop.bat"

    if (Test-Path $apacheStop) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$apacheStop`"" -WindowStyle Hidden
        Start-Sleep -Seconds 1
    }
    if (Test-Path $mysqlStop) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$mysqlStop`"" -WindowStyle Hidden
        Start-Sleep -Seconds 1
    }

    # Fallback: force-kill if batch scripts didn't stop them
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

# ── Pre-flight checks ────────────────────────────────────────

function Assert-MySQLRunning {
    <# Returns $true if MySQL is running, offers to start if not. #>
    $status = Get-XamppStatus
    if ($status.MySQL) { return $true }

    Write-Warning2 "MySQL is not running"
    if (Prompt-YesNo "  Start MySQL now?") {
        $mysqlStart = Join-Path $script:XamppRoot "mysql_start.bat"
        if (Test-Path $mysqlStart) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$mysqlStart`"" -WindowStyle Hidden
            Start-Sleep -Seconds 3
        }
        $status = Get-XamppStatus
        if ($status.MySQL) {
            Write-Success "MySQL started"
            return $true
        }
        Write-Error2 "MySQL failed to start"
    }
    return $false
}

function Assert-ApacheRunning {
    <# Returns $true if Apache is running, offers to start if not. #>
    $status = Get-XamppStatus
    if ($status.Apache) { return $true }

    Write-Warning2 "Apache is not running"
    if (Prompt-YesNo "  Start Apache now?") {
        $apacheStart = Join-Path $script:XamppRoot "apache_start.bat"
        if (Test-Path $apacheStart) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$apacheStart`"" -WindowStyle Hidden
            Start-Sleep -Seconds 3
        }
        $status = Get-XamppStatus
        if ($status.Apache) {
            Write-Success "Apache started"
            return $true
        }
        Write-Error2 "Apache failed to start"
    }
    return $false
}

# ── Config test ───────────────────────────────────────────────

function Test-ApacheConfigSyntax {
    <# Runs httpd -t and returns @{ Success; Output } #>
    $httpd = Join-Path $script:XamppRoot "apache\bin\httpd.exe"
    if (-not (Test-Path $httpd)) {
        return @{ Success = $false; Output = "httpd.exe not found at $httpd" }
    }
    try {
        $output = & $httpd -t 2>&1 | Out-String
        return @{ Success = ($LASTEXITCODE -eq 0); Output = $output.Trim() }
    } catch {
        return @{ Success = $false; Output = $_.Exception.Message }
    }
}

function Open-XamppControlPanel {
    <# Opens XAMPP Control Panel GUI if not already running #>
    $already = Get-Process -Name "xampp-control" -ErrorAction SilentlyContinue
    if ($already) { return }
    $control = Join-Path $script:XamppRoot "xampp-control.exe"
    if (Test-Path $control) {
        Start-Process -FilePath $control
        Start-Sleep -Seconds 2
        Write-Info "XAMPP Control Panel opened"
    }
}

function Invoke-PostDeployRestart {
    <# Config test → show XAMPP GUI → stop → restart. Returns $true if all OK. #>
    Write-Info "Testing Apache config syntax..."
    $test = Test-ApacheConfigSyntax
    if (-not $test.Success) {
        Write-Error2 "Apache config test FAILED — services NOT restarted"
        Write-Host "    $($test.Output)" -ForegroundColor Red
        return $false
    }

    Write-Success "Apache config syntax OK"

    # Open XAMPP Control Panel so user can see what's happening
    Open-XamppControlPanel

    # Check what's currently running
    $status = Get-XamppStatus
    Show-XamppStatus

    $anyRunning = $status.Apache -or $status.MySQL

    if ($anyRunning) {
        if (Prompt-YesNo "  Stop running services, then restart?") {
            Write-Info "Stopping services..."
            Invoke-XamppStop
            Start-Sleep -Seconds 1
            Show-XamppStatus

            Write-Info "Starting services..."
            Invoke-XamppStart
            Show-XamppStatus
            Write-Success "Services restarted"
        }
    } else {
        if (Prompt-YesNo "  Start services now?") {
            Write-Info "Starting services..."
            Invoke-XamppStart
            Show-XamppStatus
            Write-Success "Services started"
        }
    }
    return $true
}
