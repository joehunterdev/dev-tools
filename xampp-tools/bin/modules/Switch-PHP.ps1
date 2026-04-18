# Name: PHP Version Manager
# Description: Switch, install, and manage PHP versions for XAMPP
# Icon: 🐘
# Cmd: install-php
# Order: 13
# Hidden: false

<#
.SYNOPSIS
    PHP Version Manager - Switch active PHP, install versions, rollback safely

.DESCRIPTION
    Full PHP version management for XAMPP:
    - Switch active Apache PHP with backup + rollback
    - Download and install side-folder versions
    - Migrate php.ini settings across versions
    - Patch httpd-xampp.conf LoadFile/LoadModule automatically
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")
. (Join-Path $moduleRoot "bin\Service-Helpers.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile          = Join-Path $moduleRoot ".env"
$_envData                = Load-EnvFile $script:EnvFile
$script:XamppRoot        = if ($_envData['XAMPP_ROOT_DIR']) { $_envData['XAMPP_ROOT_DIR'] } else { "C:\xampp" }
$script:ActivePhpVersion = if ($_envData['PHP_VERSION'])    { $_envData['PHP_VERSION'] }    else { "8.4" }
$script:ApacheExtraPath  = Join-Path $script:XamppRoot "apache\conf\extra"
$script:XamppConfPath    = Join-Path $script:ApacheExtraPath "httpd-xampp.conf"

# PHP Version Registry
$script:PhpVersions = [ordered]@{
    "7.4" = @{
        Version    = "7.4.33"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-7.4.33-Win32-vc15-x64.zip"
        TsDll      = "php7ts.dll"
        Module     = "php7apache2_4.dll"
        VsRuntime  = "vc15"
    }
    "8.0" = @{
        Version    = "8.0.30"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.0.30-Win32-vs16-x64.zip"
        TsDll      = "php8ts.dll"
        Module     = "php8apache2_4.dll"
        VsRuntime  = "vs16"
    }
    "8.1" = @{
        Version    = "8.1.29"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.1.29-Win32-vs16-x64.zip"
        TsDll      = "php8ts.dll"
        Module     = "php8apache2_4.dll"
        VsRuntime  = "vs16"
    }
    "8.2" = @{
        Version    = "8.2.25"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.2.25-Win32-vs16-x64.zip"
        TsDll      = "php8ts.dll"
        Module     = "php8apache2_4.dll"
        VsRuntime  = "vs16"
    }
    "8.3" = @{
        Version    = "8.3.15"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.3.15-Win32-vs16-x64.zip"
        TsDll      = "php8ts.dll"
        Module     = "php8apache2_4.dll"
        VsRuntime  = "vs16"
    }
    "8.4" = @{
        Version    = "8.4.2"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.4.2-Win32-vs17-x64.zip"
        TsDll      = "php8ts.dll"
        Module     = "php8apache2_4.dll"
        VsRuntime  = "vs17"
    }
    "8.5" = @{
        Version    = "8.5.0"
        ThreadSafe = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.5.0-Win32-vs17-x64.zip"
        TsDll      = "php8ts.dll"
        Module     = "php8apache2_4.dll"
        VsRuntime  = "vs17"
    }
}

# ============================================================
# DISPLAY HELPERS
# ============================================================

function Get-CurrentPhpVersion {
    $phpExe = Join-Path $script:XamppRoot "php\php.exe"
    if (Test-Path $phpExe) {
        try {
            $output = & $phpExe -v 2>&1 | Select-Object -First 1
            if ($output -match "PHP (\d+\.\d+\.\d+)") { return $matches[1] }
        } catch {}
    }
    return "Unknown"
}

function Get-InstalledSideFolders {
    $installed = @()
    foreach ($ver in $script:PhpVersions.Keys) {
        $phpDir = Join-Path $script:XamppRoot "php$($ver -replace '\.','')"
        if (Test-Path $phpDir) { $installed += $ver }
    }
    return $installed
}

function Show-PhpStatus {
    $current     = Get-CurrentPhpVersion
    $sideDirs    = Get-InstalledSideFolders
    $activeShort = if ($current -match "^(\d+\.\d+)") { $matches[1] } else { $script:ActivePhpVersion }

    Write-Host ""
    Write-Host "  🐘 PHP Version Manager" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Active : PHP $current  ($($script:XamppRoot)\php)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Available versions:" -ForegroundColor White
    Write-Host ""

    $index = 1
    foreach ($ver in $script:PhpVersions.Keys) {
        $isActive = ($ver -eq $activeShort)
        $isSide   = ($sideDirs -contains $ver)
        $fullVer  = $script:PhpVersions[$ver].Version

        if ($isActive) {
            $icon = "✅"; $tag = " ← ACTIVE"; $color = "Green"
        } elseif ($isSide) {
            $icon = "📦"; $tag = " (installed)"; $color = "Yellow"
        } else {
            $icon = "⚫"; $tag = ""; $color = "DarkGray"
        }

        Write-Host "    $index) $icon PHP $ver  v$fullVer$tag" -ForegroundColor $color
        $index++
    }
    Write-Host ""
}

function Get-VersionChoice {
    param([string]$UserInput)
    $versionKeys = @($script:PhpVersions.Keys)
    if ($UserInput -match '^\d+$') {
        $idx = [int]$UserInput - 1
        if ($idx -ge 0 -and $idx -lt $versionKeys.Count) { return $versionKeys[$idx] }
    }
    if ($script:PhpVersions.ContainsKey($UserInput)) { return $UserInput }
    return $null
}

# ============================================================
# INSTALL (download to side-folder)
# ============================================================

function Install-PhpVersion {
    param([string]$Version)

    $phpConfig  = $script:PhpVersions[$Version]
    $verClean   = $Version -replace '\.',''
    $installDir = Join-Path $script:XamppRoot "php$verClean"

    Write-Host ""
    Write-Host "  Installing PHP $Version to side-folder..." -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $installDir) {
        Write-Info "PHP $Version already at $installDir"
        return $true
    }

    $zipPath = "$env:TEMP\php-$verClean.zip"

    Show-Step "1" "Downloading PHP $($phpConfig.Version)" "current"
    try {
        Invoke-WebRequest -Uri $phpConfig.DownloadUrl -OutFile $zipPath -UseBasicParsing
        Show-Step "1" "Downloading PHP $($phpConfig.Version)" "done"
    } catch {
        Show-Step "1" "Downloading PHP $($phpConfig.Version)" "error"
        Write-Error2 "Download failed: $($_.Exception.Message)"
        return $false
    }

    Show-Step "2" "Extracting to $installDir" "current"
    try {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
        Remove-Item $zipPath -Force
        Show-Step "2" "Extracting" "done"
    } catch {
        Show-Step "2" "Extracting" "error"
        Write-Error2 "Extract failed: $($_.Exception.Message)"
        return $false
    }

    Show-Step "3" "Configuring php.ini" "current"
    $phpIniDev = Join-Path $installDir "php.ini-development"
    $phpIni    = Join-Path $installDir "php.ini"
    if (Test-Path $phpIniDev) {
        Copy-Item $phpIniDev $phpIni -Force
        $ini = Get-Content $phpIni -Raw
        foreach ($ext in @('curl','gd','mbstring','mysqli','openssl','pdo_mysql','intl','zip')) {
            $ini = $ini -replace ";extension=$ext\b", "extension=$ext"
        }
        Set-Content -Path $phpIni -Value $ini -Encoding UTF8
        Show-Step "3" "Configuring php.ini" "done"
    } else {
        Show-Step "3" "php.ini-development not found" "error"
    }

    Write-Host ""
    Write-Success "PHP $Version installed to $installDir"
    return $true
}

# ============================================================
# SWITCH HELPERS
# ============================================================

function Backup-CurrentPhp {
    param([string]$CurrentVersion)
    $ts        = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $script:XamppRoot "php_backup_${CurrentVersion}_${ts}"
    $phpDir    = Join-Path $script:XamppRoot "php"

    Show-Step "B1" "Backing up current PHP ($CurrentVersion)" "current"
    try {
        Copy-Item -Path $phpDir -Destination $backupDir -Recurse -Force
        Show-Step "B1" "Backup → php_backup_${CurrentVersion}_${ts}" "done"
        return $backupDir
    } catch {
        Show-Step "B1" "Backup failed" "error"
        Write-Error2 $_.Exception.Message
        return $null
    }
}

function Swap-PhpFolders {
    param([string]$NewVersion, [string]$OldVersion)
    $phpDir    = Join-Path $script:XamppRoot "php"
    $oldVerDir = Join-Path $script:XamppRoot "php$($OldVersion -replace '\.','')"
    $newVerDir = Join-Path $script:XamppRoot "php$($NewVersion -replace '\.','')"

    Show-Step "S1" "Retiring current php folder" "current"
    try {
        if (-not (Test-Path $oldVerDir)) {
            Rename-Item -Path $phpDir -NewName (Split-Path $oldVerDir -Leaf) -Force
        } else {
            Remove-Item $phpDir -Recurse -Force
        }
        Show-Step "S1" "Retiring current php folder" "done"
    } catch {
        Show-Step "S1" "Retire failed" "error"
        Write-Error2 $_.Exception.Message
        return $false
    }

    Show-Step "S2" "Copying PHP $NewVersion → php" "current"
    try {
        Copy-Item -Path $newVerDir -Destination $phpDir -Recurse -Force
        Show-Step "S2" "Copying PHP $NewVersion → php" "done"
        return $true
    } catch {
        Show-Step "S2" "Copy failed" "error"
        Write-Error2 $_.Exception.Message
        return $false
    }
}

function Patch-ApachePhpConfig {
    param([string]$NewVersion)
    $phpConfig = $script:PhpVersions[$NewVersion]

    if (-not (Test-Path $script:XamppConfPath)) {
        Write-Warning2 "httpd-xampp.conf not found at $($script:XamppConfPath)"
        return $false
    }

    Show-Step "C1" "Patching httpd-xampp.conf" "current"
    try {
        $conf = Get-Content $script:XamppConfPath -Raw
        # Replace TS dll (php7ts.dll, php8ts.dll, etc.)
        $conf = $conf -replace '(?i)(LoadFile\s+"[^"]+/)php\dts\.dll"', "`$1$($phpConfig.TsDll)`""
        # Replace module dll
        $conf = $conf -replace '(?i)(LoadModule\s+php\w+_module\s+"[^"]+/)php\w+apache\w+\.dll"', "`$1$($phpConfig.Module)`""
        Set-Content -Path $script:XamppConfPath -Value $conf -Encoding UTF8
        Show-Step "C1" "Patching httpd-xampp.conf" "done"
        return $true
    } catch {
        Show-Step "C1" "Patch failed" "error"
        Write-Error2 $_.Exception.Message
        return $false
    }
}

function Migrate-PhpIni {
    param([string]$NewVersion, [string]$BackupDir)
    $newPhpIni = Join-Path $script:XamppRoot "php\php.ini"
    $oldPhpIni = Join-Path $BackupDir "php.ini"

    Show-Step "I1" "Migrating php.ini" "current"

    # Prefer managed template from build pipeline
    $templateDist = Join-Path $moduleRoot "config\optimized\dist\php\php.ini"
    if (Test-Path $templateDist) {
        Copy-Item $templateDist $newPhpIni -Force
        Show-Step "I1" "php.ini from managed template" "done"
        return $true
    }

    # Fallback: migrate critical values from old ini
    if (-not (Test-Path $oldPhpIni)) {
        $devIni = Join-Path $script:XamppRoot "php\php.ini-development"
        if (Test-Path $devIni) { Copy-Item $devIni $newPhpIni -Force }
        Show-Step "I1" "php.ini-development used (no old ini found)" "done"
        return $true
    }

    $oldIni    = Get-Content $oldPhpIni -Raw
    $newInySrc = Join-Path $script:XamppRoot "php\php.ini-development"
    $newIni    = if (Test-Path $newInySrc) { Get-Content $newInySrc -Raw } else { $oldIni }

    # Key settings to carry forward
    $keys = @(
        'extension_dir','upload_max_filesize','post_max_size','memory_limit',
        'max_execution_time','date\.timezone','error_reporting','display_errors',
        'log_errors','error_log','curl\.cainfo','openssl\.cafile',
        'session\.save_path','sys_temp_dir'
    )
    foreach ($key in $keys) {
        if ($oldIni -match "(?m)^($key\s*=\s*.+)$") {
            $newIni = $newIni -replace "(?m)^;?$key\s*=.*$", $matches[1]
        }
    }

    # Re-enable extensions that were active
    [regex]::Matches($oldIni, '(?m)^extension=(.+)$') | ForEach-Object {
        $ext    = $_.Groups[1].Value.Trim()
        $newIni = $newIni -replace ";extension=$([regex]::Escape($ext))\b", "extension=$ext"
    }

    Set-Content -Path $newPhpIni -Value $newIni -Encoding UTF8
    Show-Step "I1" "php.ini migrated from backup" "done"
    return $true
}

function Restore-PhpBackup {
    param([string]$BackupDir, [string]$OldVersion)
    Write-Warning2 "Rolling back to PHP $OldVersion..."
    $phpDir    = Join-Path $script:XamppRoot "php"
    $oldVerDir = Join-Path $script:XamppRoot "php$($OldVersion -replace '\.','')"

    if (Test-Path $phpDir) { Remove-Item $phpDir -Recurse -Force -ErrorAction SilentlyContinue }

    if (Test-Path $BackupDir) {
        Copy-Item -Path $BackupDir -Destination $phpDir -Recurse -Force
        Write-Success "PHP folder restored from backup"
    } elseif (Test-Path $oldVerDir) {
        Copy-Item -Path $oldVerDir -Destination $phpDir -Recurse -Force
        Write-Success "PHP folder restored from side-folder"
    } else {
        Write-Error2 "No backup found to restore!"
    }

    $rollbackConf = "$($script:XamppConfPath).rollback"
    if (Test-Path $rollbackConf) {
        Copy-Item $rollbackConf $script:XamppConfPath -Force
        Remove-Item $rollbackConf -Force
        Write-Success "httpd-xampp.conf restored"
    }
    Write-Warning2 "Rollback complete — still on PHP $OldVersion"
}

function Verify-PhpVersion {
    param([string]$ExpectedVersion)
    $phpExe = Join-Path $script:XamppRoot "php\php.exe"
    if (-not (Test-Path $phpExe)) { Write-Error2 "php.exe not found!"; return $false }
    try {
        $out = & $phpExe -v 2>&1 | Select-Object -First 1 | Out-String
        if ($out -match [regex]::Escape($ExpectedVersion)) {
            Write-Success "Verified: $($out.Trim())"
            return $true
        }
        Write-Warning2 "Expected PHP $ExpectedVersion, got: $($out.Trim())"
        if ($out -match "vcruntime|VCRUNTIME") {
            Write-Warning2 "Missing Visual C++ Redistributable ($($script:PhpVersions[$ExpectedVersion.Substring(0,3)].VsRuntime))"
            Write-Host "    Download: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Gray
        }
        return $false
    } catch {
        Write-Error2 "Cannot run php.exe: $($_.Exception.Message)"
        return $false
    }
}

function Update-EnvPhpVersion {
    param([string]$NewVersion)
    $envContent = Get-Content $script:EnvFile -Raw
    $envContent = $envContent -replace '(?m)^PHP_VERSION=.*$', "PHP_VERSION=$NewVersion"
    Set-Content -Path $script:EnvFile -Value $envContent -Encoding UTF8
    $script:ActivePhpVersion = $NewVersion
    Write-Success ".env → PHP_VERSION=$NewVersion"
}

# ============================================================
# SWITCH ORCHESTRATOR
# ============================================================

function Switch-ActivePhp {
    param([string]$Version)
    $phpConfig    = $script:PhpVersions[$Version]
    $verClean     = $Version -replace '\.',''
    $sideDir      = Join-Path $script:XamppRoot "php$verClean"
    $currentFull  = Get-CurrentPhpVersion
    $currentShort = if ($currentFull -match "^(\d+\.\d+)") { $matches[1] } else { $script:ActivePhpVersion }

    Write-Host ""
    Write-Host "  Switching PHP $currentShort → $Version" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    # Ensure side-folder exists
    if (-not (Test-Path $sideDir)) {
        Write-Info "PHP $Version not downloaded yet — installing side-folder first..."
        if (-not (Install-PhpVersion -Version $Version)) {
            Write-Error2 "Cannot switch — download failed"
            return $false
        }
    }

    # Pre-flight
    Open-XamppControlPanel
    Show-XamppStatus
    if (-not (Prompt-YesNo "  Stop services and switch to PHP $Version?")) {
        Write-Warning2 "Cancelled."
        return $false
    }

    Write-Info "Stopping services..."
    Invoke-XamppStop
    Show-XamppStatus

    # Save rollback copy of conf
    Copy-Item $script:XamppConfPath "$($script:XamppConfPath).rollback" -Force -ErrorAction SilentlyContinue

    # Backup current php folder
    $backupDir = Backup-CurrentPhp -CurrentVersion $currentShort
    if (-not $backupDir) { Invoke-XamppStart; return $false }

    # Swap folders
    if (-not (Swap-PhpFolders -NewVersion $Version -OldVersion $currentShort)) {
        Restore-PhpBackup -BackupDir $backupDir -OldVersion $currentShort
        Invoke-XamppStart
        return $false
    }

    # Patch Apache conf
    Patch-ApachePhpConfig -NewVersion $Version | Out-Null

    # Migrate php.ini
    Migrate-PhpIni -NewVersion $Version -BackupDir $backupDir

    # Validate Apache config
    Write-Info "Testing Apache config syntax..."
    $test = Test-ApacheConfigSyntax
    if (-not $test.Success) {
        Write-Error2 "Apache config FAILED — rolling back"
        Write-Host "    $($test.Output)" -ForegroundColor Red
        Restore-PhpBackup -BackupDir $backupDir -OldVersion $currentShort
        Invoke-XamppStart
        return $false
    }
    Write-Success "Apache config OK"

    # Start and verify
    Write-Info "Starting services..."
    Invoke-XamppStart
    Show-XamppStatus
    Verify-PhpVersion -ExpectedVersion $phpConfig.Version | Out-Null

    # Update .env
    Update-EnvPhpVersion -NewVersion $Version

    # Cleanup
    Remove-Item "$($script:XamppConfPath).rollback" -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Success "Successfully switched to PHP $Version"
    return $true
}

# ============================================================
# REMOVE SIDE FOLDER
# ============================================================

function Remove-PhpSideFolder {
    param([string]$Version)
    $verClean = $Version -replace '\.',''
    $sideDir  = Join-Path $script:XamppRoot "php$verClean"

    if (-not (Test-Path $sideDir)) { Write-Warning2 "PHP $Version not installed"; return }
    if (Prompt-YesNo "  Remove PHP $Version from $sideDir?") {
        Remove-Item $sideDir -Recurse -Force
        Write-Success "PHP $Version removed"
    }
}

# ============================================================
# MAIN MENU
# ============================================================

Show-Header

do {
    Show-PhpStatus

    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "    1) Switch active PHP version    (full swap + restart)" -ForegroundColor Gray
    Write-Host "    2) Install PHP to side-folder   (download only)" -ForegroundColor Gray
    Write-Host "    3) Remove side-folder version" -ForegroundColor Gray
    Write-Host "    4) Rebuild php.ini from template" -ForegroundColor Gray
    Write-Host "    0) Back" -ForegroundColor DarkGray
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    $choice = (Read-Host "  >").Trim()
    Write-Host ""

    switch ($choice) {

        '1' {
            Show-PhpStatus
            Write-Host "  Select version to switch TO:" -ForegroundColor White
            $sel = (Read-Host "  >").Trim()
            $ver = Get-VersionChoice $sel
            if (-not $ver) { Write-Error2 "Invalid selection"; break }
            $activeShort = if ((Get-CurrentPhpVersion) -match "^(\d+\.\d+)") { $matches[1] } else { $script:ActivePhpVersion }
            if ($ver -eq $activeShort) { Write-Info "PHP $ver is already active"; break }
            Switch-ActivePhp -Version $ver | Out-Null
        }

        '2' {
            Show-PhpStatus
            Write-Host "  Select version to install:" -ForegroundColor White
            $sel = (Read-Host "  >").Trim()
            $ver = Get-VersionChoice $sel
            if (-not $ver) { Write-Error2 "Invalid selection"; break }
            Install-PhpVersion -Version $ver | Out-Null
        }

        '3' {
            Show-PhpStatus
            Write-Host "  Select version to remove:" -ForegroundColor White
            $sel = (Read-Host "  >").Trim()
            $ver = Get-VersionChoice $sel
            if (-not $ver) { Write-Error2 "Invalid selection"; break }
            $activeShort = if ((Get-CurrentPhpVersion) -match "^(\d+\.\d+)") { $matches[1] } else { $script:ActivePhpVersion }
            if ($ver -eq $activeShort) { Write-Warning2 "Cannot remove the active version"; break }
            Remove-PhpSideFolder -Version $ver
        }

        '4' {
            $templateDist = Join-Path $moduleRoot "config\optimized\dist\php\php.ini"
            $activePhpIni = Join-Path $script:XamppRoot "php\php.ini"
            if (-not (Test-Path $templateDist)) {
                Write-Warning2 "No dist php.ini found — run 'build-configs' first"
                break
            }
            if (Prompt-YesNo "  Overwrite $activePhpIni with managed template?") {
                Copy-Item $templateDist $activePhpIni -Force
                Write-Success "php.ini rebuilt from template"
            }
        }

        '0' { break }

        default { Write-Warning2 "Invalid option" }
    }

    if ($choice -ne '0') {
        Write-Host ""
        Prompt-Continue
    }

} while ($choice -ne '0')
