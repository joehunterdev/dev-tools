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
Write-Info "Checking if MySQL is running..."

$mysqlProcess = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
if (-not $mysqlProcess) {
    Write-Warning "  MySQL is not running"
    Write-Host ""
    
    if (Prompt-YesNo "  Start MySQL now?") {
        Write-Host ""
        Write-Host "  Starting MySQL..." -ForegroundColor White
        
        $xamppRoot = if ($envData.XAMPP_ROOT_DIR) { $envData.XAMPP_ROOT_DIR } else { "C:\xampp" }
        $mysqldPath = Join-Path $xamppRoot "mysql\bin\mysqld.exe"
        
        if (Test-Path $mysqldPath) {
            try {
                # Start MySQL service via XAMPP control
                $xamppControlPath = Join-Path $xamppRoot "xampp-control.exe"
                
                if (Test-Path $xamppControlPath) {
                    # Try via Windows service first
                    $serviceStatus = (Get-Service -Name "MySQL80" -ErrorAction SilentlyContinue).Status
                    if ($serviceStatus) {
                        Start-Service -Name "MySQL80" -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 3
                    } else {
                        # If not a service, try running directly
                        Start-Process -FilePath $mysqldPath -WindowStyle Hidden -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 3
                    }
                } else {
                    Start-Process -FilePath $mysqldPath -WindowStyle Hidden -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                }
                
                # Check if it started
                $mysqlProcess = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
                if ($mysqlProcess) {
                    Write-Success "  MySQL started"
                } else {
                    Write-Warning "  Could not start MySQL automatically"
                    Write-Host ""
                    Write-Host "  Please start MySQL manually:" -ForegroundColor Yellow
                    Write-Host "    1. Open XAMPP Control Panel" -ForegroundColor Gray
                    Write-Host "    2. Click 'Start' next to MySQL" -ForegroundColor Gray
                    exit
                }
            } catch {
                Write-Warning "  Could not start MySQL automatically"
                Write-Host ""
                Write-Host "  Please start MySQL manually from XAMPP Control Panel" -ForegroundColor Yellow
                exit
            }
        } else {
            Write-Error2 "MySQL executable not found at: $mysqldPath"
            exit
        }
    } else {
        Write-Host ""
        Write-Host "  Cancelled. Start MySQL and run again." -ForegroundColor Yellow
        exit
    }
} else {
    Write-Success "  MySQL is running"
}

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
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "    1. Enter current root password" -ForegroundColor Gray
    Write-Host "    2. Reset root password to .env value" -ForegroundColor Gray
    Write-Host "    3. Force password reset (forgotten password recovery)" -ForegroundColor Gray
    Write-Host ""
    
    $option = Read-Host "  Choose (1-3)"
    
    if ($option -eq "1") {
        Write-Host ""
        Write-Host "  Enter current root password:" -ForegroundColor Yellow
        $securePass = Read-Host "  " -AsSecureString
        $manualPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($securePass))
        
        if (Test-MySQLConnection -User "root" -Password $manualPass) {
            Write-Success "  Connected"
            $accessPass = $manualPass
            $needsRootUpdate = $true
        } else {
            Write-Error2 "Cannot connect to MySQL."
            exit
        }
    }
    elseif ($option -eq "2") {
        Write-Host ""
        Write-Host "  Enter current root password (press Enter if no password):" -ForegroundColor Yellow
        $securePass = Read-Host "  " -AsSecureString
        $currentPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($securePass))
        
        Write-Host ""
        Write-Host "  Testing connection..." -ForegroundColor Gray
        
        # Test connection - handle empty password specially
        $connectionTest = $false
        if ([string]::IsNullOrEmpty($currentPass)) {
            # Try with no password
            $connectionTest = Test-MySQLConnection -User "root" -Password ""
        } else {
            $connectionTest = Test-MySQLConnection -User "root" -Password $currentPass
        }
        
        if (-not $connectionTest) {
            Write-Error2 "Cannot connect to MySQL with provided password."
            Write-Host ""
            Write-Host "  If you don't know the current password, use option 3 (Force reset)" -ForegroundColor Yellow
            exit
        }
        
        Write-Success "  Connected"
        
        Write-Host ""
        Write-Host "  Resetting root password to .env value..." -ForegroundColor White
        
        if (-not (Set-RootPassword -CurrentUser "root" -CurrentPass $currentPass -NewRootPass $envData.MYSQL_ROOT_PASSWORD)) {
            Write-Error2 "Failed to reset MySQL password."
            exit
        }
        
        Write-Success "Root password reset successfully"
        $accessPass = $envData.MYSQL_ROOT_PASSWORD
        $needsRootUpdate = $false
    }
    elseif ($option -eq "3") {
        Write-Host ""
        Write-Host "  Force Password Reset (skip-grant-tables mode)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  This will:" -ForegroundColor White
        Write-Host "    1. Stop MySQL" -ForegroundColor Gray
        Write-Host "    2. Start in safe mode (skip-grant-tables)" -ForegroundColor Gray
        Write-Host "    3. Reset root password" -ForegroundColor Gray
        Write-Host "    4. Restart MySQL normally" -ForegroundColor Gray
        Write-Host ""
        
        if (-not (Prompt-YesNo "  Continue?")) {
            Write-Host ""
            Write-Host "  Cancelled." -ForegroundColor Yellow
            exit
        }
        
        Write-Host ""
        Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        
        $xamppRoot = if ($envData.XAMPP_ROOT_DIR) { $envData.XAMPP_ROOT_DIR } else { "C:\xampp" }
        $mysqldPath = Join-Path $xamppRoot "mysql\bin\mysqld.exe"
        $mysqlPath = Join-Path $xamppRoot "mysql\bin\mysql.exe"
        $newPass = $envData.MYSQL_ROOT_PASSWORD
        
        try {
            # Step 1: Stop MySQL
            Write-Host "  Step 1: Stopping MySQL..." -ForegroundColor White
            
            # Try to stop via service first
            $serviceStatus = (Get-Service -Name "MySQL80" -ErrorAction SilentlyContinue).Status
            if ($serviceStatus) {
                Stop-Service -Name "MySQL80" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            } else {
                # Kill the process
                Get-Process -Name "mysqld" -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 2
            }
            
            Write-Success "  MySQL stopped"
            
            # Step 2: Start in skip-grant-tables mode
            Write-Host ""
            Write-Host "  Step 2: Starting MySQL in safe mode..." -ForegroundColor White
            
            $mysqldProcess = Start-Process -FilePath $mysqldPath -ArgumentList "--skip-grant-tables" -PassThru -WindowStyle Hidden
            Start-Sleep -Seconds 3
            
            Write-Success "  MySQL started in safe mode"
            
            # Step 3: Reset password
            Write-Host ""
            Write-Host "  Step 3: Resetting root password..." -ForegroundColor White
            
            $query = "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '$newPass';"
            $result = & $mysqlPath --host=127.0.0.1 -u root -e $query 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "  Password reset successfully"
            } else {
                Write-Warning "  Could not reset password with query: $result"
            }
            
            # Step 4: Stop safe mode and restart normally
            Write-Host ""
            Write-Host "  Step 4: Restarting MySQL normally..." -ForegroundColor White
            
            Get-Process -Name "mysqld" -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Seconds 2
            
            # Restart via service or process
            if ($serviceStatus) {
                Start-Service -Name "MySQL80" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
            } else {
                Start-Process -FilePath $mysqldPath -WindowStyle Hidden -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
            }
            
            Write-Success "  MySQL restarted"
            
            # Verify new password works
            Write-Host ""
            Write-Host "  Step 5: Verifying new password..." -ForegroundColor White
            
            if (Test-MySQLConnection -User "root" -Password $newPass) {
                Write-Success "  Password verified - working!"
                $accessPass = $newPass
                $needsRootUpdate = $false
            } else {
                Write-Warning "  Could not verify password, but reset may have worked"
                Write-Host "  Try connecting manually to verify" -ForegroundColor Yellow
                $accessPass = $newPass
                $needsRootUpdate = $false
            }
        } catch {
            Write-Error2 "Error during force reset: $_"
            Write-Host ""
            Write-Host "  Please restart MySQL manually from XAMPP Control Panel" -ForegroundColor Yellow
            exit
        }
    }
    else {
        Write-Error2 "Invalid option."
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
    Write-Host "    - root@localhost with password" -ForegroundColor Gray
    Write-Host "    - $($envData.PMA_USER)@localhost with privileges" -ForegroundColor Gray
} else {
    Write-Error2 "Setup completed with errors."
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Menu for additional actions
Write-Host "  Additional options:" -ForegroundColor White
Write-Host "    1. Reset root password (and rebuild configs)" -ForegroundColor Gray
Write-Host "    2. Exit" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "  Choice (1-2)"

if ($choice -eq "1") {
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Reset Root Password" -ForegroundColor White
    Write-Host ""
    
    # Try current .env password first to verify access
    Write-Host "  Verifying MySQL access..." -ForegroundColor Gray
    $rootPass = $envData.MYSQL_ROOT_PASSWORD
    
    if (-not (Test-MySQLConnection -User "root" -Password $rootPass)) {
        Write-Warning "  .env password didn't work, prompting for current access..."
        Write-Host ""
        Write-Host "  Enter current root password:" -ForegroundColor Yellow
        $securePass = Read-Host "  " -AsSecureString
        $rootPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($securePass))
        
        if (-not (Test-MySQLConnection -User "root" -Password $rootPass)) {
            Write-Error2 "Cannot connect to MySQL. Cannot proceed with password reset."
            exit
        }
    } else {
        Write-Success "  Connected"
    }
    
    Write-Host ""
    Write-Host "  Enter new root password:" -ForegroundColor Yellow
    $newPass = Read-Host "  " -AsSecureString
    $newPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($newPass))
    
    Write-Host ""
    Write-Host "  Confirm new root password:" -ForegroundColor Yellow
    $confirmPass = Read-Host "  " -AsSecureString
    $confirmPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($confirmPass))
    
    if ($newPassPlain -ne $confirmPassPlain) {
        Write-Error2 "Passwords do not match!"
        exit
    }
    
    Write-Host ""
    
    if (-not (Prompt-YesNo "  Update MySQL root password?")) {
        Write-Host ""
        Write-Host "  Cancelled." -ForegroundColor Yellow
        exit
    }
    
    Write-Host ""
    
    # Update password in MySQL (using root access we already verified)
    if (-not (Set-RootPassword -CurrentUser "root" -CurrentPass $rootPass -NewRootPass $newPassPlain)) {
        Write-Error2 "Failed to update MySQL password."
        exit
    }
    
    # Update .env file
    Write-Host "  Updating .env file..." -ForegroundColor White
    
    try {
        $envContent = Get-Content $script:EnvFile -Raw
        $envContent = $envContent -replace "MYSQL_ROOT_PASSWORD=.*", "MYSQL_ROOT_PASSWORD=$newPassPlain"
        Set-Content -Path $script:EnvFile -Value $envContent -NoNewline
        Write-Success ".env updated"
    } catch {
        Write-Error2 "Failed to update .env: $($_)"
        exit
    }
    
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  IMPORTANT: Configs need to be rebuilt!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The following configs now need regeneration:" -ForegroundColor White
    Write-Host "    - phpMyAdmin config.inc.php" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  To rebuild and deploy:" -ForegroundColor White
    Write-Host "    1. Run 'xampp-tools' (or 'build-configs')" -ForegroundColor Gray
    Write-Host "    2. Then run 'deploy-configs'" -ForegroundColor Gray
    Write-Host ""
    Write-Success "Root password reset complete!"
}

Write-Host ""
