# Name: MySQL Setup
# Description: Configure MySQL root & pma users from .env
# Icon: 🔐
# Cmd: setup-mysql
# Order: 3

<#
.SYNOPSIS
    MySQL User Setup - Configure root and pma users from .env

.DESCRIPTION
    Applies MySQL user configuration from .env file:
    - Sets root user password from MYSQL_ROOT_PASSWORD
    - Creates pma control user from PMA_CONTROLUSER/PMA_CONTROLPASS
    
.NOTES
    All credentials come from .env - this script just applies them to MySQL
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

function Set-RootPassword {
    param(
        [string]$CurrentUser,
        [string]$CurrentPass,
        [string]$NewRootPass
    )
    
    Write-Info "Setting root password..."
    
    $queries = @(
        "ALTER USER 'root'@'localhost' IDENTIFIED BY '$NewRootPass';",
        "FLUSH PRIVILEGES;"
    )
    
    foreach ($query in $queries) {
        $result = Invoke-MySQL -User $CurrentUser -Password $CurrentPass -Query $query
        if (-not $result.Success) {
            Write-Error2 "Failed: $($result.Output)"
            return $false
        }
    }
    
    Write-Success "Root password set"
    return $true
}

function Set-PmaUser {
    param(
        [string]$RootUser,
        [string]$RootPass,
        [string]$PmaUser,
        [string]$PmaPass
    )
    
    Write-Info "Creating $PmaUser user..."
    
    $queries = @(
        "DROP USER IF EXISTS '$PmaUser'@'localhost';",
        "CREATE USER '$PmaUser'@'localhost' IDENTIFIED BY '$PmaPass';",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON phpmyadmin.* TO '$PmaUser'@'localhost';",
        "FLUSH PRIVILEGES;"
    )
    
    foreach ($query in $queries) {
        $result = Invoke-MySQL -User $RootUser -Password $RootPass -Query $query
        if (-not $result.Success) {
            Write-Warning "  Warning: $($result.Output)"
        }
    }
    
    Write-Success "$PmaUser user created"
    return $true
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🔐 MySQL Setup" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check .env exists
if (-not (Test-Path $script:EnvFile)) {
    Write-Error2 ".env file not found! Copy .env.example to .env first."
    exit
}

# Load .env
$envData = Load-EnvFile $script:EnvFile

# Validate required fields
$requiredFields = @('MYSQL_ROOT_PASSWORD', 'PMA_USER', 'PMA_PASSWORD')
$missing = @()
foreach ($field in $requiredFields) {
    if (-not $envData[$field]) {
        $missing += $field
    }
}

if ($missing.Count -gt 0) {
    Write-Error2 "Missing required .env fields:"
    foreach ($m in $missing) {
        Write-Host "    • $m" -ForegroundColor Red
    }
    exit
}

# Display what will be applied
Write-Host "  From .env:" -ForegroundColor White
Write-Host "    • Root password: $($envData.MYSQL_ROOT_PASSWORD.Substring(0,8))..." -ForegroundColor Gray
Write-Host "    • PMA user:      $($envData.PMA_USER)" -ForegroundColor Gray
Write-Host "    • PMA password:  $($envData.PMA_PASSWORD.Substring(0,8))..." -ForegroundColor Gray
Write-Host ""

# Check MySQL is running
$mysqlProcess = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
if (-not $mysqlProcess) {
    Write-Error2 "MySQL is not running! Start it first."
    exit
}

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Determine current MySQL access
Write-Info "Checking MySQL access..."

$accessUser = "root"
$accessPass = ""
$needsRootUpdate = $true

# Try with .env password first
if (Test-MySQLConnection -User "root" -Password $envData.MYSQL_ROOT_PASSWORD) {
    Write-Success "  Connected (password already set)"
    $accessPass = $envData.MYSQL_ROOT_PASSWORD
    $needsRootUpdate = $false
}
# Try no password (fresh install)
elseif (Test-MySQLConnection -User "root" -Password "") {
    Write-Success "  Connected (fresh install)"
    $accessPass = ""
    $needsRootUpdate = $true
}
else {
    Write-Warning "  Cannot connect with .env password or blank"
    Write-Host ""
    Write-Host "  Enter current root password:" -ForegroundColor Yellow
    $manualPass = Read-Host "  "
    
    if (Test-MySQLConnection -User "root" -Password $manualPass) {
        Write-Success "  Connected"
        $accessPass = $manualPass
        $needsRootUpdate = $true
    } else {
        Write-Error2 "Cannot connect to MySQL."
        exit
    }
}

Write-Host ""

if (-not (Prompt-YesNo "  Apply to MySQL?")) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Execute setup
$success = $true

# 1. Set root password if needed
if ($needsRootUpdate) {
    if (-not (Set-RootPassword -CurrentUser $accessUser -CurrentPass $accessPass -NewRootPass $envData.MYSQL_ROOT_PASSWORD)) {
        $success = $false
    }
    # Use new password for subsequent operations
    $accessPass = $envData.MYSQL_ROOT_PASSWORD
} else {
    Write-Info "Root password already set - skipping"
}

# 2. Create pma user
if ($success) {
    if (-not (Set-PmaUser -RootUser $accessUser -RootPass $accessPass -PmaUser $envData.PMA_USER -PmaPass $envData.PMA_PASSWORD)) {
        $success = $false
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($success) {
    Write-Success "MySQL setup complete!"
    Write-Host ""
    Write-Host "  Created:" -ForegroundColor White
    Write-Host "    • root@localhost with password" -ForegroundColor Gray
    Write-Host "    • $($envData.PMA_USER)@localhost with privileges" -ForegroundColor Gray
} else {
    Write-Error2 "Setup completed with errors."
}

Write-Host ""
