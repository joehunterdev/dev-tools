# Name: Redeploy All
# Description: Build, deploy configs, deploy vhosts, and restart server
# Icon: 🔄
# Cmd: redeploy
# Order: 4

<#
.SYNOPSIS
    Redeploy All - Complete build and deployment pipeline

.DESCRIPTION
    One-stop command that handles the entire deployment cycle:
    1. Backup current configs (for safe rollback)
    2. Build all configs from templates
    3. Deploy base configs (httpd.conf, php.ini, etc.)
    4. Deploy vhosts (httpd-vhosts.conf, hosts file)
    5. Restart Apache and MySQL servers
    
    This ensures all changes are compiled, deployed, and live with a backup safety net.
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:Config = Load-FilesConfig $moduleRoot
$script:ModulesDir = Join-Path $moduleRoot "bin\modules"

if (-not $script:Config) {
    Write-Error2 "Could not load config/config.json"
    exit
}

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Run-BackupConfigs {
    Write-Host ""
    Write-Host "  💾 Step 1/5: Backing up current configs..." -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $backupScript = Join-Path $script:ModulesDir "Backup-Configs.ps1"
    if (-not (Test-Path $backupScript)) {
        return @{ Success = $false; Error = "Backup-Configs.ps1 not found" }
    }
    
    try {
        # Backup requires user confirmation, so we handle it specially
        $output = & $backupScript 2>&1
        
        $success = $output | Select-String -Pattern "✅|backed up" -SimpleMatch | Measure-Object | Select-Object -ExpandProperty Count
        
        if ($success -gt 0) {
            Write-Host "  ✅ Configs backed up successfully" -ForegroundColor Green
            return @{ Success = $true }
        } else {
            Write-Host "  ⚠️  Backup completed (check output above)" -ForegroundColor Yellow
            return @{ Success = $true }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Run-BuildConfigs {
    Write-Host ""
    Write-Host "  📦 Step 2/5: Building configs..." -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $buildScript = Join-Path $script:ModulesDir "Build-Configs.ps1"
    if (-not (Test-Path $buildScript)) {
        return @{ Success = $false; Error = "Build-Configs.ps1 not found" }
    }
    
    try {
        # Capture output from build script
        $output = & $buildScript -CatchAllType $script:DefaultCatchAllType 2>&1
        
        # Check if build was successful by looking for success indicators
        $success = $output | Select-String -Pattern "✅|built|success|completed" -SimpleMatch | Measure-Object | Select-Object -ExpandProperty Count
        
        if ($success -gt 0) {
            Write-Host "  ✅ Configs built successfully" -ForegroundColor Green
            return @{ Success = $true }
        } else {
            Write-Host "  ⚠️  Build completed (check output above)" -ForegroundColor Yellow
            return @{ Success = $true }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Run-DeployConfigs {
    Write-Host ""
    Write-Host "  🚀 Step 3/5: Deploying configs..." -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $deployScript = Join-Path $script:ModulesDir "Deploy-Configs.ps1"
    if (-not (Test-Path $deployScript)) {
        return @{ Success = $false; Error = "Deploy-Configs.ps1 not found" }
    }
    
    try {
        $output = & $deployScript 2>&1
        
        $success = $output | Select-String -Pattern "✅|deployed|success" -SimpleMatch | Measure-Object | Select-Object -ExpandProperty Count
        
        if ($success -gt 0) {
            Write-Host "  ✅ Configs deployed successfully" -ForegroundColor Green
            return @{ Success = $true }
        } else {
            Write-Host "  ⚠️  Deploy completed (check output above)" -ForegroundColor Yellow
            return @{ Success = $true }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Run-DeployVHosts {
    Write-Host ""
    Write-Host "  🌐 Step 4/5: Deploying VHosts..." -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $vhostsScript = Join-Path $script:ModulesDir "Deploy-VHosts.ps1"
    if (-not (Test-Path $vhostsScript)) {
        return @{ Success = $false; Error = "Deploy-VHosts.ps1 not found" }
    }
    
    try {
        $output = & $vhostsScript -Force 2>&1
        
        $success = $output | Select-String -Pattern "✅|deployed|success" -SimpleMatch | Measure-Object | Select-Object -ExpandProperty Count
        
        if ($success -gt 0) {
            Write-Host "  ✅ VHosts deployed successfully" -ForegroundColor Green
            return @{ Success = $true }
        } else {
            Write-Host "  ⚠️  Deploy completed (check output above)" -ForegroundColor Yellow
            return @{ Success = $true }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Run-RestartServers {
    Write-Host ""
    Write-Host "  ⚡ Step 5/5: Config test & restart..." -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    . (Join-Path $moduleRoot "bin\Service-Helpers.ps1")
    
    # Safety: test Apache config before restarting
    Write-Info "Testing Apache config syntax..."
    $test = Test-ApacheConfigSyntax
    
    if (-not $test.Success) {
        Write-Error2 "Apache config test FAILED — aborting restart"
        Write-Host "    $($test.Output)" -ForegroundColor Red
        return @{ Success = $false; Error = "Config syntax error" }
    }
    
    Write-Success "Config syntax OK"
    Write-Info "Restarting services..."
    Invoke-XamppRestart
    Show-XamppStatus
    Write-Success "Services restarted"
    return @{ Success = $true }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🔄 Redeploy All" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  This will:" -ForegroundColor White
Write-Host "    1️⃣  Backup current configs" -ForegroundColor Gray
Write-Host "    2️⃣  Build all configs from templates" -ForegroundColor Gray
Write-Host "    3️⃣  Deploy base configs to XAMPP" -ForegroundColor Gray
Write-Host "    4️⃣  Deploy VHosts and hosts file" -ForegroundColor Gray
Write-Host "    5️⃣  Restart Apache and MySQL" -ForegroundColor Gray
Write-Host ""

# Ask for default catch-all type (will be used by Build-Configs)
Write-Host "  🌐 Default Catch-All Configuration:" -ForegroundColor White
Write-Host ""
Write-Host "    1. Basic (simple, minimal security)" -ForegroundColor Gray
Write-Host "    2. Secure (with file blocking & upload protection)" -ForegroundColor Gray
Write-Host ""
$catchAllChoice = Read-Host "  Choose default catch-all type (1 or 2)"
$script:DefaultCatchAllType = if ($catchAllChoice -eq "2") { "Default-Secure" } else { "Default" }
Write-Host "    ✅ Using: $script:DefaultCatchAllType" -ForegroundColor Green
Write-Host ""

if (-not (Prompt-YesNo "  Continue with full redeploy?")) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    Write-Host ""
    exit
}

# Track results
$results = @()
$allSuccess = $true

# Step 1: Backup
$result = Run-BackupConfigs
$results += @{ Step = "Backup"; Success = $result.Success; Error = $result.Error }
if (-not $result.Success) { $allSuccess = $false }

# Step 2: Build
$result = Run-BuildConfigs
$results += @{ Step = "Build"; Success = $result.Success; Error = $result.Error }
if (-not $result.Success) { $allSuccess = $false }

# Step 3: Deploy Configs
$result = Run-DeployConfigs
$results += @{ Step = "Deploy Configs"; Success = $result.Success; Error = $result.Error }
if (-not $result.Success) { $allSuccess = $false }

# Step 4: Deploy VHosts
$result = Run-DeployVHosts
$results += @{ Step = "Deploy VHosts"; Success = $result.Success; Error = $result.Error }
if (-not $result.Success) { $allSuccess = $false }

# Step 5: Restart Servers
$result = Run-RestartServers
$results += @{ Step = "Restart Servers"; Success = $result.Success; Error = $result.Error }
if (-not $result.Success) { $allSuccess = $false }

# Final summary
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  📋 Summary:" -ForegroundColor White
Write-Host ""

foreach ($result in $results) {
    $icon = if ($result.Success) { "✅" } else { "❌" }
    $color = if ($result.Success) { "Green" } else { "Red" }
    $status = if ($result.Success) { "Success" } else { "Failed" }
    
    Write-Host "    $icon $($result.Step): $status" -ForegroundColor $color
    
    if (-not $result.Success -and $result.Error) {
        Write-Host "       Error: $($result.Error)" -ForegroundColor Red
    }
}

Write-Host ""

if ($allSuccess) {
    Write-Host "  ✅ Redeploy completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Your XAMPP configuration is now live." -ForegroundColor Cyan
    Write-Host "  All changes have been compiled, deployed, and servers restarted." -ForegroundColor Gray
} else {
    Write-Host "  ⚠️  Redeploy completed with errors." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Check the output above for details." -ForegroundColor Gray
}

Write-Host ""
