# Name: Backup MySQL
# Description: Backup MySQL databases
# Icon: 🗄️
# Cmd: backup-mysql
# Order: 4

<#
.SYNOPSIS
    Backup MySQL databases individually as gzipped SQL files
#>

# Get the module root
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backupBaseDir = Join-Path $moduleRoot "backups"

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
$mysqlUser = if ($envVars['MYSQL_USER']) { $envVars['MYSQL_USER'] } else { "root" }
$mysqlPass = $envVars['MYSQL_ROOT_PASSWORD']
$mysqlHost = if ($envVars['MYSQL_HOST']) { $envVars['MYSQL_HOST'] } else { "127.0.0.1" }
$mysqlPort = if ($envVars['MYSQL_PORT']) { $envVars['MYSQL_PORT'] } else { "3306" }

$mysqldump = Join-Path $xamppRoot "mysql\bin\mysqldump.exe"
$mysql = Join-Path $xamppRoot "mysql\bin\mysql.exe"

Show-Header
Write-Host "  🗄️ Backup MySQL" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check mysqldump exists
if (-not (Test-Path $mysqldump)) {
    Write-Error2 "mysqldump not found at: $mysqldump"
    return
}

# Check mysql exists
if (-not (Test-Path $mysql)) {
    Write-Error2 "mysql not found at: $mysql"
    return
}

# Check password is set
if ([string]::IsNullOrEmpty($mysqlPass)) {
    Write-Error2 "MYSQL_ROOT_PASSWORD not set in .env"
    Write-Host "       Please configure your .env file" -ForegroundColor DarkGray
    return
}

# Get list of databases
Write-Info "Fetching database list..."
Write-Host ""

try {
    # Build mysql arguments with password
    $mysqlArgs = @("-u$mysqlUser", "-p$mysqlPass", "--host=$mysqlHost", "--port=$mysqlPort", "-N", "-e", "SHOW DATABASES;")
    
    $dbList = & $mysql @mysqlArgs 2>$null
    
    # Filter out system databases
    $systemDbs = @('information_schema', 'performance_schema', 'mysql', 'sys', 'phpmyadmin')
    $userDbs = $dbList | Where-Object { $_ -and $_.Trim() -and ($_.Trim() -notin $systemDbs) }
    
    if (-not $userDbs -or $userDbs.Count -eq 0) {
        Write-Warning2 "No user databases found"
        return
    }
    
    Write-Host "  Databases to backup:" -ForegroundColor White
    Write-Host ""
    foreach ($db in $userDbs) {
        Write-Host "    📊 $db" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  Found $($userDbs.Count) database(s)" -ForegroundColor DarkGray
    Write-Host ""
    
} catch {
    Write-Error2 "Failed to connect to MySQL: $($_.Exception.Message)"
    return
}

if (-not (Prompt-YesNo "Backup all databases?")) {
    return
}

# Create daily backup folder
$today = Get-Date -Format "yyyy-MM-dd"
$backupDir = Join-Path $backupBaseDir $today
$mysqlDir = Join-Path $backupDir "mysql"

if (-not (Test-Path $mysqlDir)) {
    New-Item -ItemType Directory -Path $mysqlDir -Force | Out-Null
}

Write-Host ""
Write-Info "Backing up to: backups\$today\mysql\"
Write-Host ""

$success = 0
$failed = 0

foreach ($db in $userDbs) {
    $dbName = $db.Trim()
    $sqlFile = Join-Path $mysqlDir "$dbName.sql"
    $gzFile = "$sqlFile.gz"
    
    Write-Host "    ⏳ $dbName..." -NoNewline -ForegroundColor Gray
    
    try {
        # Build mysqldump arguments with password
        $dumpArgs = @("-u$mysqlUser", "-p$mysqlPass", "--host=$mysqlHost", "--port=$mysqlPort", "--single-transaction", "--routines", "--triggers", $dbName)
        
        # Dump database
        $output = & $mysqldump @dumpArgs 2>$null
        
        # Write to file
        $output | Out-File -FilePath $sqlFile -Encoding UTF8
        
        if ((Test-Path $sqlFile) -and (Get-Item $sqlFile).Length -gt 0) {
            # Compress with PowerShell (gzip-like)
            $bytes = [System.IO.File]::ReadAllBytes($sqlFile)
            $ms = New-Object System.IO.MemoryStream
            $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
            $gz.Write($bytes, 0, $bytes.Length)
            $gz.Close()
            [System.IO.File]::WriteAllBytes($gzFile, $ms.ToArray())
            $ms.Close()
            
            # Remove uncompressed
            Remove-Item $sqlFile -Force
            
            $size = [math]::Round((Get-Item $gzFile).Length / 1KB)
            Write-Host "`r    ✅ $dbName ($size KB)        " -ForegroundColor Green
            $success++
        } else {
            Write-Host "`r    ❌ $dbName (dump failed)     " -ForegroundColor Red
            if (Test-Path $sqlFile) { Remove-Item $sqlFile -Force }
            $failed++
        }
    } catch {
        Write-Host "`r    ❌ $dbName ($($_.Exception.Message))" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray

if ($success -gt 0) {
    $totalSize = (Get-ChildItem $mysqlDir -Filter "*.gz" | Measure-Object -Property Length -Sum).Sum
    $totalSizeKB = [math]::Round($totalSize / 1KB)
    Write-Success "$success database(s) backed up ($totalSizeKB KB total)"
    Write-Host "       Location: backups\$today\mysql\" -ForegroundColor DarkGray
}

if ($failed -gt 0) {
    Write-Warning2 "$failed database(s) failed"
}

# ============================================================
# BACKUP USER GRANTS
# ============================================================
Write-Host ""
if (Prompt-YesNo "Also backup MySQL user grants?") {
    Write-Host ""
    Write-Info "Backing up user grants..."
    
    $grantsFile = Join-Path $mysqlDir "grants.sql"
    $grantsGz = "$grantsFile.gz"
    
    try {
        # Get all users
        $usersArgs = @("-u$mysqlUser", "-p$mysqlPass", "--host=$mysqlHost", "--port=$mysqlPort", "-N", "-e", "SELECT DISTINCT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user != '';")
        $userQueries = & $mysql @usersArgs 2>$null
        
        if ($userQueries) {
            $allGrants = @()
            $allGrants += "-- MySQL User Grants Backup"
            $allGrants += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $allGrants += ""
            
            foreach ($query in $userQueries) {
                if ($query) {
                    $grantArgs = @("-u$mysqlUser", "-p$mysqlPass", "--host=$mysqlHost", "--port=$mysqlPort", "-N", "-e", $query.Trim())
                    $grants = & $mysql @grantArgs 2>$null
                    if ($grants) {
                        foreach ($grant in $grants) {
                            $allGrants += "$grant;"
                        }
                        $allGrants += ""
                    }
                }
            }
            
            # Write to file
            $allGrants | Out-File -FilePath $grantsFile -Encoding UTF8
            
            # Compress
            $bytes = [System.IO.File]::ReadAllBytes($grantsFile)
            $ms = New-Object System.IO.MemoryStream
            $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
            $gz.Write($bytes, 0, $bytes.Length)
            $gz.Close()
            [System.IO.File]::WriteAllBytes($grantsGz, $ms.ToArray())
            $ms.Close()
            Remove-Item $grantsFile -Force
            
            $grantSize = [math]::Round((Get-Item $grantsGz).Length / 1KB)
            Write-Success "User grants backed up (grants.sql.gz - $grantSize KB)"
        } else {
            Write-Warning2 "No user grants found"
        }
    } catch {
        Write-Error2 "Failed to backup grants: $($_.Exception.Message)"
    }
}

Write-Host ""
