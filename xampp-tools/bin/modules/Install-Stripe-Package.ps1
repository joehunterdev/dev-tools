# Name: Install Package
# Description: Install development packages (Stripe CLI, Composer, etc)
# Icon: 📦
# Cmd: install-package
# Order: 12
# Hidden: false

<#
.SYNOPSIS
    Install Package - Install CLI tools and development packages

.DESCRIPTION
    Installs development packages for use with XAMPP:
    1. Downloads and installs the package
    2. Adds to PATH environment variable
    3. Optionally adds to SRP whitelist
    4. Verifies installation
    
    Available packages:
    - Stripe CLI (for webhook testing)
    - Composer (PHP dependency manager)
    - Node.js (JavaScript runtime)
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:BackupDir = Join-Path $moduleRoot "backups"
$script:SrpConfigPath = "C:\Windows\SoftwarePolicy\softwarepolicy.ini"

# Package registry
$script:Packages = @{
    "stripe-cli" = @{
        Name = "Stripe CLI"
        Description = "Stripe command-line tool for webhooks and API testing"
        InstallDir = "C:\stripe-cli"
        DownloadUrl = "https://github.com/stripe/stripe-cli/releases/latest/download/stripe_latest_windows_x86_64.zip"
        ExecutableName = "stripe.exe"
        VerifyCommand = "stripe --version"
        RequiresExtraction = $true
        AddToPath = $true
        AddToSrp = $true
    }
    "composer" = @{
        Name = "Composer"
        Description = "PHP dependency manager"
        InstallDir = "C:\composer"
        DownloadUrl = "https://getcomposer.org/Composer-Setup.exe"
        ExecutableName = "composer.phar"
        VerifyCommand = "composer --version"
        RequiresExtraction = $false
        AddToPath = $true
        AddToSrp = $true
    }
}

# ============================================================
# FUNCTIONS
# ============================================================

function Show-AvailablePackages {
    Write-Host "  Available Packages:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $index = 1
    foreach ($pkg in $script:Packages.GetEnumerator()) {
        Write-Host "  $index. $($pkg.Value.Name)" -ForegroundColor White
        Write-Host "     $($pkg.Value.Description)" -ForegroundColor Gray
        Write-Host "     Install to: $($pkg.Value.InstallDir)" -ForegroundColor DarkGray
        Write-Host ""
        $index++
    }
}

function Get-PackageChoice {
    param([string]$Input)
    
    if ($Input -match '^\d+$') {
        $idx = [int]$Input - 1
        $packageKeys = @($script:Packages.Keys)
        if ($idx -ge 0 -and $idx -lt $packageKeys.Count) {
            return $packageKeys[$idx]
        }
    }
    
    # Check if input matches package key directly
    if ($script:Packages.ContainsKey($Input.ToLower())) {
        return $Input.ToLower()
    }
    
    return $null
}

function Install-DevPackage {
    param(
        [hashtable]$Package,
        [string]$PackageKey
    )
    
    $installDir = $Package.InstallDir
    $downloadUrl = $Package.DownloadUrl
    $executableName = $Package.ExecutableName
    
    # Step 1: Create installation directory
    Show-Step "1" "Creating installation directory" "current"
    if (!(Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Show-Step "1" "Creating installation directory" "done"
        Write-Info "Created: $installDir"
    } else {
        Show-Step "1" "Creating installation directory" "done"
        Write-Info "Directory exists: $installDir"
    }
    
    # Step 2: Download package
    Show-Step "2" "Downloading $($Package.Name)" "current"
    
    $fileExtension = if ($Package.RequiresExtraction) { ".zip" } else { ".exe" }
    $downloadPath = "$env:TEMP\$PackageKey$fileExtension"
    
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
        Show-Step "2" "Downloading $($Package.Name)" "done"
    } catch {
        Show-Step "2" "Downloading $($Package.Name)" "error"
        Write-Error2 "Failed to download: $($_.Exception.Message)"
        return $false
    }
    
    # Step 3: Extract or copy files
    Show-Step "3" "Installing files" "current"
    
    try {
        if ($Package.RequiresExtraction) {
            Expand-Archive -Path $downloadPath -DestinationPath $installDir -Force
            Show-Step "3" "Installing files" "done"
            Write-Info "Extracted to: $installDir"
        } else {
            Copy-Item $downloadPath -Destination (Join-Path $installDir $executableName) -Force
            Show-Step "3" "Installing files" "done"
            Write-Info "Installed to: $installDir"
        }
        
        # Clean up download
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
    } catch {
        Show-Step "3" "Installing files" "error"
        Write-Error2 "Failed to install: $($_.Exception.Message)"
        return $false
    }
    
    # Step 4: Add to PATH
    if ($Package.AddToPath) {
        Show-Step "4" "Adding to PATH" "current"
        
        $userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
        
        if ($userPath -notlike "*$installDir*") {
            $newPath = "$userPath;$installDir"
            [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::User)
            $env:Path = "$env:Path;$installDir"
            
            Show-Step "4" "Adding to PATH" "done"
            Write-Info "Added to User PATH"
        } else {
            Show-Step "4" "Adding to PATH" "done"
            Write-Info "Already in PATH"
        }
    }
    
    # Step 5: Add to SRP whitelist (optional)
    if ($Package.AddToSrp -and (Test-Path $script:SrpConfigPath)) {
        Show-Step "5" "Adding to SRP whitelist" "current"
        
        if (Test-AdminRights) {
            $srpResult = Add-PackageToSrp -InstallDir $installDir -PackageName $Package.Name
            if ($srpResult) {
                Show-Step "5" "Adding to SRP whitelist" "done"
                Write-Info "Added to SRP config"
            } else {
                Show-Step "5" "Adding to SRP whitelist" "error"
                Write-Warning2 "Could not add to SRP (requires admin)"
            }
        } else {
            Show-Step "5" "Adding to SRP whitelist" "done"
            Write-Info "Skipped (not admin)"
        }
    }
    
    # Step 6: Verify installation
    $stepNum = if ($Package.AddToSrp) { 6 } else { 5 }
    Show-Step "$stepNum" "Verifying installation" "current"
    
    $executablePath = Join-Path $installDir $executableName
    if (Test-Path $executablePath) {
        Show-Step "$stepNum" "Verifying installation" "done"
        
        # Try to get version
        if ($Package.VerifyCommand) {
            try {
                $output = Invoke-Expression $Package.VerifyCommand 2>&1
                Write-Info $output
            } catch {
                Write-Info "Installed at: $executablePath"
            }
        }
        
        return $true
    } else {
        Show-Step "$stepNum" "Verifying installation" "error"
        Write-Error2 "$executableName not found at $executablePath"
        return $false
    }
}

function Test-AdminRights {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-PackageToSrp {
    param(
        [string]$InstallDir,
        [string]$PackageName
    )
    
    try {
        $content = Get-Content $script:SrpConfigPath -Raw
        
        # Check if package already exists
        if ($content -match [regex]::Escape("; Package: $PackageName")) {
            return $true
        }
        
        # Add package section
        $newSection = @"
; Package: $PackageName
$InstallDir=1
$InstallDir\*=1

"@
        
        if ($content -match "; ✅ Allow Custom User Paths") {
            $content = $content -replace "(; ✅ Allow Custom User Paths)", "$newSection`$1"
        } else {
            $content = $content.TrimEnd() + "`n`n$newSection"
        }
        
        Set-Content -Path $script:SrpConfigPath -Value $content -Force
        
        # Restart SRP service
        Restart-Service -Name "AppIDSvc" -Force -ErrorAction SilentlyContinue
        
        return $true
    } catch {
        return $false
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  📦 Install Package" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Show available packages
Show-AvailablePackages

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Get package selection
Write-Host "  Select a package to install (number or name):" -ForegroundColor White
$selection = Read-Host "  > "

$packageKey = Get-PackageChoice $selection

if (-not $packageKey) {
    Write-Error2 "Invalid selection"
    exit
}

$package = $script:Packages[$packageKey]

Write-Host ""
Write-Host "  Selected: $($package.Name)" -ForegroundColor Yellow
Write-Host "  $($package.Description)" -ForegroundColor Gray
Write-Host ""

if (-not (Prompt-YesNo "Install $($package.Name)?")) {
    Write-Warning2 "Cancelled."
    exit
}

Write-Host ""

# Install package
$success = Install-DevPackage -Package $package -PackageKey $packageKey

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($success) {
    Write-Success "$($package.Name) installed successfully!"
    
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor DarkGray
    
    if ($packageKey -eq "stripe-cli") {
        Write-Host "    1. Restart your terminal to use 'stripe' command" -ForegroundColor Gray
        Write-Host "    2. Run: stripe login" -ForegroundColor Gray
        Write-Host "    3. Run: stripe listen --forward-to http://yoursite.local/stripe/webhook" -ForegroundColor Gray
    }
    
    Write-Host ""
} else {
    Write-Error2 "Installation failed!"
    exit 1
}
