# Name: Create Alias
# Description: Create command aliases (find & replace)
# Icon: 🔗
# Cmd: alias
# Order: 16

<#
.SYNOPSIS
    Create Alias - Create simple command replacements

.DESCRIPTION
    Create aliases that directly replace one command with another.
    The alias literally executes the command you specify - nothing more.
    
    Examples:
    - pas → php artisan
    - cp → composer
    - np → npm
    - gst → git status
    
    When you type "pas", it runs "php artisan"
    When you type "gst", it runs "git status"

.NOTES
    Aliases stored as batch files in bin\aliases\
    Works in cmd.exe and PowerShell
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:AliasesDir = Join-Path $moduleRoot "bin\aliases"

# ============================================================
# FUNCTIONS
# ============================================================

function New-AliasFile {
    param(
        [string]$AliasName,
        [string]$Command
    )
    
    $batchPath = Join-Path $script:AliasesDir "$AliasName.bat"
    # Create batch file that executes the exact command with all arguments passed through
    $batchContent = "@echo off`r`n$Command %*"
    
    try {
        Set-Content -Path $batchPath -Value $batchContent -Encoding ASCII -Force
        return @{ Success = $true }
    } catch {
        return @{ Success = $false; Error = $_ }
    }
}

function Add-PathEnvironment {
    try {
        $pathVar = [Environment]::GetEnvironmentVariable("PATH", "User")
        
        if (-not ($pathVar -like "*$script:AliasesDir*")) {
            $newPath = "$script:AliasesDir;$pathVar"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            return @{ Success = $true; Added = $true }
        }
        return @{ Success = $true; Added = $false }
    } catch {
        return @{ Success = $false; Error = $_ }
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host "  Create Alias" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Enter the command to replace:" -ForegroundColor White
Write-Host "  Examples:" -ForegroundColor Gray
Write-Host "    php artisan" -ForegroundColor Gray
Write-Host "    composer" -ForegroundColor Gray
Write-Host "    npm" -ForegroundColor Gray
Write-Host "    git status" -ForegroundColor Gray
Write-Host ""

$command = Read-Host "  Command"

if ([string]::IsNullOrEmpty($command)) {
    Write-Error2 "Command cannot be empty"
    Write-Host ""
    exit
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Enter the alias name:" -ForegroundColor White
Write-Host "  Examples:" -ForegroundColor Gray
Write-Host "    pas (for php artisan)" -ForegroundColor Gray
Write-Host "    cp (for composer)" -ForegroundColor Gray
Write-Host "    np (for npm)" -ForegroundColor Gray
Write-Host "    gst (for git status)" -ForegroundColor Gray
Write-Host ""

$aliasName = Read-Host "  Alias"

if ([string]::IsNullOrEmpty($aliasName)) {
    Write-Error2 "Alias name cannot be empty"
    Write-Host ""
    exit
}

# Validate alias name
if ($aliasName -notmatch '^[a-zA-Z0-9_\-]+$') {
    Write-Error2 "Invalid alias name. Use only letters, numbers, underscores, and hyphens."
    Write-Host ""
    exit
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Create alias:" -ForegroundColor White
Write-Host "    $aliasName" -ForegroundColor Yellow -NoNewline
Write-Host " → $command" -ForegroundColor Gray
Write-Host ""
Write-Host "  (When you type '$aliasName', it will run '$command')" -ForegroundColor Gray
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

# Create aliases directory
if (-not (Test-Path $script:AliasesDir)) {
    Write-Info "Creating aliases directory..."
    try {
        New-Item -ItemType Directory -Path $script:AliasesDir -Force | Out-Null
        Write-Success "  Directory created"
    } catch {
        Write-Error2 "Cannot create aliases directory: $_"
        Write-Host ""
        exit
    }
}

# Create batch file
Write-Info "Creating alias batch file..."

$result = New-AliasFile -AliasName $aliasName -Command $command

if ($result.Success) {
    Write-Success "Alias created!"
} else {
    Write-Error2 "Failed to create alias: $($result.Error)"
    Write-Host ""
    exit
}

# Add to PATH
Write-Info "Updating PATH..."

$pathResult = Add-PathEnvironment

if ($pathResult.Success) {
    if ($pathResult.Added) {
        Write-Success "Added aliases folder to PATH"
    } else {
        Write-Success "Aliases folder already in PATH"
    }
} else {
    Write-Warning "Could not update PATH: $($pathResult.Error)"
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Success "Setup complete!"
Write-Host ""
Write-Host "  Your new alias:" -ForegroundColor White
Write-Host "    $aliasName" -ForegroundColor Yellow -NoNewline
Write-Host " → $command" -ForegroundColor Gray
Write-Host ""
Write-Host "  Try it now:" -ForegroundColor Gray
Write-Host "    $aliasName" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Note: Restart cmd/PowerShell for PATH to take effect" -ForegroundColor Gray
Write-Host ""

