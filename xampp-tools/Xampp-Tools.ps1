<#
.SYNOPSIS
    XAMPP Tools - Main Entry Point

.DESCRIPTION
    Central hub for XAMPP configuration and management.
    Auto-discovers modules from bin/modules/ folder.

.EXAMPLE
    .\Xampp-Tools.ps1

.NOTES
    Author: Joe Hunter - github.com/joehunterdev
    Requires Administrator privileges for some operations
#>

# ============================================================
# CONFIGURATION
# ============================================================

$script:ScriptRoot = $PSScriptRoot
$script:EnvFile = Join-Path $script:ScriptRoot ".env"
$script:EnvExampleFile = Join-Path $script:ScriptRoot ".env.example"
$script:BackupDir = Join-Path $script:ScriptRoot "backups"
$script:DistDir = Join-Path $script:ScriptRoot "config\optimized\dist"
$script:BinDir = Join-Path $script:ScriptRoot "bin"
$script:ModulesDir = Join-Path $script:BinDir "modules"

# ============================================================
# LOAD CORE
# ============================================================

. (Join-Path $script:BinDir "Common.ps1")

# ============================================================
# AUTO-DISCOVER MODULES
# ============================================================

function Get-AvailableModules {
    $modules = @()
    
    if (Test-Path $script:ModulesDir) {
        Get-ChildItem -Path $script:ModulesDir -Filter "*.ps1" | ForEach-Object {
            # Extract module info from file header (first 20 lines)
            $content = (Get-Content $_.FullName -First 20) -join "`n"
            
            # Parse module metadata from comments
            $name = $_.BaseName
            $description = "No description"
            $icon = "📦"
            $cmd = $_.BaseName.ToLower()
            $order = 99
            
            if ($content -match '#\s*Name:\s*(.+)') { $name = $matches[1].Trim() }
            if ($content -match '#\s*Description:\s*(.+)') { $description = $matches[1].Trim() }
            if ($content -match '#\s*Icon:\s*(.+)') { $icon = $matches[1].Trim() }
            if ($content -match '#\s*Cmd:\s*(.+)') { $cmd = $matches[1].Trim().ToLower() }
            if ($content -match '#\s*Order:\s*(\d+)') { $order = [int]$matches[1] }
            
            $modules += @{
                Name = $name
                Description = $description
                Icon = $icon
                Cmd = $cmd
                Order = $order
                Path = $_.FullName
                FileName = $_.Name
            }
        }
    }
    
    # Sort by Order
    return $modules | Sort-Object { $_.Order }
}

# ============================================================
# MAIN MENU
# ============================================================

function Show-MainMenu {
    Show-Header
    
    # Admin status
    $isAdmin = Test-Administrator
    $adminStatus = if ($isAdmin) { "✅ Running as Administrator" } else { "⚠️  Not running as Administrator" }
    Write-Host "  $adminStatus" -ForegroundColor $(if ($isAdmin) { "Green" } else { "Yellow" })
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    # Get all modules
    $modules = Get-AvailableModules
    
    # Display horizontal menu
    Write-Host "  Commands:" -ForegroundColor White
    Write-Host ""
    
    # Build horizontal display
    $menuLine = "  "
    $key = 1
    foreach ($mod in $modules) {
        $menuLine += "$($mod.Icon) $key/$($mod.Cmd)  "
        $key++
    }
    $menuLine += "❌ 0/exit"
    
    Write-Host $menuLine -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $choice = Read-Host "  >"
    $choiceLower = $choice.ToLower().Trim()
    
    # Handle exit
    if ($choiceLower -eq '0' -or $choiceLower -eq 'exit' -or $choiceLower -eq 'q') {
        Write-Host ""
        Write-Host "  Goodbye! 🧑‍🚀" -ForegroundColor Cyan
        Write-Host ""
        exit
    }
    
    # Try to match by number
    if ($choice -match '^\d+$') {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $modules.Count) {
            & $modules[$index].Path
            Prompt-Continue
        }
    }
    else {
        # Try to match by command name
        $matched = $modules | Where-Object { $_.Cmd -eq $choiceLower }
        if ($matched) {
            & $matched.Path
            Prompt-Continue
        }
    }
    
    Show-MainMenu
}

# ============================================================
# ENTRY POINT
# ============================================================

Show-MainMenu
