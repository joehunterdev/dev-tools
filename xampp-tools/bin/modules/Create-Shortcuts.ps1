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
$script:IconIco     = Join-Path $moduleRoot "bin\assets\logo-lg.ico"
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

function Set-RunAsAdmin {
    param([string]$LnkPath)
    # Byte 21 (0x15) bit 0x20 = "Run as administrator"
    $bytes = [System.IO.File]::ReadAllBytes($LnkPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($LnkPath, $bytes)
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

    $lnkFullPath = Join-Path $TargetPath $LinkName
    Set-RunAsAdmin -LnkPath $lnkFullPath

    return $lnkFullPath
}

function Pin-ToTaskbar {
    # Create shortcut in a known folder so Shell.Application can find it
    $tempDir = Join-Path $env:TEMP "XamppToolsPin"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    $tempLnk = Join-Path $tempDir "$script:AppName.lnk"

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
    Set-RunAsAdmin -LnkPath $tempLnk

    # Use Shell.Application verb to pin (works on Windows 10 / early Win11)
    $shell  = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($tempDir)
    $item   = $folder.ParseName("$script:AppName.lnk")
    $verb   = $item.Verbs() | Where-Object { $_.Name -match 'taskbar|Task(&B)ar' -or $_.Name -eq 'Pin to tas&kbar' }

    if ($verb) {
        $verb.DoIt()
        Start-Sleep -Milliseconds 500
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        return 'pinned'
    }

    # Fallback for Win11 22H2+ — verb removed, copy to Quick Launch instead
    $quickLaunch = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch"
    if (Test-Path $quickLaunch) {
        Copy-Item $tempLnk (Join-Path $quickLaunch "$script:AppName.lnk") -Force
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        return 'quicklaunch'
    }

    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    return $false
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
            $result = Pin-ToTaskbar
            if ($result -eq 'pinned') {
                Write-Success "Pinned to taskbar"
            } elseif ($result -eq 'quicklaunch') {
                Write-Success "Added to Quick Launch (Win11 — right-click taskbar to pin)"
            } else {
                Write-Error2 "Could not pin to taskbar"
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
            $result = Pin-ToTaskbar
            if ($result -eq 'pinned') {
                Write-Success "Taskbar   : pinned"
            } elseif ($result -eq 'quicklaunch') {
                Write-Success "Taskbar   : added to Quick Launch"
            } else {
                Write-Error2 "Taskbar   : could not pin"
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
