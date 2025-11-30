# Name: Restore MySQL
# Description: Restore a database from backup
# Icon: 📥
# Cmd: restore-mysql
# Order: 10

<#
.SYNOPSIS
    Restore MySQL database from backup

.DESCRIPTION
    Restores a .sql.gz backup file to MySQL
    - Lists available backups
    - Optionally creates fresh database
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:BackupDir = Join-Path $moduleRoot "backups"

# ============================================================
# FUNCTIONS
# ============================================================

function Get-MySQLPath {
    $envData = Load-EnvFile $script:EnvFile
    $xamppRoot = if ($envData.XAMPP_ROOT_DIR) { $envData.XAMPP_ROOT_DIR } else { "C:\xampp" }
    return Join-Path $xamppRoot "mysql\bin\mysql.exe"
}

function Get-AvailableBackups {
    $backups = @()
    
    if (-not (Test-Path $script:BackupDir)) {
        return $backups
    }
    
    # Find all .sql.gz files in backup folders
    Get-ChildItem -Path $script:BackupDir -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | ForEach-Object {
        $dateFolder = $_
        $mysqlDir = Join-Path $dateFolder.FullName "mysql"
        
        if (Test-Path $mysqlDir) {
            Get-ChildItem -Path $mysqlDir -Filter "*.sql.gz" | ForEach-Object {
                $dbName = $_.BaseName -replace '\.sql$', ''
                $backups += @{
                    Date = $dateFolder.Name
                    Database = $dbName
                    File = $_.FullName
                    Size = $_.Length
                }
            }
        }
    }
    
    return $backups | Sort-Object Date -Descending
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

function Restore-Database {
    param(
        [string]$BackupFile,
        [string]$DatabaseName,
        [string]$User,
        [string]$Password
    )
    
    $mysql = Get-MySQLPath
    
    try {
        # Decompress and pipe to mysql
        Write-Info "Decompressing and importing..."
        
        $fileStream = [System.IO.File]::OpenRead($BackupFile)
        $gzipStream = New-Object System.IO.Compression.GZipStream($fileStream, [System.IO.Compression.CompressionMode]::Decompress)
        $reader = New-Object System.IO.StreamReader($gzipStream)
        $sql = $reader.ReadToEnd()
        $reader.Close()
        $gzipStream.Close()
        $fileStream.Close()
        
        # Import via mysql
        $sql | & $mysql --host=127.0.0.1 "-u$User" "-p$Password" $DatabaseName 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            return $false
        }
    } catch {
        Write-Error2 "Failed: $_"
        return $false
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  📥 Restore MySQL" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check .env
if (-not (Test-Path $script:EnvFile)) {
    Write-Error2 ".env file not found!"
    exit
}

$envData = Load-EnvFile $script:EnvFile

if (-not $envData.MYSQL_ROOT_PASSWORD) {
    Write-Error2 "MYSQL_ROOT_PASSWORD not set in .env"
    exit
}

# Check MySQL is running
$mysqlProcess = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
if (-not $mysqlProcess) {
    Write-Error2 "MySQL is not running! Start it first."
    exit
}

# Get available backups
$backups = Get-AvailableBackups

if ($backups.Count -eq 0) {
    Write-Warning "No backups found in backups\ folder"
    Write-Host ""
    Write-Host "  Run 'backup-mysql' first to create backups." -ForegroundColor Gray
    exit
}

# Group by date
$byDate = $backups | Group-Object Date

Write-Host "  Available backups:" -ForegroundColor White
Write-Host ""

$index = 1
$backupList = @()

foreach ($dateGroup in $byDate) {
    Write-Host "  📅 $($dateGroup.Name)" -ForegroundColor Yellow
    foreach ($backup in $dateGroup.Group) {
        $size = Format-Size $backup.Size
        Write-Host "     $index. $($backup.Database) ($size)" -ForegroundColor Gray
        $backupList += $backup
        $index++
    }
    Write-Host ""
}

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Select backup
Write-Host "  Enter backup number (or 0 to cancel):" -ForegroundColor Yellow
$choice = Read-Host "  "

if ($choice -eq '0' -or [string]::IsNullOrEmpty($choice)) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit
}

$selectedIndex = [int]$choice - 1
if ($selectedIndex -lt 0 -or $selectedIndex -ge $backupList.Count) {
    Write-Error2 "Invalid selection"
    exit
}

$selected = $backupList[$selectedIndex]

Write-Host ""
Write-Host "  Selected: $($selected.Database) from $($selected.Date)" -ForegroundColor Cyan
Write-Host ""

# Ask for target database name
Write-Host "  Enter target database name" -ForegroundColor Yellow
Write-Host "  (press Enter to use '$($selected.Database)'):" -ForegroundColor Gray
$targetDb = (Read-Host "  ").Trim()

if ([string]::IsNullOrEmpty($targetDb)) {
    $targetDb = $selected.Database
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check if database exists
$mysql = Get-MySQLPath
$checkResult = & $mysql --host=127.0.0.1 -uroot "-p$($envData.MYSQL_ROOT_PASSWORD)" -e "SHOW DATABASES LIKE '$targetDb';" 2>&1
$dbExists = $checkResult -match $targetDb

if ($dbExists) {
    Write-Warning "Database '$targetDb' already exists!"
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor White
    Write-Host "    1. Drop and recreate (DESTRUCTIVE)" -ForegroundColor Red
    Write-Host "    2. Import into existing (may fail on duplicates)" -ForegroundColor Yellow
    Write-Host "    0. Cancel" -ForegroundColor Gray
    Write-Host ""
    
    $action = Read-Host "  Choice"
    
    if ($action -eq '0' -or [string]::IsNullOrEmpty($action)) {
        Write-Host ""
        Write-Host "  Cancelled." -ForegroundColor Yellow
        exit
    }
    
    if ($action -eq '1') {
        Write-Host ""
        Write-Info "Dropping database '$targetDb'..."
        & $mysql --host=127.0.0.1 -uroot "-p$($envData.MYSQL_ROOT_PASSWORD)" -e "DROP DATABASE ``$targetDb``;" 2>&1 | Out-Null
        & $mysql --host=127.0.0.1 -uroot "-p$($envData.MYSQL_ROOT_PASSWORD)" -e "CREATE DATABASE ``$targetDb``;" 2>&1 | Out-Null
        Write-Success "Database recreated"
    }
} else {
    Write-Info "Creating database '$targetDb'..."
    & $mysql --host=127.0.0.1 -uroot "-p$($envData.MYSQL_ROOT_PASSWORD)" -e "CREATE DATABASE ``$targetDb``;" 2>&1 | Out-Null
    Write-Success "Database created"
}

Write-Host ""

# Restore
Write-Info "Restoring from: $($selected.Date)\mysql\$($selected.Database).sql.gz"
Write-Host ""

$success = Restore-Database -BackupFile $selected.File -DatabaseName $targetDb -User "root" -Password $envData.MYSQL_ROOT_PASSWORD

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($success) {
    Write-Success "Database '$targetDb' restored!"
} else {
    Write-Error2 "Restore failed. Check MySQL logs."
}

Write-Host ""
