<#
.SYNOPSIS
    XAMPP Tools - TUI Dashboard Entry Point

.DESCRIPTION
    Launches the full-screen TUI dashboard for XAMPP Tools.
    Reuses all module auto-discovery from Xampp-Tools.ps1
    without modifying it.

.EXAMPLE
    .\Xampp-Tools-GUI.ps1

.NOTES
    Author: Joe Hunter - github.com/joehunterdev
#>

# ============================================================
# CONFIGURATION  (mirrors Xampp-Tools.ps1)
# ============================================================

$script:ScriptRoot  = $PSScriptRoot
$script:EnvFile     = Join-Path $script:ScriptRoot ".env"
$script:BackupDir   = Join-Path $script:ScriptRoot "backups"
$script:DistDir     = Join-Path $script:ScriptRoot "config\optimized\dist"
$script:BinDir      = Join-Path $script:ScriptRoot "bin"
$script:ModulesDir  = Join-Path $script:BinDir "modules"

# ============================================================
# LOAD CORE
# ============================================================

. (Join-Path $script:BinDir "Common.ps1")
. (Join-Path $script:BinDir "Service-Helpers.ps1")
. (Join-Path $script:BinDir "Dashboard.ps1")

# ============================================================
# MODULE DISCOVERY  (copied from Xampp-Tools.ps1 — read-only)
# ============================================================

function Get-AvailableModules {
    $modules = @()

    if (Test-Path $script:ModulesDir) {
        Get-ChildItem -Path $script:ModulesDir -Filter "*.ps1" | ForEach-Object {
            $content     = (Get-Content $_.FullName -First 20) -join "`n"
            $name        = $_.BaseName
            $description = "No description"
            $icon        = [char]0x1F4E6   # 📦
            $cmd         = $_.BaseName.ToLower()
            $order       = 99
            $hidden      = $false

            if ($content -match '#\s*Name:\s*(.+)')         { $name        = $matches[1].Trim() }
            if ($content -match '#\s*Description:\s*(.+)')  { $description = $matches[1].Trim() }
            if ($content -match '#\s*Icon:\s*(.+)')         { $icon        = $matches[1].Trim() }
            if ($content -match '#\s*Cmd:\s*(.+)')          { $cmd         = $matches[1].Trim().ToLower() }
            if ($content -match '#\s*Order:\s*(\d+)')       { $order       = [int]$matches[1] }
            if ($content -match '#\s*Hidden:\s*(true|false)'){ $hidden      = [bool]::Parse($matches[1]) }

            $modules += @{
                Name        = $name
                Description = $description
                Icon        = $icon
                Cmd         = $cmd
                Order       = $order
                Hidden      = $hidden
                Path        = $_.FullName
                FileName    = $_.Name
            }
        }
    }

    return $modules | Sort-Object { $_.Order }
}

# ============================================================
# ENTRY POINT
# ============================================================

$modules = Get-AvailableModules
Start-Dashboard -Modules $modules
