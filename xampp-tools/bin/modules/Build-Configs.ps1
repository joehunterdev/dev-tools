# Name: Build Configs
# Description: Build all configs from templates
# Cmd: build-configs
# Order: 5

<#
.SYNOPSIS
    Build Configs - Compile all templates to dist/

.DESCRIPTION
    Builds base configs to dist/:
    1. Base configs (httpd.conf, php.ini, etc.) from templates
    2. VHosts (httpd-vhosts.conf) from vhosts.json
    3. Hosts file from vhosts.json server names
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION (from config/config.json)
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:Config = Load-FilesConfig $moduleRoot

if (-not $script:Config) {
    Write-Error2 "Could not load config/config.json"
    exit
}

$script:TemplatesDir = Join-Path $moduleRoot $script:Config.templates.sourceDir
$script:DistDir = Join-Path $moduleRoot $script:Config.templates.distDir
$script:VhostsFile = Join-Path $moduleRoot $script:Config.vhosts.sitesFile

# ============================================================
# FUNCTIONS
# ============================================================

function Build-ConfigFromTemplate {
    param(
        [string]$TemplatePath,
        [string]$OutputPath,
        [hashtable]$EnvVars,
        [string]$Type = "standard",
        [array]$VhostsSites = @()
    )
    
    if (-not (Test-Path $TemplatePath)) {
        return @{ Success = $false; Error = "Template not found" }
    }
    
    try {
        $content = Get-Content $TemplatePath -Raw
        
        # Replace all {{VAR_NAME}} with env values
        foreach ($key in $EnvVars.Keys) {
            $placeholder = "{{$key}}"
            $content = $content -replace [regex]::Escape($placeholder), $EnvVars[$key]
        }
        
        # Replace runtime placeholders
        $content = $content -replace [regex]::Escape("{{TIMESTAMP}}"), (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        
        # Special handling for hosts template - inject vhosts entries
        if ($Type -eq "hosts") {
            $content = $content -replace [regex]::Escape("{{GENERATED_DATE}}"), (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            $domainExt = if ($EnvVars['VHOSTS_EXTENSION']) { $EnvVars['VHOSTS_EXTENSION'] } else { ".local" }
            
            if ($VhostsSites.Count -gt 0) {
                $vhostsEntries = @()
                foreach ($site in $VhostsSites) {
                    # Generate server name: use serverName if specified, otherwise folder + extension
                    if ($site.serverName) {
                        $serverName = $site.serverName
                    } else {
                        $baseName = $site.folder -replace '\.[^.]+$', ''
                        $serverName = "$baseName$domainExt"
                    }
                    $vhostsEntries += "127.0.0.1       $serverName"
                }
                $content = $content -replace [regex]::Escape("{{VHOSTS_ENTRIES}}"), ($vhostsEntries -join "`n")
            } else {
                $content = $content -replace [regex]::Escape("{{VHOSTS_ENTRIES}}"), "# No sites configured in vhosts.json"
            }
        }
        
        # Check for any unreplaced placeholders
        $unreplaced = [regex]::Matches($content, '\{\{([^}]+)\}\}')
        if ($unreplaced.Count -gt 0) {
            $missing = ($unreplaced | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique) -join ", "
            Write-Warning "    Missing env vars: $missing"
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

function Get-VhostBlock {
    param(
        [string]$BlocksContent,
        [string]$AppType,
        [bool]$Https
    )
    
    $httpsStr = if ($Https) { "true" } else { "false" }
    $pattern = "## App:$AppType HTTPS:$httpsStr"
    
    $lines = $BlocksContent -split "`n"
    $inBlock = $false
    $blockLines = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        if ($line -match [regex]::Escape($pattern)) {
            $inBlock = $true
            continue
        }
        
        if ($inBlock) {
            if ($line -match "^##") {
                break
            }
            $blockLines += $line
        }
    }
    
    return ($blockLines -join "`n").Trim()
}

function Test-SiteFolder {
    param(
        [hashtable]$EnvVars,
        [string]$FolderPattern,
        [string]$Type = "static"
    )
    
    $docRoot = if ($EnvVars['XAMPP_DOCUMENT_ROOT']) { $EnvVars['XAMPP_DOCUMENT_ROOT'] } else { "C:\www" }
    $basePath = Join-Path $docRoot $FolderPattern
    
    if ($Type.ToLower() -eq "laravel") {
        $checkPath = Join-Path $basePath "public"
    } else {
        $checkPath = $basePath
    }
    
    if (Test-Path $checkPath) {
        return @{ Valid = $true; Path = $checkPath }
    } else {
        return @{ Valid = $false; Error = "Folder not found: $checkPath" }
    }
}

function Remove-MissingLogDirectives {
    param(
        [string]$Block,
        [string]$DocumentRoot,
        [string]$Folder,
        [string]$AppType
    )
    
    # Determine the expected log directory based on app type
    $logDir = switch ($AppType.ToLower()) {
        "laravel" { "$DocumentRoot/$Folder/storage/logs" }
        "react" { "$DocumentRoot/$Folder/storage/logs" }
        "wordpress" { "$DocumentRoot/$Folder/logs" }
        "static" { "$DocumentRoot/$Folder/logs" }
        default { "$DocumentRoot/$Folder/logs" }
    }
    
    # Convert to Windows path for testing
    $logDirTest = $logDir -replace "/", "\"
    
    # If log directory does NOT exist, remove the conditional markers and log lines
    if (-not (Test-Path $logDirTest)) {
        # Remove lines that contain {{#IF_LOG_DIR}}, {{/IF_LOG_DIR}}, ErrorLog, and CustomLog
        $lines = $Block -split "`n"
        $filteredLines = @()
        $inLogBlock = $false
        
        foreach ($line in $lines) {
            if ($line -match '\{\{#IF_LOG_DIR\}\}') {
                $inLogBlock = $true
            } elseif ($line -match '\{\{/IF_LOG_DIR\}\}') {
                $inLogBlock = $false
            } elseif ($inLogBlock) {
                # Skip lines inside log block
                continue
            } else {
                $filteredLines += $line
            }
        }
        
        $Block = $filteredLines -join "`n"
    } else {
        # Log directory exists, just remove the conditional markers
        $Block = $Block -replace '\{\{#IF_LOG_DIR\}\}', ''
        $Block = $Block -replace '\{\{/IF_LOG_DIR\}\}', ''
    }
    
    return $Block
}

function Build-VhostsConfig {
    param(
        [hashtable]$EnvVars,
        [array]$ValidSites,
        [string]$DefaultCatchAllType = "Default"
    )
    
    $blocksTemplatePath = Join-Path $script:TemplatesDir $script:Config.vhosts.blocksTemplate
    $outputPath = Join-Path $script:DistDir $script:Config.vhosts.output
    
    if (-not (Test-Path $blocksTemplatePath)) {
        return @{ Success = $false; Error = "Blocks template not found" }
    }
    
    try {
        $blocksContent = Get-Content $blocksTemplatePath -Raw
        
        $output = @()
        $output += "# Apache VHosts Configuration"
        $output += "# Generated by xampp-tools - DO NOT EDIT DIRECTLY"
        $output += "# Edit config/vhosts.json and regenerate"
        $output += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $output += ""
        
        $port = if ($EnvVars['XAMPP_SERVER_PORT']) { $EnvVars['XAMPP_SERVER_PORT'] } else { "80" }
        $sslPort = if ($EnvVars['XAMPP_SSL_PORT']) { $EnvVars['XAMPP_SSL_PORT'] } else { "443" }
        $docRoot = if ($EnvVars['XAMPP_DOCUMENT_ROOT']) { $EnvVars['XAMPP_DOCUMENT_ROOT'] } else { "C:\www" }
        $xamppRoot = if ($EnvVars['XAMPP_ROOT_DIR']) { $EnvVars['XAMPP_ROOT_DIR'] } else { "C:\xampp" }
        $domainExt = if ($EnvVars['VHOSTS_EXTENSION']) { $EnvVars['VHOSTS_EXTENSION'] } else { ".local" }
        
        # Add default localhost catch-all from template
        $output += "# Default (localhost) - Fallback for unmatched requests"
        $defaultBlock = Get-VhostBlock -BlocksContent $blocksContent -AppType "Default" -Https $false
        if ($defaultBlock) {
            $defaultBlock = $defaultBlock -replace "{{PORT}}", $port
            $defaultBlock = $defaultBlock -replace "{{SSL_PORT}}", $sslPort
            $defaultBlock = $defaultBlock -replace "{{SERVER_NAME}}", "localhost"
            $defaultBlock = $defaultBlock -replace "{{FOLDER}}", "."
            $defaultBlock = $defaultBlock -replace "{{NAME}}", "Default (localhost)"
            $defaultBlock = $defaultBlock -replace "{{DOCUMENT_ROOT}}", $docRoot
            $defaultBlock = $defaultBlock -replace "{{XAMPP_ROOT_DIR}}", $xamppRoot
            
            # Check if logs directory exists for default catch-all
            $logDirTest = "$docRoot\logs"
            if (-not (Test-Path $logDirTest)) {
                # Log directory doesn't exist, remove the conditional markers and log lines
                $lines = $defaultBlock -split "`n"
                $filteredLines = @()
                $inLogBlock = $false
                
                foreach ($line in $lines) {
                    if ($line -match '\{\{#IF_LOG_DIR\}\}') {
                        $inLogBlock = $true
                    } elseif ($line -match '\{\{/IF_LOG_DIR\}\}') {
                        $inLogBlock = $false
                    } elseif ($inLogBlock) {
                        # Skip lines inside log block
                        continue
                    } else {
                        $filteredLines += $line
                    }
                }
                
                $defaultBlock = $filteredLines -join "`n"
            } else {
                # Log directory exists, just remove the conditional markers
                $defaultBlock = $defaultBlock -replace '\{\{#IF_LOG_DIR\}\}', ''
                $defaultBlock = $defaultBlock -replace '\{\{/IF_LOG_DIR\}\}', ''
            }
            
            $output += $defaultBlock
            $output += ""
        }
        
        foreach ($site in $ValidSites) {
            $appType = switch ($site.type.ToLower()) {
                "laravel" { "Laravel" }
                "react" { "React" }
                "wordpress" { "WordPress" }
                "static" { "Static" }
                default { "Static" }
            }
            
            # Check for SSL - support both 'ssl' and 'https' properties
            # Handle various truthy values from JSON
            $sslEnabled = ($site.ssl -eq $true) -or ($site.ssl -eq "true") -or ($site.https -eq $true) -or ($site.https -eq "true")
            
            # Per-site port override: use site.port if specified, otherwise use env default
            $sitePort = if ($site.port) { $site.port.ToString() } else { $port }
            $siteSslPort = if ($site.sslPort) { $site.sslPort.ToString() } else { $sslPort }
            
            # Generate server name: use serverName if specified, otherwise folder.domainExt
            if ($site.serverName) {
                $serverName = $site.serverName
            } else {
                # Strip any existing extension from folder and add domain ext
                $baseName = $site.folder -replace '\.[^.]+$', ''
                $serverName = "$baseName$domainExt"
            }
            
            if ($sslEnabled) {
                # SSL enabled: Generate HTTP redirect + HTTPS block
                $redirectBlock = @"
<VirtualHost *:$sitePort>
    ServerName $serverName
    Redirect permanent / https://$serverName/
</VirtualHost>
"@
                $output += "# $($site.name) - HTTP to HTTPS Redirect"
                $output += $redirectBlock
                $output += ""
                
                # Get HTTPS block
                $block = Get-VhostBlock -BlocksContent $blocksContent -AppType $appType -Https $true
                
                if ($block) {
                    $block = $block -replace "{{PORT}}", $sitePort
                    $block = $block -replace "{{SSL_PORT}}", $siteSslPort
                    $block = $block -replace "{{SERVER_NAME}}", $serverName
                    $block = $block -replace "{{FOLDER}}", $site.folder
                    $block = $block -replace "{{NAME}}", $site.name
                    $block = $block -replace "{{DOCUMENT_ROOT}}", $docRoot
                    $block = $block -replace "{{XAMPP_ROOT_DIR}}", $xamppRoot
                    
                    # Remove ErrorLog/CustomLog lines if log directories don't exist
                    $block = Remove-MissingLogDirectives -Block $block -DocumentRoot $docRoot -Folder $site.folder -AppType $appType
                    
                    $output += "# $($site.name) - HTTPS"
                    $output += $block
                    $output += ""
                }
            } else {
                # HTTP only
                $block = Get-VhostBlock -BlocksContent $blocksContent -AppType $appType -Https $false
                
                if ($block) {
                    $block = $block -replace "{{PORT}}", $sitePort
                    $block = $block -replace "{{SSL_PORT}}", $siteSslPort
                    $block = $block -replace "{{SERVER_NAME}}", $serverName
                    $block = $block -replace "{{FOLDER}}", $site.folder
                    $block = $block -replace "{{NAME}}", $site.name
                    $block = $block -replace "{{DOCUMENT_ROOT}}", $docRoot
                    $block = $block -replace "{{XAMPP_ROOT_DIR}}", $xamppRoot
                    
                    # Remove ErrorLog/CustomLog lines if log directories don't exist
                    $block = Remove-MissingLogDirectives -Block $block -DocumentRoot $docRoot -Folder $site.folder -AppType $appType
                    
                    $output += "# $($site.name)"
                    $output += $block
                    $output += ""
                }
            }
        }
        
        # Ensure output directory exists
        $outputDir = Split-Path $outputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        Set-Content -Path $outputPath -Value ($output -join "`n")
        
        return @{ Success = $true; Count = $ValidSites.Count }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  📦 Build Configs" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check .env
if (-not (Test-Path $script:EnvFile)) {
    Write-Error2 ".env file not found!"
    exit
}

# Check templates dir
if (-not (Test-Path $script:TemplatesDir)) {
    Write-Error2 "Templates directory not found!"
    exit
}

# Load env
$envData = Load-EnvFile $script:EnvFile

Write-Host "  Templates: $($script:TemplatesDir)" -ForegroundColor Gray
Write-Host "  Output:    $($script:DistDir)" -ForegroundColor Gray
Write-Host ""

# Check which base templates exist
Write-Host "  📄 Base Templates:" -ForegroundColor White
Write-Host ""

$availableTemplates = @()
foreach ($tpl in $script:Config.templates.files) {
    $templatePath = Join-Path $script:TemplatesDir $tpl.template
    $exists = Test-Path $templatePath
    $icon = if ($exists) { "✅" } else { "⚫" }
    $color = if ($exists) { "Gray" } else { "DarkGray" }
    Write-Host "    $icon $($tpl.template)" -ForegroundColor $color
    if ($exists) { $availableTemplates += $tpl }
}

Write-Host ""

# Check vhosts config
Write-Host "  🌐 VHosts:" -ForegroundColor White
Write-Host ""

$vhostsBlocksFile = Join-Path $script:TemplatesDir $script:Config.vhosts.blocksTemplate
$vhostsJsonFile = $script:VhostsFile
$vhostsBlocksExists = Test-Path $vhostsBlocksFile
$vhostsJsonExists = Test-Path $vhostsJsonFile

$vhostsIcon = if ($vhostsBlocksExists) { "✅" } else { "⚫" }
$vhostsColor = if ($vhostsBlocksExists) { "Gray" } else { "DarkGray" }
Write-Host "    $vhostsIcon $($script:Config.vhosts.blocksTemplate)" -ForegroundColor $vhostsColor

$jsonIcon = if ($vhostsJsonExists) { "✅" } else { "⚫" }
$jsonColor = if ($vhostsJsonExists) { "Gray" } else { "DarkGray" }
Write-Host "    $jsonIcon vhosts.json" -ForegroundColor $jsonColor

Write-Host ""

# Load vhosts.json and validate site folders (needed for hosts template too)
$vhosts = @()
$invalidSites = @()
if ($vhostsJsonExists) {
    $vhostsJson = Get-Content $vhostsJsonFile -Raw | ConvertFrom-Json
    
    # Support both "vhosts" and "sites" array names
    $sitesList = if ($vhostsJson.vhosts) { $vhostsJson.vhosts } elseif ($vhostsJson.sites) { $vhostsJson.sites } else { @() }
    
    foreach ($site in $sitesList) {
        $siteType = if ($site.type) { $site.type } else { "static" }
        $folderResult = Test-SiteFolder -EnvVars $envData -FolderPattern $site.folder -Type $siteType
        if ($folderResult.Valid) {
            $vhosts += $site
        } else {
            $invalidSites += @{
                Site = $site
                Error = $folderResult.Error
            }
        }
    }
    
    if ($invalidSites.Count -gt 0) {
        Write-Host "  ⚠️  Sites with missing folders (will be skipped):" -ForegroundColor Yellow
        Write-Host ""
        foreach ($invalid in $invalidSites) {
            $siteName = if ($invalid.Site.serverName) { $invalid.Site.serverName } else { $invalid.Site.folder }
            Write-Host "    ⚫ $siteName - $($invalid.Error)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    
    Write-Host "    📋 Valid sites: $($vhosts.Count)/$($sitesList.Count)" -ForegroundColor Gray
    Write-Host ""
}

$canBuildVhosts = $vhostsBlocksExists -and $vhostsJsonExists -and ($vhosts.Count -gt 0)

# Summary
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

$totalItems = $availableTemplates.Count
if ($canBuildVhosts) { $totalItems += 2 } # vhosts.conf + hosts

if ($totalItems -eq 0) {
    Write-Error2 "Nothing to build!"
    exit
}

Write-Host "  Will build:" -ForegroundColor White
Write-Host "    • $($availableTemplates.Count) base config(s)" -ForegroundColor Gray
if ($canBuildVhosts) {
    Write-Host "    • httpd-vhosts.conf ($($vhosts.Count) sites)" -ForegroundColor Gray
    Write-Host "    • hosts file" -ForegroundColor Gray
}
Write-Host ""

if (-not (Prompt-YesNo "  Build all configs to dist/?")) {
    Write-Host ""
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "  Building..." -ForegroundColor Cyan
Write-Host ""

# Build base templates
$built = 0
$failed = 0

Write-Host "  📄 Base Configs:" -ForegroundColor White
Write-Host ""

foreach ($tpl in $availableTemplates) {
    $templatePath = Join-Path $script:TemplatesDir $tpl.template
    $outputPath = Join-Path $script:DistDir $tpl.output
    $tplType = if ($tpl.type) { $tpl.type } else { "standard" }
    
    # Pass vhosts sites for hosts template
    $result = Build-ConfigFromTemplate -TemplatePath $templatePath -OutputPath $outputPath -EnvVars $envData -Type $tplType -VhostsSites $vhosts
    
    if ($result.Success) {
        Write-Host "    ✅ $($tpl.output)" -ForegroundColor Green
        $built++
    } else {
        Write-Host "    ❌ $($tpl.output) - $($result.Error)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""

# Build vhosts config (separate from base templates)
if ($canBuildVhosts) {
    Write-Host "  🌐 VHosts Config:" -ForegroundColor White
    Write-Host ""
    
    $vhostsResult = Build-VhostsConfig -EnvVars $envData -ValidSites $vhosts -DefaultCatchAllType $script:DefaultCatchAllType
    
    if ($vhostsResult.Success) {
        Write-Host "    ✅ $($script:Config.vhosts.output) ($($vhostsResult.Count) sites)" -ForegroundColor Green
        $built++
    } else {
        Write-Host "    ❌ $($script:Config.vhosts.output) - $($vhostsResult.Error)" -ForegroundColor Red
        $failed++
    }
    
    Write-Host ""
}

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($built -gt 0) {
    Write-Success "Built $built config(s) to dist/"
}

if ($failed -gt 0) {
    Write-Warning2 "$failed config(s) failed"
}

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor DarkGray
Write-Host "    • Run 'deploy-configs' to deploy base configs to XAMPP" -ForegroundColor DarkGray
Write-Host "    • Run 'deploy-vhosts' to deploy vhosts + hosts" -ForegroundColor DarkGray
Write-Host ""
