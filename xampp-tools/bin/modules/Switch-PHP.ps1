# Name: Install PHP Version
# Description: Install additional PHP versions (keeps 8.4 as default)
# Icon: 🔄
# Cmd: install-php
# Order: 13
# Hidden: false

<#
.SYNOPSIS
    Install PHP Version - Download and install additional PHP versions

.DESCRIPTION
    Downloads PHP versions to C:\xampp\php{version} folders:
    - Keeps PHP 8.4 as your main version in C:\xampp\php
    - Installs others to C:\xampp\php74, php80, etc.
    - Useful for testing compatibility or running with Docker/manual configs
    
    Does NOT switch your main Apache installation.
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:XamppRoot = "C:\xampp"
$script:ApacheConfPath = Join-Path $script:XamppRoot "apache\conf\httpd.conf"
$script:ApacheExtraPath = Join-Path $script:XamppRoot "apache\conf\extra"

# PHP Version Registry
$script:PhpVersions = @{
    "7.4" = @{
        Version = "7.4.33"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-7.4.33-Win32-vc15-x64.zip"
        Module = "php7apache2_4.dll"
    }
    "8.0" = @{
        Version = "8.0.30"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.0.30-Win32-vs16-x64.zip"
        Module = "php8apache2_4.dll"
    }
    "8.1" = @{
        Version = "8.1.29"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.1.29-Win32-vs16-x64.zip"
        Module = "php8apache2_4.dll"
    }
    "8.2" = @{
        Version = "8.2.25"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.2.25-Win32-vs16-x64.zip"
        Module = "php8apache2_4.dll"
    }
    "8.3" = @{
        Version = "8.3.15"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.3.15-Win32-vs16-x64.zip"
        Module = "php8apache2_4.dll"
    }
    "8.4" = @{
        Version = "8.4.2"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.4.2-Win32-vs17-x64.zip"
        Module = "php8apache2_4.dll"
    }
}

# ============================================================
# FUNCTIONS
# ============================================================

function Get-CurrentPhpVersion {
    $phpExe = Join-Path $script:XamppRoot "php\php.exe"
    if (Test-Path $phpExe) {
        try {
            $output = & $phpExe -v 2>&1 | Select-Object -First 1
            if ($output -match "PHP (\d+\.\d+)\.") {
                return $matches[1]
            }
        } catch {
            return "Unknown"
        }
    }
    return "Not Installed"
}

function Get-InstalledPhpVersions {
    $installed = @()
    foreach ($ver in $script:PhpVersions.Keys) {
        $phpDir = Join-Path $script:XamppRoot "php$($ver -replace '\.','')"
        if (Test-Path $phpDir) {
            $installed += $ver
        }
    }
    return $installed
}

function Show-PhpVersions {
    $current = Get-CurrentPhpVersion
    $installed = Get-InstalledPhpVersions
    
    Write-Host "  Current PHP Version: " -NoNewline -ForegroundColor White
    Write-Host $current -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Available Versions:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $index = 1
    foreach ($ver in ($script:PhpVersions.Keys | Sort-Object { [version]$_ })) {
        $status = if ($installed -contains $ver) { "[Installed]" } else { "[Not Installed]" }
        $statusColor = if ($installed -contains $ver) { "Green" } else { "Gray" }
        $isCurrent = if ($ver -eq $current) { " ← ACTIVE" } else { "" }
        
        Write-Host "  $index. PHP $ver" -NoNewline -ForegroundColor White
        Write-Host " $status" -NoNewline -ForegroundColor $statusColor
        Write-Host $isCurrent -ForegroundColor Cyan
        Write-Host "     v$($script:PhpVersions[$ver].Version)" -ForegroundColor DarkGray
        Write-Host ""
        $index++
    }
}

function Install-PhpVersion {
    param([string]$Version)
    
    $phpConfig = $script:PhpVersions[$Version]
    $versionClean = $Version -replace '\.',''
    $installDir = Join-Path $script:XamppRoot "php$versionClean"
    $downloadUrl = $phpConfig.DownloadUrl
    
    Write-Host ""
    Write-Host "  Installing PHP $Version" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    # Check if already installed
    if (Test-Path $installDir) {
        Write-Info "PHP $Version already installed at $installDir"
        return $true
    }
    
    # Step 1: Download
    Show-Step "1" "Downloading PHP $Version" "current"
    
    $zipPath = "$env:TEMP\php-$versionClean.zip"
    
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Show-Step "1" "Downloading PHP $Version" "done"
    } catch {
        Show-Step "1" "Downloading PHP $Version" "error"
        Write-Error2 "Failed to download: $($_.Exception.Message)"
        return $false
    }
    
    # Step 2: Extract
    Show-Step "2" "Extracting files" "current"
    
    try {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
        Remove-Item $zipPath -Force
        Show-Step "2" "Extracting files" "done"
        Write-Info "Extracted to: $installDir"
    } catch {
        Show-Step "2" "Extracting files" "error"
        Write-Error2 "Failed to extract: $($_.Exception.Message)"
        return $false
    }
    
    # Step 3: Copy php.ini template
    Show-Step "3" "Configuring php.ini" "current"
    
    $phpIniDev = Join-Path $installDir "php.ini-development"
    $phpIni = Join-Path $installDir "php.ini"
    
    if (Test-Path $phpIniDev) {
        Copy-Item $phpIniDev $phpIni -Force
        
        # Apply basic configuration
        $iniContent = Get-Content $phpIni -Raw
        $iniContent = $iniContent -replace ';extension=curl', 'extension=curl'
        $iniContent = $iniContent -replace ';extension=gd', 'extension=gd'
        $iniContent = $iniContent -replace ';extension=mbstring', 'extension=mbstring'
        $iniContent = $iniContent -replace ';extension=mysqli', 'extension=mysqli'
        $iniContent = $iniContent -replace ';extension=openssl', 'extension=openssl'
        $iniContent = $iniContent -replace ';extension=pdo_mysql', 'extension=pdo_mysql'
        Set-Content -Path $phpIni -Value $iniContent -Force
        
        Show-Step "3" "Configuring php.ini" "done"
    } else {
        Show-Step "3" "Configuring php.ini" "error"
        Write-Warning2 "php.ini-development not found"
    }
    
    Write-Host ""
    Write-Success "PHP $Version installed successfully!"
    
    return $true
}

function Get-VersionChoice {
    param([string]$UserInput)
    
    if ($UserInput -match '^\d+$') {
        $idx = [int]$UserInput - 1
        $versionKeys = @($script:PhpVersions.Keys | Sort-Object { [version]$_ })
        if ($idx -ge 0 -and $idx -lt $versionKeys.Count) {
            return $versionKeys[$idx]
        }
    }
    
    # Check if input matches version directly
    if ($script:PhpVersions.ContainsKey($UserInput)) {
        return $UserInput
    }
    
    return $null
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🔄 Switch PHP Version" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Show available versions
Show-PhpVersions

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Host ""
Write-Host "  🔄 Install PHP Version" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  NOTE: This installs additional PHP versions for testing." -ForegroundColor Yellow
Write-Host "  Your main Apache will continue using PHP 8.4" -ForegroundColor Yellow
Write-Host ""

# Show available versions
Show-PhpVersions

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Get version selection
Write-Host "  Select PHP version to install (number or version like 7.4):" -ForegroundColor White
$selection = (Read-Host "  > ").Trim()

$version = Get-VersionChoice $selection

if (-not $version) {
    Write-Error2 "Invalid selection"
    exit
}

# Don't allow installing 8.4 (already main version)
if ($version -eq "8.4") {
    Write-Warning2 "PHP 8.4 is already your main version in C:\xampp\php"
    exit
}

Write-Host ""
Write-Host "  Selected: PHP $version" -ForegroundColor Yellow
Write-Host ""

if (-not (Prompt-YesNo "Install PHP $version to C:\xampp\php$($version -replace '\.','')?")) {
    Write-Warning2 "Cancelled."
    exit
}

# Install version
$success = Install-PhpVersion -Version $version

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($success) {
    Write-Success "PHP $version installed!"
    Write-Host ""
    Write-Host "  Installed to: C:\xampp\php$($version -replace '\.','')" -ForegroundColor White
    Write-Host ""
    Write-Host "  To use this version:" -ForegroundColor DarkGray
    Write-Host "    - CLI: C:\xampp\php$($version -replace '\.','')\\php.exe" -ForegroundColor Gray
    Write-Host "    - Configure manually in Apache vhosts or Docker" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Your main Apache still uses PHP 8.4 on port 80/443" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Error2 "Switch failed!"
    Write-Host ""
    Write-Host "  Troubleshooting:" -ForegroundColor Yellow
    Write-Host "    - Check Apache error logs in C:\xampp\apache\logs\error.log" -ForegroundColor Gray
    Write-Host "    - Verify PHP module exists in selected version" -ForegroundColor Gray
    exit 1
}
