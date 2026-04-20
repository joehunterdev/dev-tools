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
        Version     = "7.4.33"
        ThreadSafe  = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-7.4.33-Win32-vc15-x64.zip"
        TsDll       = "php7ts.dll"
        Module      = "php7apache2_4.dll"
        VsRuntime   = "vc15"
        # Visual C++ 2015-2019 Redistributable
        VsRuntimeUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
        Quirks      = @(
            'opcache-dll'           # needs zend_extension=php_opcache.dll
        )
    }
    "8.0" = @{
        Version     = "8.0.30"
        ThreadSafe  = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.0.30-Win32-vs16-x64.zip"
        TsDll       = "php8ts.dll"
        Module      = "php8apache2_4.dll"
        VsRuntime   = "vs16"
        VsRuntimeUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
        Quirks      = @(
            'opcache-dll'
        )
    }
    "8.1" = @{
        Version     = "8.1.34"
        ThreadSafe  = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.1.34-Win32-vs16-x64.zip"
        TsDll       = "php8ts.dll"
        Module      = "php8apache2_4.dll"
        VsRuntime   = "vs16"
        VsRuntimeUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
        Quirks      = @(
            'opcache-dll'
        )
    }
    "8.2" = @{
        Version     = "8.2.30"
        ThreadSafe  = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.2.30-Win32-vs16-x64.zip"
        TsDll       = "php8ts.dll"
        Module      = "php8apache2_4.dll"
        VsRuntime   = "vs16"
        VsRuntimeUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
        Quirks      = @(
            'opcache-dll'
        )
    }
    "8.3" = @{
        Version     = "8.3.30"
        ThreadSafe  = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.3.30-Win32-vs16-x64.zip"
        TsDll       = "php8ts.dll"
        Module      = "php8apache2_4.dll"
        VsRuntime   = "vs16"
        VsRuntimeUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
        Quirks      = @(
            'opcache-dll'
        )
    }
    "8.4" = @{
        Version     = "8.4.20"
        ThreadSafe  = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.4.20-Win32-vs17-x64.zip"
        TsDll       = "php8ts.dll"
        Module      = "php8apache2_4.dll"
        VsRuntime   = "vs17"
        # Visual C++ 2022 Redistributable
        VsRuntimeUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        Quirks      = @(
            'opcache-builtin'       # statically compiled, no DLL — comment out zend_extension=opcache
        )
    }
    "8.5" = @{
        Version     = "8.5.5"
        ThreadSafe  = $true
        DownloadUrl = "https://windows.php.net/downloads/releases/php-8.5.5-Win32-vs17-x64.zip"
        TsDll       = "php8ts.dll"
        Module      = "php8apache2_4.dll"
        VsRuntime   = "vs17"
        VsRuntimeUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        Quirks      = @(
            'opcache-builtin'
        )
    }
}

# ============================================================
# LIVE URL RESOLVER
# (Get-WindowsPhpConfig / Show-WindowsPhpConfig are in Common.ps1)
# ============================================================

function Resolve-PhpDownloadUrl {
    <#
    Queries the windows.php.net releases.json API for the latest Thread Safe zip
    matching the requested major.minor version and system arch.
    Returns @{ Url; Version; Sha256 } or $null on failure.
    #>
    param(
        [string]$MajorMinor,   # e.g. "8.3"
        [string]$Arch = "x64"
    )

    try {
        $json = Invoke-WebRequest 'https://windows.php.net/downloads/releases/releases.json' `
            -UseBasicParsing -TimeoutSec 15 | ConvertFrom-Json

        $verData = $json.$MajorMinor
        if (-not $verData) {
            Write-Warning2 "No releases.json entry for PHP $MajorMinor"
            return $null
        }

        # Try runtimes in priority order (newest first)
        foreach ($rt in @('vs17', 'vs16', 'vc15')) {
            $key   = "ts-$rt-$Arch"
            $entry = $verData.$key
            if ($entry -and $entry.zip -and $entry.zip.path) {
                $file    = $entry.zip.path
                $sha256  = $entry.zip.sha256
                $version = if ($file -match 'php-(\d+\.\d+\.\d+)-') { $matches[1] } else { $MajorMinor }
                return @{
                    Url     = "https://windows.php.net/downloads/releases/$file"
                    Version = $version
                    Sha256  = $sha256
                }
            }
        }
        Write-Warning2 "No TS $Arch build found for PHP $MajorMinor in releases.json"
    } catch {
        Write-Warning2 "Could not fetch releases.json: $($_.Exception.Message)"
    }
    return $null
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
    Write-Host "  Active : PHP $current  ($($script:XamppRoot + '\php'))" -ForegroundColor White
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

    # Resolve live URL first, fall back to registry URL
    $sysCfg  = Get-WindowsPhpConfig
    $resolved = Resolve-PhpDownloadUrl -MajorMinor $Version -Arch $sysCfg.Arch
    if ($resolved) {
        $downloadUrl = $resolved.Url
        $displayVer  = $resolved.Version
        $sha256      = $resolved.Sha256
    } else {
        $downloadUrl = $phpConfig.DownloadUrl
        $displayVer  = if ($downloadUrl -match 'php-(\d+\.\d+\.\d+)-') { $matches[1] } else { $phpConfig.Version }
        $sha256      = $null
    }

    Show-Step "1" "Downloading PHP $displayVer ($($sysCfg.Arch))" "current"
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        # Verify SHA256 if available
        if ($sha256) {
            $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
            if ($actual -ne $sha256.ToUpper()) {
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                Show-Step "1" "Downloading PHP $displayVer" "error"
                Write-Error2 "SHA256 mismatch — download may be corrupt."
                Write-Host "    Expected: $sha256" -ForegroundColor DarkGray
                Write-Host "    Actual  : $actual" -ForegroundColor DarkGray
                return $false
            }
        }
        Show-Step "1" "Downloading PHP $displayVer ($($sysCfg.Arch))" "done"
    } catch {
        Show-Step "1" "Downloading PHP $displayVer" "error"
        Write-Error2 "Download failed: $($_.Exception.Message)"
        Write-Host "    URL: $downloadUrl" -ForegroundColor DarkGray
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
    $phpDir = Join-Path $script:XamppRoot "php"

    # ── Priority 1: per-version curated config in config/php/php-X.Y.ini ──
    $versionConfig = Join-Path $moduleRoot "config\php\php-$NewVersion.ini"
    if (Test-Path $versionConfig) {
        $content = Get-Content $versionConfig -Raw
        $content = Repair-PhpIni -PhpIniContent $content -PhpVersion $NewVersion -PhpDir $phpDir
        Set-Content $newPhpIni $content -Encoding UTF8
        Show-Step "I1" "php.ini from version config (config/php/php-$NewVersion.ini)" "done"
        return $true
    }

    # ── Priority 2: managed template from build pipeline ──────────────────
    $templateDist = Join-Path $moduleRoot "config\optimized\dist\php\php.ini"
    if (Test-Path $templateDist) {
        $content = Get-Content $templateDist -Raw
        $content = Repair-PhpIni -PhpIniContent $content -PhpVersion $NewVersion -PhpDir $phpDir
        Set-Content $newPhpIni $content -Encoding UTF8
        Show-Step "I1" "php.ini from managed template" "done"
        return $true
    }

    # ── Priority 3: migrate critical values from old ini ──────────────────
    if (-not (Test-Path $oldPhpIni)) {
        $devIni = Join-Path $phpDir "php.ini-development"
        if (Test-Path $devIni) {
            $content = Get-Content $devIni -Raw
            $content = Repair-PhpIni -PhpIniContent $content -PhpVersion $NewVersion -PhpDir $phpDir
            Set-Content $newPhpIni $content -Encoding UTF8
        }
        Show-Step "I1" "php.ini-development used (no version config found)" "done"
        return $true
    }

    $oldIni    = Get-Content $oldPhpIni -Raw
    $newInySrc = Join-Path $phpDir "php.ini-development"
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

    $newIni = Repair-PhpIni -PhpIniContent $newIni -PhpVersion $NewVersion -PhpDir $phpDir
    Set-Content -Path $newPhpIni -Value $newIni -Encoding UTF8
    Show-Step "I1" "php.ini migrated from backup (no version config found)" "done"
    return $true
}

function Repair-PhpIni {
    <#
    Post-processes a php.ini string using the Quirks declared in the version registry,
    plus universal sanity checks (browscap path, missing extension DLLs).
    Returns the corrected content string.

    Recognised Quirks:
      'opcache-builtin'  — OPcache is statically compiled (PHP 8.4+); comment out zend_extension=opcache
      'opcache-dll'      — OPcache loads from php_opcache.dll; ensure the DLL exists before enabling
    #>
    param(
        [string]$PhpIniContent,
        [string]$PhpVersion,   # major.minor key e.g. "8.5"
        [string]$PhpDir        # e.g. C:\xampp\php
    )

    $quirks = if ($script:PhpVersions[$PhpVersion]) { $script:PhpVersions[$PhpVersion].Quirks } else { @() }

    # ── Quirk: opcache-builtin ─────────────────────────────────────────────
    # OPcache is compiled into the binary — no DLL. Loading it from ini crashes PHP.
    if ($quirks -contains 'opcache-builtin') {
        $PhpIniContent = $PhpIniContent.Replace(
            'zend_extension=opcache',
            '; zend_extension=opcache  ; built-in on this PHP version'
        )
        # Also handle explicit dll path: zend_extension="...\php_opcache.dll"
        $PhpIniContent = $PhpIniContent -replace
            '(?m)^(zend_extension\s*=\s*"[^"]*opcache[^"]*")',
            '; $1  ; built-in on this PHP version'
    }

    # ── Quirk: opcache-dll ────────────────────────────────────────────────
    # OPcache ships as php_opcache.dll. Ensure zend_extension points to the DLL name,
    # not the bare 'opcache' alias (which only works on some systems).
    if ($quirks -contains 'opcache-dll') {
        $opcacheDll = Join-Path $PhpDir "ext\php_opcache.dll"
        if (Test-Path $opcacheDll) {
            # Normalise bare 'opcache' alias → explicit dll filename
            $PhpIniContent = $PhpIniContent -replace
                '(?m)^zend_extension=opcache$',
                'zend_extension=php_opcache.dll'
        } else {
            # DLL missing — comment it out rather than crash
            $PhpIniContent = $PhpIniContent -replace
                '(?m)^(zend_extension\s*=\s*(opcache|php_opcache\.dll|"[^"]*opcache[^"]*"))$',
                '; $1  ; php_opcache.dll not found in ext folder'
        }
    }

    # ── Universal: comment out browscap if the file doesn't exist ─────────
    if ($PhpIniContent -match '(?m)^browscap\s*=\s*"([^"]+)"') {
        $browscapPath = $matches[1]
        if (-not (Test-Path $browscapPath)) {
            $PhpIniContent = $PhpIniContent.Replace(
                "browscap=`"$browscapPath`"",
                "; browscap=`"$browscapPath`"  ; file not present"
            )
        }
    }

    # ── Universal: comment out any extension= whose DLL is missing ────────
    $extDir = Join-Path $PhpDir "ext"
    $PhpIniContent = [regex]::Replace($PhpIniContent, '(?m)^extension=([^\s;]+)', {
        param($m)
        $ext = $m.Groups[1].Value.Trim()
        # Resolve bare name (e.g. "curl") to "php_curl.dll"
        $dll = if ($ext -match '\.dll$') { $ext } else { "php_$ext.dll" }
        $dllPath = Join-Path $extDir $dll
        if (-not (Test-Path $dllPath)) {
            "; extension=$ext  ; $dll not found in ext folder"
        } else {
            $m.Value
        }
    })

    return $PhpIniContent
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
            $majorMinor = $ExpectedVersion.Substring(0, 3)
            $cfg        = $script:PhpVersions[$majorMinor]
            $runtime    = if ($cfg) { $cfg.VsRuntime }    else { 'unknown' }
            $dlUrl      = if ($cfg) { $cfg.VsRuntimeUrl } else { 'https://aka.ms/vs/17/release/vc_redist.x64.exe' }
            Write-Warning2 "Missing Visual C++ Redistributable ($runtime)"
            Write-Host "    Download: $dlUrl" -ForegroundColor Gray
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

    if ($currentShort -eq $Version) {
        Write-Info "PHP $Version is already active — nothing to do."
        return $false
    }

    # ── Step 1: Ensure side-folder is downloaded ─────────────
    Show-Step "1" "Checking PHP $Version side-folder" "current"
    if (-not (Test-Path $sideDir)) {
        Show-Step "1" "PHP $Version not downloaded yet — fetching now" "current"
        if (-not (Install-PhpVersion -Version $Version)) {
            Show-Step "1" "Download failed" "error"
            Write-Error2 "Cannot switch — download failed"
            return $false
        }
    } else {
        Show-Step "1" "PHP $Version side-folder found at $sideDir" "done"
    }

    # ── Step 2: Open XAMPP Control Panel + show current state ─
    Show-Step "2" "Opening XAMPP Control Panel" "current"
    Open-XamppControlPanel
    Show-Step "2" "XAMPP Control Panel" "done"
    Write-Host ""
    Show-XamppStatus

    if (-not (Prompt-YesNo "  Stop services, backup PHP $currentShort, then switch to PHP $Version?")) {
        Write-Warning2 "Cancelled."
        return $false
    }

    # ── Step 3: Stop services ─────────────────────────────────
    Show-Step "3" "Stopping Apache + MySQL" "current"
    Invoke-XamppStop
    $stopped = Get-XamppStatus
    if ($stopped.Apache -or $stopped.MySQL) {
        Show-Step "3" "Services may still be running — continuing anyway" "error"
    } else {
        Show-Step "3" "Apache + MySQL stopped" "done"
    }
    Show-XamppStatus

    # ── Step 4: Backup current PHP folder ─────────────────────
    # This MUST happen before any folder changes
    $backupDir = Backup-CurrentPhp -CurrentVersion $currentShort
    if (-not $backupDir) {
        Write-Error2 "Backup failed — aborting switch to protect current installation"
        Show-Step "4" "Backup FAILED — starting services again" "error"
        Invoke-XamppStart
        Show-XamppStatus
        return $false
    }
    Write-Host "  Backup at: $backupDir" -ForegroundColor DarkGray

    # Save rollback copy of Apache conf
    Copy-Item $script:XamppConfPath "$($script:XamppConfPath).rollback" -Force -ErrorAction SilentlyContinue

    # ── Step 5: Swap PHP folders ──────────────────────────────
    if (-not (Swap-PhpFolders -NewVersion $Version -OldVersion $currentShort)) {
        Write-Error2 "Folder swap failed — restoring from backup"
        Restore-PhpBackup -BackupDir $backupDir -OldVersion $currentShort
        Invoke-XamppStart
        Show-XamppStatus
        return $false
    }

    # ── Step 6: Sync OpenSSL DLLs → Apache bin ───────────────
    # PHP ships its own libssl/libcrypto. If they're newer than Apache's copies,
    # Apache will load its stale version first, then php_curl.dll fails with
    # "entry point SSL_get0_group_name not found". Keep them in sync.
    Show-Step "6" "Syncing OpenSSL DLLs (PHP → Apache bin)" "current"
    $phpDir     = $script:XamppRoot | Join-Path -ChildPath "php"
    $apacheBin  = $script:XamppRoot | Join-Path -ChildPath "apache\bin"
    $sslDlls    = @("libssl-3-x64.dll", "libcrypto-3-x64.dll")
    $syncOk     = $true
    foreach ($dll in $sslDlls) {
        $src = Join-Path $phpDir $dll
        $dst = Join-Path $apacheBin $dll
        if (Test-Path $src) {
            try {
                Copy-Item $src $dst -Force
                Write-Host "    [OK] $dll synced" -ForegroundColor DarkGray
            } catch {
                Write-Host "    [!!] Could not copy $dll`: $($_.Exception.Message)" -ForegroundColor Yellow
                $syncOk = $false
            }
        } else {
            Write-Host "    [--] $dll not found in PHP dir — skipping" -ForegroundColor DarkGray
        }
    }
    if ($syncOk) { Show-Step "6" "OpenSSL DLLs synced" "done" } else { Show-Step "6" "OpenSSL sync partial — check manually" "error" }

    # ── Step 7: Patch httpd-xampp.conf ────────────────────────
    Patch-ApachePhpConfig -NewVersion $Version | Out-Null

    # ── Step 8: Migrate php.ini ───────────────────────────────
    Migrate-PhpIni -NewVersion $Version -BackupDir $backupDir

    # ── Step 9: Validate Apache config before starting ────────
    Show-Step "9" "Testing Apache config syntax" "current"
    $test = Test-ApacheConfigSyntax
    if (-not $test.Success) {
        Show-Step "9" "Apache config FAILED — rolling back" "error"
        Write-Host "    $($test.Output)" -ForegroundColor Red
        Restore-PhpBackup -BackupDir $backupDir -OldVersion $currentShort
        Invoke-XamppStart
        Show-XamppStatus
        return $false
    }
    Show-Step "8" "Apache config syntax OK" "done"

    # ── Step 9: Start services ────────────────────────────────
    Show-Step "9" "Starting Apache + MySQL" "current"
    Invoke-XamppStart
    $started = Get-XamppStatus
    if ($started.Apache -and $started.MySQL) {
        Show-Step "9" "Apache + MySQL running" "done"
    } else {
        Show-Step "9" "One or more services did not start" "error"
    }
    Show-XamppStatus

    # ── Step 10: Verify PHP version ───────────────────────────
    Show-Step "10" "Verifying PHP version" "current"
    # Resolve actual installed version from the downloaded zip name
    $resolvedVer = if ($sideDir) {
        $phpExeSide = Join-Path $sideDir "php.exe"
        if (Test-Path $phpExeSide) {
            $v = & $phpExeSide -v 2>&1 | Select-Object -First 1 | Out-String
            if ($v -match "PHP (\d+\.\d+\.\d+)") { $matches[1] } else { $phpConfig.Version }
        } else { $phpConfig.Version }
    } else { $phpConfig.Version }

    if (Verify-PhpVersion -ExpectedVersion $resolvedVer) {
        Show-Step "10" "PHP $resolvedVer confirmed" "done"
    } else {
        Show-Step "10" "Version mismatch — check VC++ runtimes" "error"
    }

    # ── Step 11: Update .env ──────────────────────────────────
    Update-EnvPhpVersion -NewVersion $Version

    # Cleanup rollback conf — switch succeeded
    Remove-Item "$($script:XamppConfPath).rollback" -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Success "Switched to PHP $Version  |  Backup kept at: $(Split-Path $backupDir -Leaf)"
    Write-Host ""
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
# EXPORT VERSION CONFIG
# ============================================================

function Export-PhpVersionConfig {
    <#
    Captures the current active php.ini into config/php/php-X.Y.ini,
    stripping machine-specific absolute paths so the file is portable
    and can be committed to source control.

    Substitutions made:
      C:\xampp\...   →  placeholder tokens e.g. {{XAMPP_ROOT}}
      C:\xampp\tmp   →  {{XAMPP_TMP}}
    Callers can update their preferred timezone / mail settings before committing.
    #>
    param(
        [string]$Version  # major.minor, e.g. "8.5"
    )

    $activeIni  = Join-Path $script:XamppRoot "php\php.ini"
    $destPath   = Join-Path $moduleRoot "config\php\php-$Version.ini"
    $xamppRoot  = $script:XamppRoot.TrimEnd('\')

    if (-not (Test-Path $activeIni)) {
        Write-Error2 "Active php.ini not found at $activeIni"
        return $false
    }

    Write-Host ""
    Write-Host "  Exporting PHP $Version config..." -ForegroundColor Cyan

    $content = Get-Content $activeIni -Raw

    # ─ Strip duplicate blank lines (tidy up migrated noise) ─────────────────────
    $content = $content -replace '(\r?\n){3,}', "`r`n`r`n"

    # ─ Normalise XAMPP paths → portable tokens ────────────────────────────
    # Order matters: longest/most specific first
    $replacements = [ordered]@{
        "$xamppRoot\php\logs\php_error_log"   = 'C:\xampp\php\logs\php_error_log'
        "$xamppRoot\php\extras\ssl\cacert.pem" = 'C:\xampp\php\extras\ssl\cacert.pem'
        "$xamppRoot\php\extras\browscap.ini"  = 'C:\xampp\php\extras\browscap.ini'
        "$xamppRoot\php\PEAR"                  = 'C:\xampp\php\PEAR'
        "$xamppRoot\php\ext"                   = 'C:\xampp\php\ext'
        "$xamppRoot\tmp"                       = 'C:\xampp\tmp'
        $xamppRoot                             = 'C:\xampp'
    }
    # Also handle forward-slash variants
    $fwd = $xamppRoot -replace '\\', '/'
    $replacements["$fwd/php/logs/php_error_log"]    = 'C:\xampp\php\logs\php_error_log'
    $replacements["$fwd/php/extras/ssl/cacert.pem"] = 'C:\xampp\php\extras\ssl\cacert.pem'
    $replacements["$fwd/php/ext"]                   = 'C:\xampp\php\ext'
    $replacements["$fwd/tmp"]                        = 'C:\xampp\tmp'
    $replacements[$fwd]                              = 'C:\xampp'

    foreach ($from in $replacements.Keys) {
        if ($from) { $content = $content.Replace($from, $replacements[$from]) }
    }

    # ─ Prepend header ───────────────────────────────────────────────────────
    $quirks  = if ($script:PhpVersions[$Version]) { ($script:PhpVersions[$Version].Quirks -join ', ') } else { 'none' }
    $runtime = if ($script:PhpVersions[$Version]) { $script:PhpVersions[$Version].VsRuntime } else { 'unknown' }
    $header  = @"
; ============================================================
; PHP $Version — XAMPP Dev Configuration
; Exported : $(Get-Date -Format 'yyyy-MM-dd HH:mm')
; Runtime  : $runtime
; Quirks   : $quirks
; Paths use C:\xampp as the canonical XAMPP root.
; Update date.timezone and mail settings for your environment.
; ============================================================

"@
    # Remove any existing auto-generated header block at the top
    $content = $content -replace '(?s)^;\s*={10,}.*?;\s*={10,}\r?\n+', ''
    $content = $header + $content.TrimStart()

    New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
    Set-Content -Path $destPath -Value $content -Encoding UTF8

    Write-Success "Exported → $destPath"
    Write-Host "  Review and commit this file to lock in your PHP $Version settings." -ForegroundColor DarkGray
    Write-Host ""
    return $true
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
    Write-Host "    5) Show system config            (arch, VC runtimes)" -ForegroundColor Gray
    Write-Host "    6) Export active php.ini to version config" -ForegroundColor Gray
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

        '5' { Show-WindowsPhpConfig }

        '6' {
            $activeShort = if ((Get-CurrentPhpVersion) -match "^(\d+\.\d+)") { $matches[1] } else { $script:ActivePhpVersion }
            Write-Host "  Export active php.ini for PHP $activeShort to config/php/php-$activeShort.ini" -ForegroundColor White
            if (Test-Path (Join-Path $moduleRoot "config\php\php-$activeShort.ini")) {
                if (-not (Prompt-YesNo "  File already exists — overwrite?")) { break }
            }
            Export-PhpVersionConfig -Version $activeShort | Out-Null
        }

        '0' { break }

        default { Write-Warning2 "Invalid option" }
    }

    if ($choice -ne '0') {
        Write-Host ""
        Prompt-Continue
    }

} while ($choice -ne '0')
