# Name: Deploy Configs
# Description: Deploy base configs to XAMPP
# Icon: 🚀
# Cmd: deploy-configs
# Order: 6

<#
.SYNOPSIS
    Deploy Configs - Deploy base configs from dist/ to XAMPP

.DESCRIPTION
    Deploys base configs only (excludes vhosts and hosts).
    Use 'deploy-vhosts' to deploy vhosts + hosts separately.
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
Write-Host "  🚀 Deploy Configs" -ForegroundColor Cyan
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

Write-Host "  Source:  $($script:DistDir)" -ForegroundColor Gray
Write-Host "  Target:  $xamppRoot" -ForegroundColor Gray
Write-Host ""

# Find files to deploy (exclude vhosts and hosts)
$filesToDeploy = @()
foreach ($mapping in $script:Config.deployMappings.mappings.PSObject.Properties) {
    $sourcePath = Join-Path $script:DistDir $mapping.Name
    $targetPath = $mapping.Value
    
    # Substitute environment variables in target path
    foreach ($key in $envData.Keys) {
        $targetPath = $targetPath -replace [regex]::Escape("{{$key}}"), $envData[$key]
    }
    
    # Skip vhosts - deployed separately
    if ($mapping.Name -match "httpd-vhosts\.conf$") {
        continue
    }
    
    if (Test-Path $sourcePath) {
        # Make target path absolute if it's relative to XAMPP_ROOT_DIR
        $absoluteTarget = $targetPath
        if (-not [System.IO.Path]::IsPathRooted($absoluteTarget)) {
            $absoluteTarget = Join-Path $xamppRoot $absoluteTarget
        }
        
        $filesToDeploy += @{
            Source = $sourcePath
            Target = $absoluteTarget
            Name = $mapping.Name
        }
    } else {
        Write-Host "  ⚠️  Skipping (not found): $($mapping.Name) at $sourcePath" -ForegroundColor Yellow
    }
}

if ($filesToDeploy.Count -eq 0) {
    Write-Error2 "No files found to deploy! Run 'build-configs' first."
    exit
}

Write-Host "  Files to deploy:" -ForegroundColor White
Write-Host ""
foreach ($file in $filesToDeploy) {
    Write-Host "    📄 $($file.Name)" -ForegroundColor Gray
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
        Write-Host "    ✅ $($file.Name)" -ForegroundColor Green
        $deployed++
    } catch {
        Write-Host "    ❌ $($file.Name) - $($_.Exception.Message)" -ForegroundColor Red
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
