# Name: Backup Configs
# Description: Backup XAMPP config files
# Icon: 💾
# Cmd: backup-configs
# Order: 8

<#
.SYNOPSIS
    Backup XAMPP configuration files with folder structure
#>

# Get the module root
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backupDir = Join-Path $moduleRoot "backups"
$configFile = Join-Path $moduleRoot "config\config.json"

# Load env
$envFile = Join-Path $moduleRoot ".env"
$envVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $envVars[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
}
$xamppRoot = if ($envVars['XAMPP_ROOT_DIR']) { $envVars['XAMPP_ROOT_DIR'] } else { "C:\xampp" }

Show-Header
Write-Host "  💾 Backup Config" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Load config files from JSON
if (-not (Test-Path $configFile)) {
    Write-Error2 "Config file not found: config\config.json"
    return
}

$backupConfig = Get-Content $configFile -Raw | ConvertFrom-Json
$configFiles = @()

foreach ($file in $backupConfig.backups.files) {
    $sourcePath = if ($file.absolute) { 
        $file.source 
    } else { 
        Join-Path $xamppRoot $file.source 
    }
    $configFiles += @{ 
        Source = $sourcePath
        Target = $file.target 
    }
}

Write-Host "  Files to backup:" -ForegroundColor White
Write-Host ""

$availableFiles = @()
foreach ($cfg in $configFiles) {
    $exists = Test-Path $cfg.Source
    $icon = if ($exists) { "✅" } else { "⚫" }
    $color = if ($exists) { "Green" } else { "DarkGray" }
    Write-Host "    $icon $($cfg.Target)" -ForegroundColor $color
    if ($exists) { $availableFiles += $cfg }
}

Write-Host ""
Write-Host "  Found $($availableFiles.Count)/$($configFiles.Count) files" -ForegroundColor DarkGray
Write-Host ""

if ($availableFiles.Count -eq 0) {
    Write-Warning2 "No config files found to backup"
    return
}

if (Prompt-YesNo "Create backup?") {
    # Create daily backup folder
    $today = Get-Date -Format "yyyy-MM-dd"
    $backupDir = Join-Path $moduleRoot "backups\$today"
    $configDir = Join-Path $backupDir "configs"
    
    # Create backup directory
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    Write-Host ""
    Write-Info "Backing up to: backups\$today\configs\"
    
    $backedUp = 0
    foreach ($cfg in $availableFiles) {
        $targetPath = Join-Path $configDir $cfg.Target
        $targetDir = Split-Path $targetPath -Parent
        
        # Create folder structure
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        try {
            Copy-Item $cfg.Source $targetPath -Force
            $backedUp++
            Write-Host "    ✅ $($cfg.Target)" -ForegroundColor Green
        } catch {
            Write-Host "    ❌ $($cfg.Target) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    
    if ($backedUp -gt 0) {
        Write-Host ""
        Write-Success "$backedUp config(s) backed up"
        Write-Host "       Location: backups\$today\configs\" -ForegroundColor DarkGray
    } else {
        Write-Warning2 "No files were backed up"
        if (Test-Path $configDir) { Remove-Item $configDir -Recurse -Force }
    }
}

# Show existing backups
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Recent backups:" -ForegroundColor White
Write-Host ""

$backupBaseDir = Join-Path $moduleRoot "backups"
if (Test-Path $backupBaseDir) {
    $backupDays = Get-ChildItem $backupBaseDir -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object Name -Descending | Select-Object -First 5
    if ($backupDays) {
        foreach ($day in $backupDays) {
            $configPath = Join-Path $day.FullName "configs"
            $hasConfigs = Test-Path $configPath
            $icon = if ($hasConfigs) { "📁" } else { "📂" }
            $status = if ($hasConfigs) { "configs ✓" } else { "" }
            Write-Host "    $icon $($day.Name) $status" -ForegroundColor Gray
        }
    } else {
        Write-Host "    No backups found" -ForegroundColor DarkGray
    }
} else {
    Write-Host "    No backups directory yet" -ForegroundColor DarkGray
}

Write-Host ""
