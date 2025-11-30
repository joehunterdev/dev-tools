# Name: Firewall
# Description: Manage Windows Firewall rules for XAMPP
# Icon: 🛡️
# Cmd: firewall
# Order: 9

<#
.SYNOPSIS
    Firewall Manager - Secure XAMPP with Windows Firewall rules

.DESCRIPTION
    Creates firewall rules to:
    1. Block external access to Apache (HTTP/HTTPS)
    2. Block external access to MySQL
    3. Allow only localhost connections
    
    Reads ports from .env file.
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:RulePrefix = "XAMPP-Tools"

# ============================================================
# FUNCTIONS
# ============================================================

function Get-XamppPorts {
    param([hashtable]$EnvVars)
    
    return @{
        HTTP = @{
            Port = if ($EnvVars['XAMPP_SERVER_PORT']) { [int]$EnvVars['XAMPP_SERVER_PORT'] } else { 80 }
            Name = "Apache HTTP"
            Service = "Apache"
        }
        HTTPS = @{
            Port = if ($EnvVars['XAMPP_SSL_PORT']) { [int]$EnvVars['XAMPP_SSL_PORT'] } else { 443 }
            Name = "Apache HTTPS"
            Service = "Apache"
        }
        MySQL = @{
            Port = if ($EnvVars['MYSQL_PORT']) { [int]$EnvVars['MYSQL_PORT'] } else { 3306 }
            Name = "MySQL"
            Service = "MySQL"
        }
    }
}

function Get-FirewallRuleStatus {
    param([string]$RuleName)
    
    $rule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if ($rule) {
        return @{
            Exists = $true
            Enabled = $rule.Enabled -eq 'True'
            Action = $rule.Action
            Direction = $rule.Direction
        }
    }
    return @{ Exists = $false }
}

function Get-PortExposure {
    param([int]$Port)
    
    # Check if port is listening
    $listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    
    # Check if listening on all interfaces (0.0.0.0) or just localhost
    $exposed = $false
    $localOnly = $true
    
    if ($listening) {
        foreach ($conn in $listening) {
            if ($conn.LocalAddress -eq "0.0.0.0" -or $conn.LocalAddress -eq "::") {
                $exposed = $true
                $localOnly = $false
            }
        }
    }
    
    return @{
        Listening = ($null -ne $listening)
        Exposed = $exposed
        LocalOnly = $localOnly
        Connections = $listening
    }
}

function Show-PortStatus {
    param(
        [hashtable]$Ports,
        [hashtable]$EnvVars
    )
    
    Write-Host "  Current Port Status:" -ForegroundColor White
    Write-Host ""
    
    foreach ($key in $Ports.Keys) {
        $portInfo = $Ports[$key]
        $port = $portInfo.Port
        $exposure = Get-PortExposure -Port $port
        $ruleName = "$($script:RulePrefix)-Block-$key"
        $ruleStatus = Get-FirewallRuleStatus -RuleName $ruleName
        
        # Status icon
        if ($exposure.Listening) {
            if ($exposure.Exposed -and -not $ruleStatus.Exists) {
                $icon = "🔴"  # Exposed and no firewall rule
                $status = "EXPOSED"
                $color = "Red"
            } elseif ($ruleStatus.Exists -and $ruleStatus.Enabled) {
                $icon = "🟢"  # Protected by firewall
                $status = "PROTECTED"
                $color = "Green"
            } elseif ($exposure.LocalOnly) {
                $icon = "🟡"  # Localhost only
                $status = "LOCAL ONLY"
                $color = "Yellow"
            } else {
                $icon = "🟡"  # Running but status unclear
                $status = "RUNNING"
                $color = "Yellow"
            }
        } else {
            $icon = "⚫"  # Not running
            $status = "NOT LISTENING"
            $color = "DarkGray"
        }
        
        Write-Host "    $icon $($portInfo.Name)" -ForegroundColor $color -NoNewline
        Write-Host " (port $port)" -ForegroundColor DarkGray -NoNewline
        Write-Host " - $status" -ForegroundColor $color
        
        # Show firewall rule status
        if ($ruleStatus.Exists) {
            $ruleIcon = if ($ruleStatus.Enabled) { "  ✓" } else { "  ✗" }
            $ruleText = if ($ruleStatus.Enabled) { "Firewall rule active" } else { "Firewall rule disabled" }
            Write-Host "      $ruleIcon $ruleText" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

function New-XamppFirewallRule {
    param(
        [string]$Key,
        [hashtable]$PortInfo
    )
    
    $ruleName = "$($script:RulePrefix)-Block-$Key"
    $port = $PortInfo.Port
    
    # Remove existing rule if present
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    
    try {
        # Create rule to block inbound from external (not from localhost)
        # Block all inbound on the port, then we rely on localhost being allowed by default
        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Description "XAMPP-Tools: Block external access to $($PortInfo.Name) on port $port" `
            -Direction Inbound `
            -LocalPort $port `
            -Protocol TCP `
            -Action Block `
            -RemoteAddress @("Internet", "Intranet", "LocalSubnet") `
            -Profile @("Domain", "Private", "Public") `
            -ErrorAction Stop | Out-Null
        
        return @{ Success = $true }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Remove-XamppFirewallRule {
    param([string]$Key)
    
    $ruleName = "$($script:RulePrefix)-Block-$Key"
    
    try {
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop
            return @{ Success = $true; Existed = $true }
        }
        return @{ Success = $true; Existed = $false }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Test-AdminPrivileges {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  🛡️  Firewall Manager" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Check .env
if (-not (Test-Path $script:EnvFile)) {
    Write-Error2 ".env file not found!"
    exit
}

# Load env and get ports
$envData = Load-EnvFile $script:EnvFile
$ports = Get-XamppPorts -EnvVars $envData

# Show current status
Show-PortStatus -Ports $ports -EnvVars $envData

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Options:" -ForegroundColor White
Write-Host ""
Write-Host "    1) 🛡️  Secure All Ports (create blocking rules)" -ForegroundColor Gray
Write-Host "    2) 🔓 Remove All Rules (allow external access)" -ForegroundColor Gray
Write-Host "    3) 📋 Show Detailed Status" -ForegroundColor Gray
Write-Host ""
Write-Host "    0) <- Back" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "  Select option"

switch ($choice) {
    '1' {
        Write-Host ""
        
        # Check admin privileges
        if (-not (Test-AdminPrivileges)) {
            Write-Error2 "Administrator privileges required!"
            Write-Host ""
            Write-Host "  Run PowerShell as Administrator and try again." -ForegroundColor DarkGray
            Write-Host ""
            exit
        }
        
        Write-Host "  Creating firewall rules..." -ForegroundColor Cyan
        Write-Host ""
        
        $created = 0
        $failed = 0
        
        foreach ($key in $ports.Keys) {
            $portInfo = $ports[$key]
            $result = New-XamppFirewallRule -Key $key -PortInfo $portInfo
            
            if ($result.Success) {
                Write-Host "    ✅ $($portInfo.Name) (port $($portInfo.Port)) - blocked from external" -ForegroundColor Green
                $created++
            } else {
                Write-Host "    ❌ $($portInfo.Name) - $($result.Error)" -ForegroundColor Red
                $failed++
            }
        }
        
        Write-Host ""
        
        if ($created -gt 0) {
            Write-Success "Created $created firewall rule(s)"
        }
        if ($failed -gt 0) {
            Write-Warning2 "$failed rule(s) failed"
        }
        
        Write-Host ""
        Write-Host "  XAMPP ports are now only accessible from localhost." -ForegroundColor DarkGray
        Write-Host ""
    }
    '2' {
        Write-Host ""
        
        # Check admin privileges
        if (-not (Test-AdminPrivileges)) {
            Write-Error2 "Administrator privileges required!"
            Write-Host ""
            Write-Host "  Run PowerShell as Administrator and try again." -ForegroundColor DarkGray
            Write-Host ""
            exit
        }
        
        if (-not (Prompt-YesNo "  Remove all XAMPP firewall rules? (ports will be exposed)")) {
            Write-Host ""
            Write-Host "  Cancelled." -ForegroundColor Yellow
            exit
        }
        
        Write-Host ""
        Write-Host "  Removing firewall rules..." -ForegroundColor Cyan
        Write-Host ""
        
        $removed = 0
        
        foreach ($key in $ports.Keys) {
            $portInfo = $ports[$key]
            $result = Remove-XamppFirewallRule -Key $key
            
            if ($result.Success -and $result.Existed) {
                Write-Host "    ✅ Removed rule for $($portInfo.Name)" -ForegroundColor Green
                $removed++
            } elseif ($result.Success) {
                Write-Host "    ⚫ No rule existed for $($portInfo.Name)" -ForegroundColor DarkGray
            } else {
                Write-Host "    ❌ $($portInfo.Name) - $($result.Error)" -ForegroundColor Red
            }
        }
        
        Write-Host ""
        
        if ($removed -gt 0) {
            Write-Success "Removed $removed firewall rule(s)"
            Write-Host ""
            Write-Warning2 "XAMPP ports may now be accessible from external networks!"
        } else {
            Write-Host "  No rules were removed." -ForegroundColor DarkGray
        }
        
        Write-Host ""
    }
    '3' {
        Write-Host ""
        Write-Host "  Detailed Port Analysis:" -ForegroundColor White
        Write-Host ""
        
        foreach ($key in $ports.Keys) {
            $portInfo = $ports[$key]
            $port = $portInfo.Port
            $exposure = Get-PortExposure -Port $port
            $ruleName = "$($script:RulePrefix)-Block-$key"
            $ruleStatus = Get-FirewallRuleStatus -RuleName $ruleName
            
            Write-Host "  [$($portInfo.Name) - Port $port]" -ForegroundColor Cyan
            Write-Host "    Listening:      $(if ($exposure.Listening) { 'Yes' } else { 'No' })" -ForegroundColor Gray
            Write-Host "    Bound to:       $(if ($exposure.Exposed) { 'All interfaces (0.0.0.0)' } elseif ($exposure.LocalOnly) { 'Localhost only' } else { 'N/A' })" -ForegroundColor Gray
            Write-Host "    Firewall Rule:  $(if ($ruleStatus.Exists) { if ($ruleStatus.Enabled) { 'Active (blocking)' } else { 'Disabled' } } else { 'None' })" -ForegroundColor Gray
            
            # Risk assessment
            if ($exposure.Listening -and $exposure.Exposed -and -not $ruleStatus.Exists) {
                Write-Host "    Risk:           HIGH - Exposed to network!" -ForegroundColor Red
            } elseif ($exposure.Listening -and $ruleStatus.Exists -and $ruleStatus.Enabled) {
                Write-Host "    Risk:           LOW - Protected by firewall" -ForegroundColor Green
            } elseif ($exposure.Listening -and $exposure.LocalOnly) {
                Write-Host "    Risk:           LOW - Localhost only" -ForegroundColor Green
            } else {
                Write-Host "    Risk:           N/A" -ForegroundColor DarkGray
            }
            Write-Host ""
        }
    }
    '0' {
        # Back - do nothing
    }
    default {
        Write-Host ""
        Write-Host "  Invalid option." -ForegroundColor Yellow
        Write-Host ""
    }
}
