# Name: Create Shortcuts
# Description: Add XAMPP Tools to desktop, Start Menu, and taskbar
# Icon: 🖥️
# Cmd: shortcuts
# Order: 17

<#
.SYNOPSIS
    Create Shortcuts - Pin XAMPP Tools to desktop and Start Menu

.DESCRIPTION
    Creates Windows shortcuts for XAMPP Tools:
    1. Desktop shortcut
    2. Start Menu shortcut (Programs folder)
    3. Optionally sets a custom icon

.NOTES
    Shortcuts launch Xampp-Tools.ps1 via pwsh/powershell
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:ToolsEntry  = Join-Path $moduleRoot "Xampp-Tools.ps1"
$script:AssetsDir   = Join-Path $moduleRoot "bin\assets"
$script:IconIco     = Join-Path $moduleRoot "bin\assets\logo.ico"
$script:IconPng     = Join-Path $moduleRoot "bin\assets\logo.png"
$script:AppName     = "XAMPP Tools"

$script:DesktopPath   = [Environment]::GetFolderPath("Desktop")
$script:StartMenuPath = Join-Path ([Environment]::GetFolderPath("Programs")) "XAMPP Tools"

# ============================================================
# FUNCTIONS
# ============================================================

function Get-PowerShellExe {
    # Prefer pwsh (PS7), fall back to Windows PowerShell
    $pwsh = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    return "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
}

function New-XamppShortcut {
    param(
        [string]$TargetPath,
        [string]$LinkName = "$script:AppName.lnk"
    )

    $psExe     = Get-PowerShellExe
    $arguments = "-NoExit -ExecutionPolicy Bypass -File `"$script:ToolsEntry`""
    $wsh       = New-Object -ComObject WScript.Shell
    $shortcut  = $wsh.CreateShortcut((Join-Path $TargetPath $LinkName))

    $shortcut.TargetPath       = $psExe
    $shortcut.Arguments        = $arguments
    $shortcut.WorkingDirectory = $moduleRoot
    $shortcut.Description      = "XAMPP Tools - Dev environment manager"

    if (Test-Path $script:IconIco) {
        $shortcut.IconLocation = $script:IconIco
    } elseif (Test-Path $script:IconPng) {
        $shortcut.IconLocation = $script:IconPng
    } else {
        # Fallback: use powershell's own icon
        $shortcut.IconLocation = "$psExe,0"
    }

    $shortcut.Save()
    return (Join-Path $TargetPath $LinkName)
}

function Show-ShortcutStatus {
    $desktopLink   = Join-Path $script:DesktopPath   "$script:AppName.lnk"
    $startMenuLink = Join-Path $script:StartMenuPath "$script:AppName.lnk"

    Write-Host ""
    Write-Host "  Current Status:" -ForegroundColor White
    Write-Host "    Desktop   : $(if (Test-Path $desktopLink)   { '✅ Exists' } else { '⚫ Not created' })" -ForegroundColor Gray
    Write-Host "    Start Menu: $(if (Test-Path $startMenuLink) { '✅ Exists' } else { '⚫ Not created' })" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================
# MAIN
# ============================================================

Show-Header
Write-Host "  🖥️  Create Shortcuts" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray

Show-ShortcutStatus

Write-Host "    1) Create Desktop shortcut" -ForegroundColor Gray
Write-Host "    2) Create Start Menu shortcut" -ForegroundColor Gray
Write-Host "    3) Create Both" -ForegroundColor Gray
Write-Host "    4) Remove All Shortcuts" -ForegroundColor Gray
Write-Host ""
Write-Host "    0) Back" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "  Select option"

switch ($choice) {
    '1' {
        try {
            $path = New-XamppShortcut -TargetPath $script:DesktopPath
            Write-Success "Desktop shortcut created: $path"
        } catch {
            Write-Error2 "Failed: $($_.Exception.Message)"
        }
    }
    '2' {
        try {
            if (-not (Test-Path $script:StartMenuPath)) {
                New-Item -ItemType Directory -Path $script:StartMenuPath -Force | Out-Null
            }
            $path = New-XamppShortcut -TargetPath $script:StartMenuPath
            Write-Success "Start Menu shortcut created: $path"
        } catch {
            Write-Error2 "Failed: $($_.Exception.Message)"
        }
    }
    '3' {
        $errors = 0
        try {
            $d = New-XamppShortcut -TargetPath $script:DesktopPath
            Write-Success "Desktop   : $d"
        } catch {
            Write-Error2 "Desktop failed: $($_.Exception.Message)"
            $errors++
        }
        try {
            if (-not (Test-Path $script:StartMenuPath)) {
                New-Item -ItemType Directory -Path $script:StartMenuPath -Force | Out-Null
            }
            $s = New-XamppShortcut -TargetPath $script:StartMenuPath
            Write-Success "Start Menu: $s"
        } catch {
            Write-Error2 "Start Menu failed: $($_.Exception.Message)"
            $errors++
        }
        if ($errors -eq 0) {
            Write-Host ""
            Write-Info "All shortcuts created successfully"
        }
    }
    '4' {
        $desktopLink   = Join-Path $script:DesktopPath   "$script:AppName.lnk"
        $startMenuLink = Join-Path $script:StartMenuPath "$script:AppName.lnk"
        $removed = 0

        if (Test-Path $desktopLink) {
            Remove-Item $desktopLink -Force
            Write-Success "Desktop shortcut removed"
            $removed++
        }
        if (Test-Path $startMenuLink) {
            Remove-Item $startMenuLink -Force
            Write-Success "Start Menu shortcut removed"
            $removed++
        }
        if ($removed -eq 0) {
            Write-Info "No shortcuts found to remove"
        }
    }
    '0' { return }
    default {
        Write-Warning2 "Invalid option"
    }
}

Write-Host ""
Show-ShortcutStatus
