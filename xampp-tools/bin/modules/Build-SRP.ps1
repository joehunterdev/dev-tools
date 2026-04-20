# Name: Build & Deploy SRP
# Description: Build Software Restriction Policy from template and deploy to SoftwarePolicy
# Cmd: build-srp
# Order: 7
# Icon: 🔐

<#
.SYNOPSIS
    Build & Deploy SRP - Compile softwarepolicy.ini template and deploy it

.DESCRIPTION
    1. Expands template tokens (USERNAME, XAMPP_ROOT_DIR, doc root, dev-tools path)
    2. Writes dist/softwarepolicy/softwarepolicy.ini
    3. Copies to C:\Windows\SoftwarePolicy\softwarepolicy.ini (requires admin)
    4. Reloads via softwarepolicy.exe /s (silent reinstall)
#>

$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")
. (Join-Path $moduleRoot "bin\Service-Helpers.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile   = Join-Path $moduleRoot ".env"
$_env             = Load-EnvFile $script:EnvFile
$xamppRoot        = if ($_env['XAMPP_ROOT_DIR'])       { $_env['XAMPP_ROOT_DIR'] }       else { "C:\xampp" }
$docRoot          = if ($_env['XAMPP_DOCUMENT_ROOT'])  { $_env['XAMPP_DOCUMENT_ROOT'] }  else { "C:\www" }
$devToolsRoot     = $moduleRoot   # e.g. C:\dev-tools\xampp-tools
$srpTarget        = "C:\Windows\SoftwarePolicy\softwarepolicy.ini"
$srpExe           = "C:\Windows\SoftwarePolicy\softwarepolicy.exe"
$templatePath     = Join-Path $moduleRoot "config\optimized\templates\softwarepolicy\softwarepolicy.ini.template" #do not hard code these paths
$distPath         = Join-Path $moduleRoot "config\optimized\dist\softwarepolicy\softwarepolicy.ini"

# ============================================================
# FUNCTIONS
# ============================================================

function Build-XamppPaths {
    param([string]$Root)
    $r = $Root.TrimEnd('\')
    $lines = @(
        "$r=1",
        "$r\apache=1",
        "$r\apache\bin=1",
        "$r\apache\bin\httpd.exe=1",
        "$r\mysql=1",
        "$r\mysql\bin=1",
        "$r\mysql\bin\mysqld.exe=1",
        "$r\mysql\bin\mysql.exe=1",
        "$r\mysql\bin\mysqladmin.exe=1",
        "$r\php=1",
        "$r\php\php.exe=1",
        "$r\phpMyAdmin=1",
        "$r\tmp=1",
        "$r\apache\bin\openssl.exe=1"
    )
    return $lines -join "`r`n"
}

function Build-DevToolsPaths {
    param([string]$Root)
    $r = $Root.TrimEnd('\')
    $lines = @(
        "$r=1",
        "$r\bin=1",
        "$r\bin\*.ps1=1",
        "$r\bin\modules=1",
        "$r\bin\modules\*.ps1=1",
        "$r\Xampp-Tools.ps1=1",
        "$r\Xampp-Tools-GUI.ps1=1"
    )
    return $lines -join "`r`n"
}

function Build-DocRootPaths {
    param([string]$Root)
    $r = $Root.TrimEnd('\')
    $lines = @(
        "$r=1",
        "$r\*=1",
        "$r\*\node_modules=1",
        "$r\*\node_modules\.bin=1",
        "$r\*\node_modules\.bin\*=1"
    )
    return $lines -join "`r`n"
}

function Build-UserCustomPaths {
    # Placeholder — add extra paths here or load from .env
    return "; Add custom paths below"
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  Build & Deploy SRP" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Step 1: Check template ────────────────────────────────────
if (-not (Test-Path $templatePath)) {
    Write-Error2 "Template not found: $templatePath"
    exit
}

# ── Step 2: Expand tokens ─────────────────────────────────────
Write-Host "  Building softwarepolicy.ini from template..." -ForegroundColor White
Write-Host ""

$content = Get-Content $templatePath -Raw

$username      = $env:USERNAME
$xamppPaths    = Build-XamppPaths    -Root $xamppRoot
$devtoolsPaths = Build-DevToolsPaths -Root $devToolsRoot
$docRootPaths  = Build-DocRootPaths  -Root $docRoot
$customPaths   = Build-UserCustomPaths

$content = $content.Replace('{{USERNAME}}',         $username)
$content = $content.Replace('{{XAMPP_ROOT_DIR}}',   $xamppRoot)
$content = $content.Replace('{{XAMPP_PATHS}}',      $xamppPaths)
$content = $content.Replace('{{DEVTOOLS_PATHS}}',   $devtoolsPaths)
$content = $content.Replace('{{DOC_ROOT_PATHS}}',   $docRootPaths)
$content = $content.Replace('{{USER_CUSTOM_PATHS}}', $customPaths)

# ── Step 3: Write dist ────────────────────────────────────────
$distDir = Split-Path $distPath -Parent
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Set-Content -Path $distPath -Value $content -Encoding UTF8
Write-Host "    [OK] dist/softwarepolicy/softwarepolicy.ini" -ForegroundColor Green

# ── Step 4: Preview ───────────────────────────────────────────
Write-Host ""
Write-Host "  Expanded entries:" -ForegroundColor White
$content -split "`n" | Where-Object { $_ -match '=1$' } | ForEach-Object {
    Write-Host "    $_" -ForegroundColor DarkGray
}
Write-Host ""

# ── Step 5: Deploy ────────────────────────────────────────────
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Target: $srpTarget" -ForegroundColor Gray
Write-Host ""

if (-not (Prompt-YesNo "  Deploy to C:\Windows\SoftwarePolicy and reload?")) {
    Write-Warning2 "Skipped deploy — dist file is ready at:"
    Write-Host "    $distPath" -ForegroundColor DarkGray
    Write-Host ""
    exit
}

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error2 "Admin rights required to write to C:\Windows\SoftwarePolicy"
    Write-Host "  Run this tool as Administrator, or copy manually:" -ForegroundColor DarkGray
    Write-Host "    $distPath  →  $srpTarget" -ForegroundColor DarkGray
    exit
}

try {
    Copy-Item -Path $distPath -Destination $srpTarget -Force
    Write-Host "    [OK] Deployed to $srpTarget" -ForegroundColor Green
} catch {
    Write-Error2 "Deploy failed: $($_.Exception.Message)"
    exit
}

# ── Step 6: Reload SRP ────────────────────────────────────────
# NOTE: We use cmd.exe to kill + relaunch softwarepolicy.exe *after a delay*
# so the currently running pwsh session is not killed by the new policy mid-script.
if (Test-Path $srpExe) {
    Write-Host "    [..] Scheduling SRP reload via cmd (deferred — avoids killing this session)" -ForegroundColor DarkGray
    $killCmd  = "taskkill /F /IM softwarepolicy.exe >nul 2>&1"
    $waitCmd  = "timeout /t 2 /nobreak >nul"
    $startCmd = "start `"`" `"$srpExe`" /s"
    $fullCmd  = "$killCmd & $waitCmd & $startCmd"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $fullCmd -WindowStyle Hidden
    Write-Host "    [OK] SRP reload scheduled (will apply in ~2s)" -ForegroundColor Green
} else {
    Write-Warning2 "softwarepolicy.exe not found — reload manually"
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Success "SRP built and deployed"
Write-Host ""
