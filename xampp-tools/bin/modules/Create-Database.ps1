# Name: Create Database
# Description: Quickly create a new MySQL database with utf8mb4_general_ci
# Icon: 🗄️
# Cmd: create-db
# Order: 4

<#
.SYNOPSIS
    Create Database - Quickly create a new MySQL database

.DESCRIPTION
    Interactive tool to create a new MySQL database with utf8mb4_general_ci charset.
    
    Prompts for:
    - Database name
    - MySQL root password
    
.NOTES
    Uses root credentials to create database
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

function Get-MySQLPath {
    $envData = Load-EnvFile $script:EnvFile
    $xamppRoot = if ($envData.XAMPP_ROOT_DIR) { $envData.XAMPP_ROOT_DIR } else { "C:\xampp" }
    return Join-Path $xamppRoot "mysql\bin\mysql.exe"
}

function Test-MySQLConnection {
    param(
        [string]$User,
        [string]$Password
    )
    
    $mysql = Get-MySQLPath
    
    if (-not (Test-Path $mysql)) {
        return $false
    }
    
    try {
        if ([string]::IsNullOrEmpty($Password)) {
            $null = & $mysql --host=127.0.0.1 "-u$User" -e "SELECT 1;" 2>&1
        } else {
            $null = & $mysql --host=127.0.0.1 "-u$User" "-p$Password" -e "SELECT 1;" 2>&1
        }
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Invoke-MySQL {
    param(
        [string]$User,
        [string]$Password,
        [string]$Query
    )
    
    $mysql = Get-MySQLPath
    
    if ([string]::IsNullOrEmpty($Password)) {
        $result = & $mysql --host=127.0.0.1 "-u$User" -e $Query 2>&1
    } else {
        $result = & $mysql --host=127.0.0.1 "-u$User" "-p$Password" -e $Query 2>&1
    }
    
    return @{
        Success = ($LASTEXITCODE -eq 0)
        Output = $result
    }
}

function Test-DatabaseExists {
    param(
        [string]$DatabaseName,
        [string]$RootPass
    )
    
    $query = "SHOW DATABASES LIKE '$DatabaseName';"
    $result = Invoke-MySQL -User "root" -Password $RootPass -Query $query
    
    return [bool]($result.Output | Where-Object { $_ -match "^\s*$DatabaseName\s*$" })
}

function New-Database {
    param(
        [string]$DatabaseName,
        [string]$RootPass
    )
    
    $query = "CREATE DATABASE ``$DatabaseName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    $result = Invoke-MySQL -User "root" -Password $RootPass -Query $query
    
    return $result.Success
}

function New-DatabaseUser {
    param(
        [string]$DatabaseName,
        [string]$UserName,
        [string]$Password,
        [string]$RootPass
    )
    
    $queries = @(
        "CREATE USER ``$UserName``@'localhost' IDENTIFIED BY '$Password';",
        "GRANT ALL PRIVILEGES ON ``$DatabaseName``.* TO ``$UserName``@'localhost';",
        "FLUSH PRIVILEGES;"
    )
    
    foreach ($query in $queries) {
        $result = Invoke-MySQL -User "root" -Password $RootPass -Query $query
        if (-not $result.Success) {
            return $false
        }
    }
    
    return $true
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host "  Create MySQL Database" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Load env file
$envData = Load-EnvFile $script:EnvFile
$rootPassword = $envData.MYSQL_ROOT_PASSWORD

if ([string]::IsNullOrEmpty($rootPassword)) {
    Write-Warning "  No MYSQL_ROOT_PASSWORD in .env"
    Write-Host ""
    Write-Host "  Enter MySQL root password:" -ForegroundColor Yellow
    $rootPassword = Read-Host "  " -AsSecureString
    $rootPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($rootPassword))
}

# Test connection
Write-Info "Testing MySQL connection..."

if (-not (Test-MySQLConnection -User "root" -Password $rootPassword)) {
    Write-Error2 "Cannot connect to MySQL with provided password"
    Write-Host ""
    exit
}

Write-Success "  Connected to MySQL"
Write-Host ""

# Get database name
Write-Host "  Database name:" -ForegroundColor Yellow
$dbName = Read-Host "  "

if ([string]::IsNullOrEmpty($dbName)) {
    Write-Error2 "Database name cannot be empty"
    exit
}

# Validate database name (alphanumeric, underscore, hyphen)
if ($dbName -notmatch '^[a-zA-Z0-9_\-]+$') {
    Write-Error2 "Invalid database name. Use only letters, numbers, underscores, and hyphens."
    exit
}

Write-Host ""

# Check if database already exists
Write-Info "Checking if database exists..."

if (Test-DatabaseExists -DatabaseName $dbName -RootPass $rootPassword) {
    Write-Warning "  Database '$dbName' already exists"
    Write-Host ""
    exit
}

Write-Success "  Database '$dbName' is available"
Write-Host ""

# Get username for database
Write-Host "  Database user (optional, leave blank to skip):" -ForegroundColor Yellow
$userName = Read-Host "  "

$createUser = $false
$userPassword = ""

if (-not [string]::IsNullOrEmpty($userName)) {
    if ($userName -notmatch '^[a-zA-Z0-9_\-]+$') {
        Write-Error2 "Invalid username. Use only letters, numbers, underscores, and hyphens."
        exit
    }
    
    Write-Host ""
    Write-Host "  Password for user '$userName':" -ForegroundColor Yellow
    $userPassword = Read-Host "  " -AsSecureString
    $userPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($userPassword))
    
    if ([string]::IsNullOrEmpty($userPassword)) {
        Write-Error2 "Password cannot be empty"
        exit
    }
    
    $createUser = $true
}

Write-Host ""

# Confirm creation
Write-Host "  Create:" -ForegroundColor White
Write-Host "    Database: $dbName" -ForegroundColor Gray
Write-Host "    Charset: utf8mb4" -ForegroundColor Gray
Write-Host "    Collation: utf8mb4_general_ci" -ForegroundColor Gray

if ($createUser) {
    Write-Host "    User: $userName (all privileges on $dbName)" -ForegroundColor Gray
}

Write-Host ""

if (-not (Prompt-YesNo "  Proceed?")) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    Write-Host ""
    exit
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Create database
Write-Info "Creating database..."

if (New-Database -DatabaseName $dbName -RootPass $rootPassword) {
    Write-Success "Database created successfully!"
} else {
    Write-Error2 "Failed to create database"
    Write-Host ""
    exit
}

# Create user if requested
if ($createUser) {
    Write-Info "Creating user..."
    
    if (New-DatabaseUser -DatabaseName $dbName -UserName $userName -Password $userPassword -RootPass $rootPassword) {
        Write-Success "User created with all privileges!"
    } else {
        Write-Error2 "Failed to create user (database was created)"
        Write-Host ""
        exit
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Database: $dbName" -ForegroundColor White
Write-Host "  Charset: utf8mb4" -ForegroundColor Gray
Write-Host "  Collation: utf8mb4_general_ci" -ForegroundColor Gray

if ($createUser) {
    Write-Host "  User: $userName" -ForegroundColor White
    Write-Host "  Privileges: ALL on $dbName.*" -ForegroundColor Gray
}

