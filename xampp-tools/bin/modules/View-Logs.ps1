# Name: View Logs
# Description: View and tail Apache, MySQL, and PHP error logs
# Icon: 📋
# Cmd: logs
# Order: 14
# Hidden: false

<#
.SYNOPSIS
    View Logs - Tail and view XAMPP logs (Apache, MySQL, PHP)

.DESCRIPTION
    Provides easy access to XAMPP log files:
    - Apache access log
    - Apache error log
    - MySQL error log
    - PHP error log
    
    Options:
    - Tail last N lines
    - Follow log in real-time (like tail -f)
    - Clear log files
    - Open in VS Code
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

# ============================================================
# CONFIGURATION
# ============================================================

$script:EnvFile = Join-Path $moduleRoot ".env"
$script:XamppRoot = "C:\xampp"

# Log file registry
$script:LogFiles = @{
    "apache-access" = @{
        Name = "Apache Access Log"
        Path = Join-Path $script:XamppRoot "apache\logs\access.log"
        Icon = "🌐"
        Color = "Cyan"
    }
    "apache-error" = @{
        Name = "Apache Error Log"
        Path = Join-Path $script:XamppRoot "apache\logs\error.log"
        Icon = "❌"
        Color = "Red"
    }
    "mysql-error" = @{
        Name = "MySQL Error Log"
        Path = Join-Path $script:XamppRoot "mysql\data\mysql_error.log"
        Icon = "🗄️"
        Color = "Yellow"
    }
    "php-error" = @{
        Name = "PHP Error Log"
        Path = Join-Path $script:XamppRoot "php\logs\php_error_log.txt"
        Icon = "🐘"
        Color = "Magenta"
    }
}

# ============================================================
# FUNCTIONS
# ============================================================

function Show-LogMenu {
    Write-Host "  Available Logs:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $index = 1
    foreach ($log in $script:LogFiles.GetEnumerator() | Sort-Object { $_.Value.Name }) {
        $logInfo = $log.Value
        $exists = Test-Path $logInfo.Path
        $status = if ($exists) { 
            $size = (Get-Item $logInfo.Path).Length
            $sizeStr = Format-FileSize $size
            "[$sizeStr]"
        } else { 
            "[Not Found]" 
        }
        $statusColor = if ($exists) { "Green" } else { "DarkGray" }
        
        Write-Host "  $index. $($logInfo.Icon) $($logInfo.Name)" -NoNewline -ForegroundColor $logInfo.Color
        Write-Host " $status" -ForegroundColor $statusColor
        Write-Host "     $($logInfo.Path)" -ForegroundColor DarkGray
        Write-Host ""
        $index++
    }
}

function Show-LogActions {
    Write-Host "  Actions:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. Tail (show last 50 lines)" -ForegroundColor Gray
    Write-Host "  2. Follow (live tail)" -ForegroundColor Gray
    Write-Host "  3. View all" -ForegroundColor Gray
    Write-Host "  4. Open in VS Code" -ForegroundColor Gray
    Write-Host "  5. Clear log file" -ForegroundColor Gray
    Write-Host "  6. Show log info" -ForegroundColor Gray
    Write-Host ""
}

function Format-FileSize {
    param([long]$Bytes)
    
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes bytes"
    }
}

function Get-LogChoice {
    param([string]$UserInput)
    
    if ($UserInput -match '^\d+$') {
        $idx = [int]$UserInput - 1
        $logKeys = @($script:LogFiles.Keys | Sort-Object { $script:LogFiles[$_].Name })
        if ($idx -ge 0 -and $idx -lt $logKeys.Count) {
            return $logKeys[$idx]
        }
    }
    
    # Check if input matches key directly
    if ($script:LogFiles.ContainsKey($UserInput)) {
        return $UserInput
    }
    
    return $null
}

function Show-LogTail {
    param(
        [string]$LogPath,
        [int]$Lines = 50
    )
    
    if (-not (Test-Path $LogPath)) {
        Write-Warning2 "Log file not found: $LogPath"
        return
    }
    
    Write-Host ""
    Write-Host "  Last $Lines lines:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $content = Get-Content $LogPath -Tail $Lines -ErrorAction SilentlyContinue
    
    if ($content) {
        foreach ($line in $content) {
            # Color-code based on content
            if ($line -match '\[error\]|\bERROR\b|Failed|Exception') {
                Write-Host $line -ForegroundColor Red
            } elseif ($line -match '\[warning\]|\bWARNING\b|\bWARN\b') {
                Write-Host $line -ForegroundColor Yellow
            } elseif ($line -match '\[notice\]|\[info\]|\bINFO\b|\bNote\b') {
                Write-Host $line -ForegroundColor Cyan
            } else {
                Write-Host $line -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "  (empty log)" -ForegroundColor DarkGray
    }
}

function Show-LogFollow {
    param([string]$LogPath)
    
    if (-not (Test-Path $LogPath)) {
        Write-Warning2 "Log file not found: $LogPath"
        return
    }
    
    Write-Host ""
    Write-Host "  Following log (Press Ctrl+C to stop)..." -ForegroundColor Yellow
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    try {
        Get-Content $LogPath -Wait -Tail 10 | ForEach-Object {
            if ($_ -match '\[error\]|\bERROR\b|Failed|Exception') {
                Write-Host $_ -ForegroundColor Red
            } elseif ($_ -match '\[warning\]|\bWARNING\b|\bWARN\b') {
                Write-Host $_ -ForegroundColor Yellow
            } elseif ($_ -match '\[notice\]|\[info\]|\bINFO\b|\bNote\b') {
                Write-Host $_ -ForegroundColor Cyan
            } else {
                Write-Host $_ -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host ""
        Write-Info "Stopped following log"
    }
}

function Clear-LogFile {
    param([string]$LogPath)
    
    if (-not (Test-Path $LogPath)) {
        Write-Warning2 "Log file not found: $LogPath"
        return
    }
    
    try {
        Clear-Content $LogPath -Force
        Write-Success "Log file cleared: $LogPath"
    } catch {
        Write-Error2 "Failed to clear log: $($_.Exception.Message)"
    }
}

function Show-LogInfo {
    param([string]$LogPath)
    
    if (-not (Test-Path $LogPath)) {
        Write-Warning2 "Log file not found: $LogPath"
        return
    }
    
    $file = Get-Item $LogPath
    $lines = (Get-Content $LogPath | Measure-Object -Line).Lines
    
    Write-Host ""
    Write-Host "  Log File Information:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Path:         $($file.FullName)" -ForegroundColor Gray
    Write-Host "  Size:         $(Format-FileSize $file.Length)" -ForegroundColor Gray
    Write-Host "  Lines:        $lines" -ForegroundColor Gray
    Write-Host "  Created:      $($file.CreationTime)" -ForegroundColor Gray
    Write-Host "  Last Modified: $($file.LastWriteTime)" -ForegroundColor Gray
    Write-Host ""
}

function Open-LogInVSCode {
    param([string]$LogPath)
    
    if (-not (Test-Path $LogPath)) {
        Write-Warning2 "Log file not found: $LogPath"
        return
    }
    
    try {
        # Try using code command first
        $codeCmd = Get-Command code -ErrorAction SilentlyContinue
        if ($codeCmd) {
            & code $LogPath
            Write-Success "Opened in VS Code: $LogPath"
            return
        }
        
        # Try common VS Code installation paths
        $vscPaths = @(
            "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
            "$env:ProgramFiles\Microsoft VS Code\Code.exe",
            "$env:ProgramFiles(x86)\Microsoft VS Code\Code.exe"
        )
        
        foreach ($path in $vscPaths) {
            if (Test-Path $path) {
                Start-Process -FilePath $path -ArgumentList $LogPath
                Write-Success "Opened in VS Code: $LogPath"
                return
            }
        }
        
        # Fallback to default text editor
        Write-Warning2 "VS Code not found, opening with default editor..."
        Start-Process $LogPath
        Write-Success "Opened: $LogPath"
        
    } catch {
        Write-Error2 "Failed to open file: $($_.Exception.Message)"
    }
}

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  📋 View Logs" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Show log menu
Show-LogMenu

Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Get log selection
Write-Host "  Select a log (number or name):" -ForegroundColor White
$logSelection = (Read-Host "  > ").Trim()

$logKey = Get-LogChoice $logSelection

if (-not $logKey) {
    Write-Error2 "Invalid selection"
    exit
}

$selectedLog = $script:LogFiles[$logKey]

Write-Host ""
Write-Host "  Selected: $($selectedLog.Icon) $($selectedLog.Name)" -ForegroundColor $selectedLog.Color
Write-Host ""

# Show actions
Show-LogActions

Write-Host "  Select an action:" -ForegroundColor White
$actionChoice = (Read-Host "  > ").Trim()

Write-Host ""

switch ($actionChoice) {
    "1" {
        # Tail
        Write-Host "  How many lines to show? (default: 50):" -ForegroundColor White
        $linesInput = (Read-Host "  > ").Trim()
        $lines = if ($linesInput -and $linesInput -match '^\d+$') { [int]$linesInput } else { 50 }
        
        Show-LogTail -LogPath $selectedLog.Path -Lines $lines
    }
    "2" {
        # Follow
        Show-LogFollow -LogPath $selectedLog.Path
    }
    "3" {
        # View all
        if (Test-Path $selectedLog.Path) {
            Write-Host "  Full log contents:" -ForegroundColor White
            Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            Get-Content $selectedLog.Path | ForEach-Object {
                if ($_ -match '\[error\]|\bERROR\b|Failed|Exception') {
                    Write-Host $_ -ForegroundColor Red
                } elseif ($_ -match '\[warning\]|\bWARNING\b|\bWARN\b') {
                    Write-Host $_ -ForegroundColor Yellow
                } else {
                    Write-Host $_ -ForegroundColor Gray
                }
            }
        } else {
            Write-Warning2 "Log file not found"
        }
    }
    "4" {
        # Open in VS Code
        Open-LogInVSCode -LogPath $selectedLog.Path
    }
    "5" {
        # Clear
        Write-Host "  Are you sure you want to clear this log?" -ForegroundColor Yellow
        if (Prompt-YesNo "  Clear $($selectedLog.Name)?") {
            Clear-LogFile -LogPath $selectedLog.Path
        } else {
            Write-Info "Cancelled"
        }
    }
    "6" {
        # Info
        Show-LogInfo -LogPath $selectedLog.Path
    }
    default {
        Write-Error2 "Invalid action"
        exit
    }
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
