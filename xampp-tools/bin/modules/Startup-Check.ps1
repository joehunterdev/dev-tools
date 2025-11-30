# Name: Startup Check
# Description: Verify environment
# Icon: 🔍
# Cmd: check
# Order: 1

<#
.SYNOPSIS
    Validates XAMPP Tools environment is properly configured
#>

# Get the root (parent of bin/modules)
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Write-Host ""
Write-Host "  🔍 Running Startup Checks..." -ForegroundColor Cyan
Write-Host ""

$checks = @()
$allPassed = $true

# ============================================================
# CHECK 1: .env file exists
# ============================================================
Write-Host "  Checking .env configuration..." -ForegroundColor Gray

$envFile = Join-Path $moduleRoot ".env"
$envExampleFile = Join-Path $moduleRoot ".env.example"

if (Test-Path $envFile) {
    $checks += @{ Name = ".env file exists"; Status = "✅"; Passed = $true }
} else {
    $checks += @{ Name = ".env file exists"; Status = "❌"; Passed = $false; Fix = "Copy .env.example to .env" }
    $allPassed = $false
    
    # Offer to create from example
    if (Test-Path $envExampleFile) {
        Write-Host "    ⚠️  .env file not found" -ForegroundColor Yellow
        $create = Read-Host "    Create from .env.example? (y/n)"
        if ($create -eq 'y') {
            Copy-Item $envExampleFile $envFile
            Write-Host "    ✅ Created .env from .env.example" -ForegroundColor Green
            $checks[-1].Status = "✅"
            $checks[-1].Passed = $true
            $allPassed = $true
        }
    }
}

# ============================================================
# CHECK 2: Administrator privileges
# ============================================================
Write-Host "  Checking administrator privileges..." -ForegroundColor Gray

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    $checks += @{ Name = "Running as Administrator"; Status = "✅"; Passed = $true }
} else {
    $checks += @{ Name = "Running as Administrator"; Status = "⚠️"; Passed = $true; Note = "Some features require admin" }
}

# ============================================================
# CHECK 3: XAMPP paths accessible
# ============================================================
Write-Host "  Checking XAMPP paths..." -ForegroundColor Gray

# Load .env if it exists to get paths
$xamppRoot = "C:\xampp"
if (Test-Path $envFile) {
    $envContent = Get-Content $envFile -Raw
    if ($envContent -match 'XAMPP_ROOT_DIR\s*=\s*"?([^"\r\n]+)"?') {
        $xamppRoot = $matches[1].Trim()
    }
}

$pathsToCheck = @(
    @{ Name = "XAMPP Root"; Path = $xamppRoot }
    @{ Name = "Apache"; Path = Join-Path $xamppRoot "apache" }
    @{ Name = "PHP"; Path = Join-Path $xamppRoot "php" }
    @{ Name = "MySQL"; Path = Join-Path $xamppRoot "mysql" }
)

foreach ($p in $pathsToCheck) {
    if (Test-Path $p.Path) {
        $checks += @{ Name = "$($p.Name) ($($p.Path))"; Status = "✅"; Passed = $true }
    } else {
        $checks += @{ Name = "$($p.Name) ($($p.Path))"; Status = "❌"; Passed = $false }
        $allPassed = $false
    }
}

# ============================================================
# CHECK 4: Key config files
# ============================================================
Write-Host "  Checking config files..." -ForegroundColor Gray

$configFiles = @(
    @{ Name = "httpd.conf"; Path = Join-Path $xamppRoot "apache\conf\httpd.conf" }
    @{ Name = "php.ini"; Path = Join-Path $xamppRoot "php\php.ini" }
    @{ Name = "my.ini"; Path = Join-Path $xamppRoot "mysql\bin\my.ini" }
)

foreach ($cfg in $configFiles) {
    if (Test-Path $cfg.Path) {
        $checks += @{ Name = "$($cfg.Name)"; Status = "✅"; Passed = $true }
    } else {
        $checks += @{ Name = "$($cfg.Name)"; Status = "❌"; Passed = $false }
        $allPassed = $false
    }
}

# ============================================================
# CHECK 5: Hosts file accessible
# ============================================================
Write-Host "  Checking hosts file..." -ForegroundColor Gray

$hostsFile = "C:\Windows\System32\drivers\etc\hosts"
if (Test-Path $hostsFile) {
    # Check if we can write to it (need admin)
    try {
        $acl = Get-Acl $hostsFile
        $checks += @{ Name = "Hosts file ($hostsFile)"; Status = "✅"; Passed = $true }
        
        # Try to test write access
        if (-not $isAdmin) {
            $checks += @{ Name = "Hosts file writable"; Status = "⚠️"; Passed = $true; Note = "Need admin to modify" }
        } else {
            $checks += @{ Name = "Hosts file writable"; Status = "✅"; Passed = $true }
        }
    } catch {
        $checks += @{ Name = "Hosts file"; Status = "❌"; Passed = $false; Fix = "Run as Administrator" }
        $allPassed = $false
    }
} else {
    $checks += @{ Name = "Hosts file"; Status = "❌"; Passed = $false }
    $allPassed = $false
}

# ============================================================
# CHECK 6: MySQL connection
# ============================================================
Write-Host "  Checking MySQL connection..." -ForegroundColor Gray

$mysql = Join-Path $xamppRoot "mysql\bin\mysql.exe"
$mysqlPass = $null

# Get password from .env
if (Test-Path $envFile) {
    $envContent = Get-Content $envFile -Raw
    if ($envContent -match 'MYSQL_ROOT_PASSWORD\s*=\s*"?([^"\r\n]+)"?') {
        $mysqlPass = $matches[1].Trim()
    }
}

if (-not (Test-Path $mysql)) {
    $checks += @{ Name = "MySQL client"; Status = "❌"; Passed = $false; Fix = "mysql.exe not found" }
    $allPassed = $false
} elseif ([string]::IsNullOrEmpty($mysqlPass)) {
    $checks += @{ Name = "MySQL connection"; Status = "⚠️"; Passed = $true; Note = "MYSQL_ROOT_PASSWORD not set in .env" }
} else {
    # Try to connect
    try {
        $mysqlArgs = @("-uroot", "-p$mysqlPass", "--host=127.0.0.1", "-e", "SELECT 1;")
        $result = & $mysql @mysqlArgs 2>&1
        if ($result -match "ERROR") {
            $checks += @{ Name = "MySQL connection"; Status = "❌"; Passed = $false; Fix = "Access denied - check password in .env" }
            $allPassed = $false
        } else {
            $checks += @{ Name = "MySQL connection"; Status = "✅"; Passed = $true }
        }
    } catch {
        $checks += @{ Name = "MySQL connection"; Status = "❌"; Passed = $false; Fix = "Connection failed" }
        $allPassed = $false
    }
}

# ============================================================
# RESULTS SUMMARY
# ============================================================
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Results:" -ForegroundColor White
Write-Host ""

foreach ($check in $checks) {
    Write-Host "    $($check.Status) $($check.Name)" -ForegroundColor $(if ($check.Passed) { "Gray" } else { "Yellow" })
    if ($check.Note) {
        Write-Host "       $($check.Note)" -ForegroundColor DarkGray
    }
    if ($check.Fix -and -not $check.Passed) {
        Write-Host "       Fix: $($check.Fix)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray

if ($allPassed) {
    Write-Host "  ✅ All checks passed! Environment is ready." -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Some checks failed. Please fix issues above." -ForegroundColor Yellow
}

Write-Host ""
