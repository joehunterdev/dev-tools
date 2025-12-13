# Name: Deploy SRP
# Description: Deploy SRP config and manage service
# Icon: 🔐
# Cmd: deploy-srp
# Order: 7
# Hidden: true

<#
.SYNOPSIS
    Deploy SRP - Deploy SRP config from dist/ and manage service

.DESCRIPTION
    Deploys Software Restriction Policy config:
    1. Validates SRP config exists in dist/
    2. Stops SRP service (Application Identity)
    3. Deploys dist/softwarepolicy/softwarepolicy.ini to Windows
    4. Restarts SRP service
    5. Logs any issues for future troubleshooting
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:Config = Load-FilesConfig $moduleRoot
$script:SrpConfigPath = "C:\Windows\SoftwarePolicy\softwarepolicy.ini"
$script:DistDir = Join-Path $moduleRoot $script:Config.templates.distDir
$script:BackupDir = Join-Path $moduleRoot "backups"
$script:SrpServiceName = "AppIDSvc"  # Application Identity service

if (-not $script:Config) {
    Write-Error2 "Could not load config/config.json"
    exit
}

# ============================================================
# FUNCTIONS
# ============================================================

function Test-AdminRights {
    <#
    .SYNOPSIS
        Check if running with administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SrpServiceStatus {
    <#
    .SYNOPSIS
        Get current status of SRP service
    #>
    try {
        $service = Get-Service -Name $script:SrpServiceName -ErrorAction Stop
        return @{
            Exists = $true
            Status = $service.Status
            StartType = $service.StartType
        }
    } catch {
        return @{
            Exists = $false
            Error = $_.Exception.Message
        }
    }
}

function Stop-SrpService {
    <#
    .SYNOPSIS
        Stop SRP service
    #>
    try {
        $service = Get-Service -Name $script:SrpServiceName -ErrorAction Stop
        if ($service.Status -eq "Running") {
            Stop-Service -Name $script:SrpServiceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
        return @{ Success = $true; Status = "Stopped" }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Start-SrpService {
    <#
    .SYNOPSIS
        Start SRP service
    #>
    try {
        $service = Get-Service -Name $script:SrpServiceName -ErrorAction Stop
        if ($service.Status -ne "Running") {
            Start-Service -Name $script:SrpServiceName -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
        return @{ Success = $true; Status = "Running" }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Deploy-SrpConfig {
    <#
    .SYNOPSIS
        Deploy SRP config from dist to Windows system
    #>
    param(
        [string]$SourcePath,
        [string]$TargetPath
    )
    
    try {
        # Ensure target directory exists
        $targetDir = Split-Path $TargetPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        Copy-Item -Path $SourcePath -Destination $TargetPath -Force
        return @{ Success = $true }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🔐 Deploy SRP Config" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check admin rights
if (-not (Test-AdminRights)) {
    Write-Error2 "Administrator rights required to deploy SRP!"
    Write-Host ""
    Write-Host "  Please run PowerShell as Administrator" -ForegroundColor DarkGray
    Write-Host ""
    exit
}

Write-Success "Running as Administrator"
Write-Host ""

# Check if SRP config exists in dist
$srpDistPath = Join-Path $script:DistDir "softwarepolicy\softwarepolicy.ini"
if (-not (Test-Path $srpDistPath)) {
    Write-Error2 "SRP config not found in dist!"
    Write-Host ""
    Write-Host "  Run 'build-srp' first to build the SRP config" -ForegroundColor DarkGray
    Write-Host ""
    exit
}

Write-Success "SRP config found in dist/"
Write-Host ""

# Step 1: Check SRP service status
Write-Host "  Step 1: Checking SRP service..." -ForegroundColor Yellow
Write-Host ""

$serviceStatus = Get-SrpServiceStatus
if (-not $serviceStatus.Exists) {
    Write-Error2 "SRP service not found: $($serviceStatus.Error)"
    Write-Host ""
    Write-Host "  Software Restriction Policy may not be installed" -ForegroundColor DarkGray
    Write-Host ""
    exit
}

Write-Success "SRP service found: $($serviceStatus.Status)"
Write-Host ""

# Step 2: Stop SRP service
Write-Host "  Step 2: Stopping SRP service..." -ForegroundColor Yellow
Write-Host ""

$stopResult = Stop-SrpService
if ($stopResult.Success) {
    Write-Success "SRP service stopped"
} else {
    Write-Error2 "Failed to stop SRP service: $($stopResult.Error)"
    Write-Host ""
    exit
}

Write-Host ""

# Step 3: Deploy config
Write-Host "  Step 3: Deploying SRP config..." -ForegroundColor Yellow
Write-Host ""

Write-Info "Source: dist/softwarepolicy/softwarepolicy.ini"
Write-Info "Target: $script:SrpConfigPath"
Write-Host ""

$deployResult = Deploy-SrpConfig -SourcePath $srpDistPath -TargetPath $script:SrpConfigPath
if ($deployResult.Success) {
    Write-Success "Config deployed successfully"
} else {
    Write-Error2 "Deployment failed: $($deployResult.Error)"
    
    # Log the error for future troubleshooting
    $today = Get-Date -Format "yyyy-MM-dd"
    $auditDir = Join-Path $script:BackupDir $today
    Write-AuditLog -Issue "Failed to deploy SRP config" `
                   -Apply "Deploy-SrpConfig $srpDistPath to $script:SrpConfigPath" `
                   -Result "Failed: $($deployResult.Error)" `
                   -LogDir $auditDir
    
    Write-Host ""
    exit
}

Write-Host ""

# Step 4: Restart SRP service
Write-Host "  Step 4: Restarting SRP service..." -ForegroundColor Yellow
Write-Host ""

$startResult = Start-SrpService
if ($startResult.Success) {
    Write-Success "SRP service restarted: $($startResult.Status)"
} else {
    Write-Warning2 "Warning: Could not restart SRP service: $($startResult.Error)"
    
    # Log the warning
    $today = Get-Date -Format "yyyy-MM-dd"
    $auditDir = Join-Path $script:BackupDir $today
    Write-AuditLog -Issue "Failed to restart SRP service" `
                   -Apply "Start-Service -Name $script:SrpServiceName" `
                   -Result "Failed: $($startResult.Error)" `
                   -LogDir $auditDir
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Success "SRP config deployed successfully"

Write-Host ""
Write-Host "  Summary:" -ForegroundColor DarkGray
Write-Host "    ✅ SRP service status: $($serviceStatus.Status)" -ForegroundColor DarkGray
Write-Host "    ✅ Config deployed to: $script:SrpConfigPath" -ForegroundColor DarkGray
if ($startResult.Success) {
    Write-Host "    ✅ Service restarted: $($startResult.Status)" -ForegroundColor DarkGray
}
Write-Host ""

