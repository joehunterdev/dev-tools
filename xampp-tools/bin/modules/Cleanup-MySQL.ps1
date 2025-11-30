# Name: Cleanup Orphaned
# Description: Remove a specific orphaned database folder
# Icon: 🧹
# Cmd: cleanup-orphaned
# Order: 11

<#
.SYNOPSIS
    MySQL Cleanup - Remove a specific orphaned database folder

.DESCRIPTION
    Removes a database folder that MySQL can't drop
    (errno 41 "Directory not empty" errors)
    
    You specify the database name - this does NOT auto-delete!
    
.NOTES
    Use when you get: Error dropping database (can't rmdir, errno: 41)
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"

# ============================================================
# FUNCTIONS
# ============================================================

function Get-MySQLDataPath {
    $envData = Load-EnvFile $script:EnvFile
    $xamppRoot = if ($envData.XAMPP_ROOT_DIR) { $envData.XAMPP_ROOT_DIR } else { "C:\xampp" }
    return Join-Path $xamppRoot "mysql\data"
}

function Get-SystemDatabases {
    return @('mysql', 'performance_schema', 'information_schema', 'sys', 'phpmyadmin', 'test')
}

function Format-Size {
    param([long]$Bytes)
    
    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes bytes"
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🧹 MySQL Cleanup" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Use this when DROP DATABASE fails with:" -ForegroundColor Gray
Write-Host "  'errno: 41 Directory not empty'" -ForegroundColor Gray
Write-Host ""

$dataPath = Get-MySQLDataPath

if (-not (Test-Path $dataPath)) {
    Write-Error2 "MySQL data folder not found: $dataPath"
    exit
}

# Check if MySQL is running
$mysqlProcess = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
if ($mysqlProcess) {
    Write-Warning "  MySQL is running - folder may be locked"
    Write-Host ""
}

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Ask for database name
Write-Host "  Enter database name to remove:" -ForegroundColor Yellow
$dbName = (Read-Host "  ").Trim()

if ([string]::IsNullOrEmpty($dbName)) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit
}

# Check if it's a system database
$systemDBs = Get-SystemDatabases
if ($systemDBs -contains $dbName) {
    Write-Host ""
    Write-Error2 "Cannot delete system database: $dbName"
    exit
}

# Check if folder exists
$dbPath = Join-Path $dataPath $dbName

if (-not (Test-Path $dbPath)) {
    Write-Host ""
    Write-Error2 "Folder not found: $dbPath"
    Write-Host ""
    Write-Host "  Available non-system folders:" -ForegroundColor Gray
    Get-ChildItem -Path $dataPath -Directory | Where-Object { $systemDBs -notcontains $_.Name } | ForEach-Object {
        Write-Host "    • $($_.Name)" -ForegroundColor Gray
    }
    exit
}

# Show folder info
$files = Get-ChildItem -Path $dbPath -File -ErrorAction SilentlyContinue
$fileCount = $files.Count
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
$sizeStr = Format-Size $totalSize

Write-Host ""
Write-Host "  Found:" -ForegroundColor White
Write-Host "    📁 $dbName" -ForegroundColor Cyan
Write-Host "       Path:  $dbPath" -ForegroundColor Gray
Write-Host "       Files: $fileCount" -ForegroundColor Gray
Write-Host "       Size:  $sizeStr" -ForegroundColor Gray
Write-Host ""

if ($fileCount -gt 0) {
    Write-Host "  Files:" -ForegroundColor Gray
    $files | Select-Object -First 10 | ForEach-Object {
        Write-Host "    • $($_.Name)" -ForegroundColor DarkGray
    }
    if ($fileCount -gt 10) {
        Write-Host "    ... and $($fileCount - 10) more" -ForegroundColor DarkGray
    }
    Write-Host ""
}

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Confirm deletion
Write-Host "  ⚠️  This will permanently delete this folder!" -ForegroundColor Red
Write-Host ""

if (-not (Prompt-YesNo "  Delete '$dbName'?")) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit
}

Write-Host ""

# Delete folder
try {
    Remove-Item -Path $dbPath -Recurse -Force -ErrorAction Stop
    Write-Success "Removed: $dbName"
    Write-Host ""
    Write-Host "  You can now DROP DATABASE in MySQL if needed." -ForegroundColor Gray
} catch {
    Write-Error2 "Failed to remove: $_"
    Write-Host ""
    Write-Host "  Try stopping MySQL first, then run cleanup again." -ForegroundColor Yellow
}

Write-Host ""
