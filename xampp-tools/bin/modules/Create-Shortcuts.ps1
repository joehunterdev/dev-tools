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
$script:TaskbarPath   = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"

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

function Pin-ToTaskbar {
    # Create a temp shortcut then use Shell verb to pin it
    $tempLnk = Join-Path $env:TEMP "$script:AppName.lnk"
    
    # First create the shortcut in temp
    $psExe     = Get-PowerShellExe
    $arguments = "-NoExit -ExecutionPolicy Bypass -File `"$script:ToolsEntry`""
    $wsh       = New-Object -ComObject WScript.Shell
    $shortcut  = $wsh.CreateShortcut($tempLnk)
    $shortcut.TargetPath       = $psExe
    $shortcut.Arguments        = $arguments
    $shortcut.WorkingDirectory = $moduleRoot
    $shortcut.Description      = "XAMPP Tools - Dev environment manager"
    if (Test-Path $script:IconIco) {
        $shortcut.IconLocation = $script:IconIco
    } elseif (Test-Path $script:IconPng) {
        $shortcut.IconLocation = $script:IconPng
    } else {
        $shortcut.IconLocation = "$psExe,0"
    }
    $shortcut.Save()
    
    # Copy to taskbar pinned folder
    if (Test-Path $script:TaskbarPath) {
        Copy-Item $tempLnk (Join-Path $script:TaskbarPath "$script:AppName.lnk") -Force
        Remove-Item $tempLnk -Force -ErrorAction SilentlyContinue
        return $true
    } else {
        Remove-Item $tempLnk -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Show-ShortcutStatus {
    $desktopLink   = Join-Path $script:DesktopPath   "$script:AppName.lnk"
    $startMenuLink = Join-Path $script:StartMenuPath "$script:AppName.lnk"

    Write-Host ""
    Write-Host "  Current Status:" -ForegroundColor White
    $taskbarLink  = Join-Path $script:TaskbarPath "$script:AppName.lnk"

    Write-Host "    Desktop   : $(if (Test-Path $desktopLink)   { '✅ Exists' } else { '⚫ Not created' })" -ForegroundColor Gray
    Write-Host "    Start Menu: $(if (Test-Path $startMenuLink) { '✅ Exists' } else { '⚫ Not created' })" -ForegroundColor Gray
    Write-Host "    Taskbar   : $(if (Test-Path $taskbarLink)   { '✅ Exists' } else { '⚫ Not created' })" -ForegroundColor Gray
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
Write-Host "    3) Pin to Taskbar" -ForegroundColor Gray
Write-Host "    4) Create All (Desktop + Start Menu + Taskbar)" -ForegroundColor Gray
Write-Host "    5) Remove All Shortcuts" -ForegroundColor Gray
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
        try {
            if (Pin-ToTaskbar) {
                Write-Success "Taskbar shortcut created"
                Write-Info "You may need to sign out/in or restart Explorer for it to appear"
            } else {
                Write-Error2 "Taskbar pin folder not found"
            }
        } catch {
            Write-Error2 "Failed: $($_.Exception.Message)"
        }
    }
    '4' {
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
        try {
            if (Pin-ToTaskbar) {
                Write-Success "Taskbar   : pinned"
            } else {
                Write-Error2 "Taskbar pin folder not found"
                $errors++
            }
        } catch {
            Write-Error2 "Taskbar failed: $($_.Exception.Message)"
            $errors++
        }
        if ($errors -eq 0) {
            Write-Host ""
            Write-Info "All shortcuts created successfully"
        }
    }
    '5' {
        $desktopLink   = Join-Path $script:DesktopPath   "$script:AppName.lnk"
        $startMenuLink = Join-Path $script:StartMenuPath "$script:AppName.lnk"
        $taskbarLink   = Join-Path $script:TaskbarPath   "$script:AppName.lnk"
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
        if (Test-Path $taskbarLink) {
            Remove-Item $taskbarLink -Force
            Write-Success "Taskbar shortcut removed"
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
