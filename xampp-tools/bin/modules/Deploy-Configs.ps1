# Name: Deploy Configs
# Description: Deploy all configs to XAMPP (base configs, vhosts, and hosts file)
# Cmd: deploy-configs
# Order: 6

<#
.SYNOPSIS
    Deploy Configs - Deploy all configs from dist/ to XAMPP

.DESCRIPTION
    Deploys all configs including:
    1. Base configs (httpd.conf, php.ini, etc.)
    2. VHosts configuration (httpd-vhosts.conf)
    3. Hosts file
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:Config = Load-FilesConfig $moduleRoot

if (-not $script:Config) {
    Write-Error2 "Could not load config/config.json"
    exit
}

$script:DistDir = Join-Path $moduleRoot $script:Config.templates.distDir

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  Deploy Configs" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check .env
if (-not (Test-Path $script:EnvFile)) {
    Write-Error2 ".env file not found!"
    exit
}

# Check dist dir
if (-not (Test-Path $script:DistDir)) {
    Write-Error2 "Dist directory not found! Run 'build-configs' first."
    exit
}

# Load env
$envData = Load-EnvFile $script:EnvFile
$xamppRoot = if ($envData['XAMPP_ROOT_DIR']) { $envData['XAMPP_ROOT_DIR'] } else { "C:\xampp" }
$docRoot = if ($envData['XAMPP_DOCUMENT_ROOT']) { $envData['XAMPP_DOCUMENT_ROOT'] } else { "C:\www" }

Write-Host "  Source:  $($script:DistDir)" -ForegroundColor Gray
Write-Host "  Target:  $xamppRoot" -ForegroundColor Gray
Write-Host ""

# Find files to deploy
$filesToDeploy = @()
foreach ($mapping in $script:Config.deployMappings.mappings.PSObject.Properties) {
    $sourcePath = Join-Path $script:DistDir $mapping.Name
    
    # Substitute environment variables in target path
    $targetValue = $mapping.Value
    $targetValue = $targetValue -replace '\{\{XAMPP_ROOT_DIR\}\}', $xamppRoot
    $targetValue = $targetValue -replace '\{\{XAMPP_DOCUMENT_ROOT\}\}', $docRoot
    
    # Check if target path is absolute or relative
    if ([System.IO.Path]::IsPathRooted($targetValue)) {
        $targetPath = $targetValue
    } else {
        $targetPath = Join-Path $xamppRoot $targetValue
    }
    
    if (Test-Path $sourcePath) {
        $filesToDeploy += @{
            Source = $sourcePath
            Target = $targetPath
            Name = $mapping.Name
        }
    }
}

if ($filesToDeploy.Count -eq 0) {
    Write-Error2 "No files found to deploy! Run 'build-configs' first."
    exit
}

Write-Host "  Files to deploy:" -ForegroundColor White
Write-Host ""
foreach ($file in $filesToDeploy) {
    Write-Host "    - $($file.Name)" -ForegroundColor Gray
}
Write-Host ""

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if (-not (Prompt-YesNo "  Deploy $($filesToDeploy.Count) config(s) to XAMPP?")) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "  Deploying..." -ForegroundColor Cyan
Write-Host ""

$deployed = 0
$failed = 0

foreach ($file in $filesToDeploy) {
    try {
        # Ensure target directory exists
        $targetDir = Split-Path $file.Target -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        Copy-Item -Path $file.Source -Destination $file.Target -Force
        Write-Host "    [OK] $($file.Name)" -ForegroundColor Green
        $deployed++
    } catch {
        Write-Host "    [FAIL] $($file.Name) - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($deployed -gt 0) {
    Write-Success "Deployed $deployed config(s) to XAMPP"
}

if ($failed -gt 0) {
    Write-Warning2 "$failed config(s) failed"
}

Write-Host ""
Write-Host "  Restart Apache/MySQL to apply changes" -ForegroundColor DarkGray
Write-Host ""
