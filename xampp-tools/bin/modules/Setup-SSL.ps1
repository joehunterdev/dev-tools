# Name: Setup SSL
# Description: Generate SSL certificates for local sites
# Icon: 🔐
# Cmd: setup-ssl
# Order: 9

<#
.SYNOPSIS
    Setup SSL - Generate self-signed SSL certificates for virtual hosts

.DESCRIPTION
    Generates SSL certificates for sites in vhosts.json with ssl:true
    1. Reads vhosts.json for sites with ssl enabled
    2. Generates self-signed certificates using OpenSSL
    3. Optionally imports certificates to Windows trust store
    4. Updates are applied when build-configs is run next
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:Config = Load-FilesConfig $moduleRoot
$script:VhostsFile = Join-Path $moduleRoot $script:Config.vhosts.sitesFile

if (-not $script:Config) {
    Write-Error2 "Could not load config/config.json"
    exit
}

# Load env
$envData = Load-EnvFile $script:EnvFile
$xamppRoot = if ($envData['XAMPP_ROOT_DIR']) { $envData['XAMPP_ROOT_DIR'] } else { "C:\xampp" }
$vhostsExtension = if ($envData['VHOSTS_EXTENSION']) { $envData['VHOSTS_EXTENSION'] } else { ".local" }

$script:OpenSSL = Join-Path $xamppRoot "apache\bin\openssl.exe"
$script:SSLCrtDir = Join-Path $xamppRoot "apache\conf\ssl.crt"
$script:SSLKeyDir = Join-Path $xamppRoot "apache\conf\ssl.key"
$script:OpenSSLConf = Join-Path $xamppRoot "apache\conf\openssl.cnf"

# ============================================================
# FUNCTIONS
# ============================================================

function Test-OpenSSL {
    <#
    .SYNOPSIS
        Check if OpenSSL is available
    #>
    if (Test-Path $script:OpenSSL) {
        return @{ Valid = $true; Path = $script:OpenSSL }
    }
    
    # Try PATH
    $opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
    if ($opensslPath) {
        return @{ Valid = $true; Path = $opensslPath.Source }
    }
    
    return @{ Valid = $false; Error = "OpenSSL not found" }
}

function Get-ServerName {
    <#
    .SYNOPSIS
        Get server name from site config
    #>
    param($Site, $Extension)
    
    if ($Site.serverName) {
        return $Site.serverName
    }
    
    $baseName = $Site.folder -replace '\.[^.]+$', ''
    return "$baseName$Extension"
}

function New-SelfSignedCertificate {
    <#
    .SYNOPSIS
        Generate a self-signed certificate for a domain
    #>
    param(
        [string]$Domain,
        [string]$OpenSSLPath,
        [string]$CrtDir,
        [string]$KeyDir,
        [string]$ConfigPath,
        [int]$Days = 365
    )
    
    # Ensure directories exist
    if (-not (Test-Path $CrtDir)) {
        New-Item -ItemType Directory -Path $CrtDir -Force | Out-Null
    }
    if (-not (Test-Path $KeyDir)) {
        New-Item -ItemType Directory -Path $KeyDir -Force | Out-Null
    }
    
    $crtFile = Join-Path $CrtDir "$Domain-selfsigned.crt"
    $keyFile = Join-Path $KeyDir "$Domain-selfsigned.key"
    
    # Build the openssl command
    $subjectAltName = "subjectAltName=DNS:$Domain,DNS:localhost,DNS:127.0.0.1"
    $subject = "/C=US/ST=Local/L=Development/O=XAMPP-Tools/OU=Dev/CN=$Domain"
    
    $args = @(
        "req"
        "-x509"
        "-nodes"
        "-days", $Days
        "-newkey", "rsa:2048"
        "-keyout", $keyFile
        "-out", $crtFile
        "-subj", $subject
        "-addext", $subjectAltName
    )
    
    if (Test-Path $ConfigPath) {
        $args += @("-config", $ConfigPath)
    }
    
    try {
        $result = & $OpenSSLPath $args 2>&1
        
        if (Test-Path $crtFile) {
            return @{ 
                Success = $true
                CrtFile = $crtFile
                KeyFile = $keyFile
            }
        } else {
            return @{ Success = $false; Error = "Certificate file not created: $result" }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Import-CertificateToStore {
    <#
    .SYNOPSIS
        Import certificate to Windows Trusted Root store
    #>
    param([string]$CrtFile)
    
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CrtFile)
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
        $store.Open("ReadWrite")
        $store.Add($cert)
        $store.Close()
        return @{ Success = $true }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Repair-ServerCert {
    <#
    .SYNOPSIS
        Regenerate the main Apache server.crt/server.key if the key is too small (< 2048 bit).
        OpenSSL 3.x rejects keys smaller than 2048 bit, preventing Apache from starting.
    #>
    $crtFile = Join-Path $script:SSLCrtDir "server.crt"
    $keyFile = Join-Path $script:SSLKeyDir "server.key"

    # Check current key size
    $keyBits = 0
    if (Test-Path $crtFile) {
        $info = & $script:OpenSSL x509 -in $crtFile -noout -text 2>&1 | Out-String
        if ($info -match 'Public-Key:\s*\((\d+)\s*bit\)') {
            $keyBits = [int]$matches[1]
        }
    }

    if ($keyBits -ge 2048) {
        return @{ Skipped = $true; KeyBits = $keyBits }
    }

    Write-Host "    [!!] server.crt has $keyBits-bit key — regenerating with 4096-bit (OpenSSL 3 minimum is 2048)" -ForegroundColor Yellow

    # Back up old files
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    if (Test-Path $crtFile) { Copy-Item $crtFile "$crtFile.bak.$ts" -Force }
    if (Test-Path $keyFile) { Copy-Item $keyFile "$keyFile.bak.$ts" -Force }

    $subject = "/C=GB/ST=Local/L=Development/O=XAMPP-Local/CN=localhost"
    $san     = "subjectAltName=DNS:localhost,IP:127.0.0.1"

    $genArgs = @(
        "req", "-x509", "-nodes",
        "-days", "3650",
        "-newkey", "rsa:4096",
        "-keyout", $keyFile,
        "-out",    $crtFile,
        "-subj",   $subject,
        "-addext", $san
    )
    if (Test-Path $script:OpenSSLConf) { $genArgs += @("-config", $script:OpenSSLConf) }

    $out = & $script:OpenSSL $genArgs 2>&1
    if (Test-Path $crtFile) {
        return @{ Success = $true; KeyBits = 4096 }
    } else {
        return @{ Success = $false; Error = ($out | Out-String).Trim() }
    }
}

function Repair-CaCert {
    <#
    .SYNOPSIS
        Ensure cacert.pem exists in C:\xampp\php\extras\ssl\.
        Downloads the Mozilla CA bundle from curl.se if missing or older than 90 days.
    #>
    param(
        [string]$XamppRoot = 'C:\xampp'
    )

    $sslDir  = Join-Path $XamppRoot 'php\extras\ssl'
    $caFile  = Join-Path $sslDir 'cacert.pem'
    $url     = 'https://curl.se/ca/cacert.pem'

    # Create directory if needed
    if (-not (Test-Path $sslDir)) {
        New-Item -ItemType Directory -Path $sslDir -Force | Out-Null
    }

    # Check if file exists and is fresh (< 90 days old)
    if (Test-Path $caFile) {
        $ageDays = ((Get-Date) - (Get-Item $caFile).LastWriteTime).TotalDays
        if ($ageDays -lt 90) {
            return @{ Skipped = $true; Path = $caFile; AgeDays = [int]$ageDays }
        }
        # Stale — re-download
        $stale = $true
    } else {
        $stale = $false
    }

    try {
        Invoke-WebRequest -Uri $url -OutFile $caFile -UseBasicParsing -ErrorAction Stop
        return @{ Success = $true; Path = $caFile; Stale = $stale }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message; Path = $caFile }
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🔐 Setup SSL Certificates" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check OpenSSL
$opensslCheck = Test-OpenSSL
if (-not $opensslCheck.Valid) {
    Write-Error2 "OpenSSL not found!"
    Write-Host "    Expected at: $script:OpenSSL" -ForegroundColor DarkGray
    exit
}

Write-Success "OpenSSL found: $($opensslCheck.Path)"
Write-Host ""

# ── Ensure main server.crt meets OpenSSL 3 minimum key size ──
Write-Host "  Checking main server.crt key size..." -ForegroundColor White
$serverCertCheck = Repair-ServerCert
if ($serverCertCheck.Skipped) {
    Write-Host "    [OK] server.crt is $($serverCertCheck.KeyBits)-bit — no action needed" -ForegroundColor DarkGray
} elseif ($serverCertCheck.Success) {
    Write-Host "    [OK] server.crt regenerated as 4096-bit (10-year expiry)" -ForegroundColor Green
    Write-Host "    [..] Restart Apache for the new cert to take effect" -ForegroundColor DarkGray
} else {
    Write-Host "    [!!] Could not regenerate server.crt: $($serverCertCheck.Error)" -ForegroundColor Red
}
Write-Host ""

# ── Ensure cacert.pem (Mozilla CA bundle) is present ──────────
Write-Host "  Checking CA certificate bundle (cacert.pem)..." -ForegroundColor White
$caCheck = Repair-CaCert -XamppRoot $xamppRoot
if ($caCheck.Skipped) {
    Write-Host "    [OK] cacert.pem present ($($caCheck.AgeDays) days old)" -ForegroundColor DarkGray
} elseif ($caCheck.Success) {
    $action = if ($caCheck.Stale) { 'refreshed' } else { 'downloaded' }
    Write-Host "    [OK] cacert.pem $action → $($caCheck.Path)" -ForegroundColor Green
} else {
    Write-Host "    [!!] Could not download cacert.pem: $($caCheck.Error)" -ForegroundColor Red
    Write-Host "    [..] Download manually from https://curl.se/ca/cacert.pem" -ForegroundColor DarkGray
    Write-Host "         and save to: $($caCheck.Path)" -ForegroundColor DarkGray
}
Write-Host ""

# Load vhosts
if (-not (Test-Path $script:VhostsFile)) {
    Write-Error2 "vhosts.json not found!"
    exit
}

$vhostsJson = Get-Content $script:VhostsFile -Raw | ConvertFrom-Json
$sitesList = if ($vhostsJson.vhosts) { $vhostsJson.vhosts } elseif ($vhostsJson.sites) { $vhostsJson.sites } else { @() }

# Filter sites with SSL enabled
$sslSites = @()
foreach ($site in $sitesList) {
    if ($site.ssl -eq $true) {
        $sslSites += $site
    }
}

if ($sslSites.Count -eq 0) {
    Write-Warning2 "No sites have ssl:true in vhosts.json"
    Write-Host ""
    Write-Host "  Add 'ssl': true to sites in config/vhosts.json" -ForegroundColor DarkGray
    exit
}

Write-Host "  Sites with SSL enabled:" -ForegroundColor White
Write-Host ""

$domains = @()
foreach ($site in $sslSites) {
    $serverName = Get-ServerName -Site $site -Extension $vhostsExtension
    $domains += $serverName
    $crtFile = Join-Path $script:SSLCrtDir "$serverName-selfsigned.crt"
    $exists = Test-Path $crtFile
    $icon = if ($exists) { "✅" } else { "⬜" }
    $status = if ($exists) { "(cert exists)" } else { "(needs cert)" }
    Write-Host "    $icon $serverName $status" -ForegroundColor Gray
}

# Always add localhost
if ($domains -notcontains "localhost") {
    $domains = @("localhost") + $domains
    $crtFile = Join-Path $script:SSLCrtDir "localhost-selfsigned.crt"
    $exists = Test-Path $crtFile
    $icon = if ($exists) { "✅" } else { "⬜" }
    $status = if ($exists) { "(cert exists)" } else { "(needs cert)" }
    Write-Host "    $icon localhost $status" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  Output directories:" -ForegroundColor White
Write-Host "    📁 Certificates: $script:SSLCrtDir" -ForegroundColor Gray
Write-Host "    📁 Private keys: $script:SSLKeyDir" -ForegroundColor Gray
Write-Host ""

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if (-not (Prompt-YesNo "  Generate SSL certificates for $($domains.Count) domain(s)?")) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "  Generating certificates..." -ForegroundColor Cyan
Write-Host ""

$generated = 0
$failed = 0
$generatedCerts = @()

foreach ($domain in $domains) {
    $result = New-SelfSignedCertificate `
        -Domain $domain `
        -OpenSSLPath $opensslCheck.Path `
        -CrtDir $script:SSLCrtDir `
        -KeyDir $script:SSLKeyDir `
        -ConfigPath $script:OpenSSLConf
    
    if ($result.Success) {
        Write-Host "    ✅ $domain" -ForegroundColor Green
        $generated++
        $generatedCerts += $result.CrtFile
    } else {
        Write-Host "    ❌ $domain - $($result.Error)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""

# Ask to import to Windows trust store
if ($generated -gt 0) {
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    if (Prompt-YesNo "  Import certificates to Windows trust store? (removes browser warnings)") {
        Write-Host ""
        Write-Host "  Importing to Trusted Root Certification Authorities..." -ForegroundColor Cyan
        Write-Host ""
        
        $imported = 0
        foreach ($crtFile in $generatedCerts) {
            $domain = [System.IO.Path]::GetFileNameWithoutExtension($crtFile) -replace "-selfsigned$", ""
            $importResult = Import-CertificateToStore -CrtFile $crtFile
            
            if ($importResult.Success) {
                Write-Host "    ✅ $domain" -ForegroundColor Green
                $imported++
            } else {
                Write-Host "    ⚠️  $domain - $($importResult.Error)" -ForegroundColor Yellow
            }
        }
        
        Write-Host ""
        Write-Success "$imported certificate(s) imported to trust store"
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($generated -gt 0) {
    Write-Success "Generated $generated SSL certificate(s)"
}

if ($failed -gt 0) {
    Write-Warning2 "$failed certificate(s) failed"
}

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor DarkGray
Write-Host "    1. Run 'build-configs' to rebuild vhosts with SSL" -ForegroundColor DarkGray
Write-Host "    2. Run 'deploy-vhosts' to deploy the new configuration" -ForegroundColor DarkGray
Write-Host "    3. Restart Apache to apply changes" -ForegroundColor DarkGray
Write-Host ""
