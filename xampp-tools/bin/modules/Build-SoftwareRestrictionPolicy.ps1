# Name: Build SRP Config
# Description: Build Software Restriction Policy config from template
# Icon: 🔒
# Cmd: build-srp
# Order: 6
# Hidden: true

<#
.SYNOPSIS
    Build SRP Config - Compile SRP template to dist/

.DESCRIPTION
    Builds Software Restriction Policy config:
    1. Validates SRP is installed (checks ini file access)
    2. Backs up current SRP configuration
    3. Compiles SRP template from config/optimized/templates/softwarepolicy/
    4. Generates dist/softwarepolicy/softwarepolicy.ini with environment variables
    
    Deploy separately with 'deploy-srp'
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:Config = Load-FilesConfig $moduleRoot
$script:SrpConfigPath = "C:\Windows\SoftwarePolicy\softwarepolicy.ini"
$script:TemplatesDir = Join-Path $moduleRoot $script:Config.templates.sourceDir
$script:DistDir = Join-Path $moduleRoot $script:Config.templates.distDir
$script:BackupDir = Join-Path $moduleRoot "backups"

if (-not $script:Config) {
    Write-Error2 "Could not load config/config.json"
    exit
}

# ============================================================
# FUNCTIONS
# ============================================================

function Test-SrpPrerequisites {
    <#
    .SYNOPSIS
        Check if SRP is installed and accessible
    #>
    
    # Check if SRP config exists
    if (-not (Test-Path $script:SrpConfigPath)) {
        return @{ Valid = $false; Error = "SRP config not found at $script:SrpConfigPath" }
    }
    
    # Check read access
    try {
        $null = Get-Content $script:SrpConfigPath -Raw
    } catch {
        return @{ Valid = $false; Error = "Cannot read SRP config: $($_.Exception.Message)" }
    }
    
    # Check if running as admin (needed for write)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return @{ Valid = $false; Error = "Administrator rights required" }
    }
    
    return @{ Valid = $true }
}

function Backup-SrpConfig {
    <#
    .SYNOPSIS
        Backup SRP config to daily backup folder
    #>
    
    # Create daily backup folder
    $today = Get-Date -Format "yyyy-MM-dd"
    $backupDayDir = Join-Path $script:BackupDir $today
    $srpBackupDir = Join-Path $backupDayDir "softwarepolicy"
    
    if (-not (Test-Path $srpBackupDir)) {
        New-Item -ItemType Directory -Path $srpBackupDir -Force | Out-Null
    }
    
    $srpBackupPath = Join-Path $srpBackupDir "softwarepolicy.ini"
    
    try {
        Copy-Item $script:SrpConfigPath $srpBackupPath -Force
        return @{ Success = $true; Path = $srpBackupPath }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Build-SrpConfigFromTemplate {
    <#
    .SYNOPSIS
        Build SRP config from template with environment variables
    #>
    
    param(
        [string]$TemplatePath,
        [string]$OutputPath,
        [hashtable]$EnvVars
    )
    
    if (-not (Test-Path $TemplatePath)) {
        return @{ Success = $false; Error = "Template not found: $TemplatePath" }
    }
    
    try {
        $content = Get-Content $TemplatePath -Raw
        
        # Build XAMPP paths section
        $xamppRoot = if ($EnvVars['XAMPP_ROOT_DIR']) { $EnvVars['XAMPP_ROOT_DIR'] } else { "C:\xampp" }
        $xamppPaths = @(
            "$xamppRoot=1"
            "$xamppRoot\apache=1"
            "$xamppRoot\apache\bin=1"
            "$xamppRoot\apache\bin\httpd.exe=1"
            "$xamppRoot\mysql=1"
            "$xamppRoot\mysql\bin=1"
            "$xamppRoot\mysql\bin\mysqld.exe=1"
            "$xamppRoot\php=1"
            "$xamppRoot\php\php.exe=1"
        ) -join "`n"
        
        # Build dev-tools paths section
        $devToolsRoot = if ($EnvVars['DEVTOOLS_ROOT']) { $EnvVars['DEVTOOLS_ROOT'] } else { Split-Path (Split-Path $moduleRoot -Parent) -Parent }
        $devtoolsPaths = @(
            "$devToolsRoot=1"
            "$devToolsRoot\xampp-tools=1"
            "$devToolsRoot\xampp-tools\bin=1"
            "$devToolsRoot\xampp-tools\bin\*.ps1=1"
            "$devToolsRoot\xampp-tools\bin\modules=1"
            "$devToolsRoot\xampp-tools\bin\modules\*.ps1=1"
        ) -join "`n"
        
        # Build user custom paths section (empty by default, user can add manually)
        $userCustomPaths = "; Add custom user paths here`n; C:\path\to\app=1"
        
        # Replace placeholders
        $content = $content -replace [regex]::Escape("{{XAMPP_PATHS}}"), $xamppPaths
        $content = $content -replace [regex]::Escape("{{DEVTOOLS_PATHS}}"), $devtoolsPaths
        $content = $content -replace [regex]::Escape("{{USER_CUSTOM_PATHS}}"), $userCustomPaths
        
        # Check for any unreplaced placeholders (should be none after above replacements)
        $unreplaced = [regex]::Matches($content, '\{\{([^}]+)\}\}')
        if ($unreplaced.Count -gt 0) {
            $missing = ($unreplaced | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique) -join ", "
            Write-Warning "    Unreplaced SRP placeholders: $missing"
        }
        
        # Ensure output directory exists
        $outputDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Write output
        Set-Content -Path $OutputPath -Value $content -NoNewline
        
        return @{ Success = $true }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🔒 Build SRP Config" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check .env
if (-not (Test-Path $script:EnvFile)) {
    Write-Error2 ".env file not found!"
    exit
}

# Load env
$envData = Load-EnvFile $script:EnvFile

Write-Host "  SRP Config: $($script:SrpConfigPath)" -ForegroundColor Gray
Write-Host "  Templates:  $($script:TemplatesDir)" -ForegroundColor Gray
Write-Host "  Output:     $($script:DistDir)" -ForegroundColor Gray
Write-Host ""

# Step 1: Check SRP prerequisites
Write-Host "  Step 1: Checking SRP prerequisites..." -ForegroundColor Yellow
Write-Host ""

$srpCheck = Test-SrpPrerequisites
if (-not $srpCheck.Valid) {
    Write-Error2 $srpCheck.Error
    Write-Host ""
    Write-Host "  To use SRP features, please:" -ForegroundColor DarkGray
    Write-Host "    1. Install Software Restriction Policy" -ForegroundColor DarkGray
    Write-Host "    2. Run PowerShell as Administrator" -ForegroundColor DarkGray
    Write-Host ""
    exit
}

Write-Success "SRP is installed and accessible"
Write-Host ""

# Check template exists
$srpTemplateFile = Join-Path $script:TemplatesDir "softwarepolicy\softwarepolicy.ini.template"
if (-not (Test-Path $srpTemplateFile)) {
    Write-Error2 "SRP template not found: softwarepolicy\softwarepolicy.ini.template"
    exit
}

Write-Success "SRP template found"
Write-Host ""

# Step 2: Backup current SRP config
Write-Host "  Step 2: Backing up current SRP configuration..." -ForegroundColor Yellow
Write-Host ""

$backupResult = Backup-SrpConfig
if ($backupResult.Success) {
    $relativePath = $backupResult.Path -replace [regex]::Escape($moduleRoot), "."
    Write-Success "Backed up to: $relativePath"
} else {
    Write-Warning2 "Backup failed: $($backupResult.Error)"
}

Write-Host ""

# Step 3: Build from template
Write-Host "  Step 3: Building SRP config from template..." -ForegroundColor Yellow
Write-Host ""

$srpOutputPath = Join-Path $script:DistDir "softwarepolicy\softwarepolicy.ini"

$buildResult = Build-SrpConfigFromTemplate -TemplatePath $srpTemplateFile -OutputPath $srpOutputPath -EnvVars $envData

if ($buildResult.Success) {
    $relativePath = $srpOutputPath -replace [regex]::Escape($moduleRoot), "."
    Write-Success "Built: $relativePath"
} else {
    Write-Error2 "Build failed: $($buildResult.Error)"
    exit
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Success "SRP config built successfully"

Write-Host ""
Write-Host "  Next step:" -ForegroundColor DarkGray
Write-Host "    • Run 'deploy-srp' to deploy config and manage SRP service" -ForegroundColor DarkGray
Write-Host ""
