# ============================================================
# Dashboard.ps1 - Full TUI Engine for XAMPP Tools
# ============================================================
# Requires: Common.ps1 and Service-Helpers.ps1 dot-sourced first
# ============================================================

# ── Box-drawing chars via code point (encoding-safe) ────────
$script:TL = [char]0x250C  # ┌
$script:TR = [char]0x2510  # ┐
$script:BL = [char]0x2514  # └
$script:BR = [char]0x2518  # ┘
$script:HZ = [char]0x2500  # ─
$script:VT = [char]0x2502  # │
$script:LT = [char]0x251C  # ├
$script:RT = [char]0x2524  # ┤

# Sparkline block chars
$script:Sparks = [char]0x2581,[char]0x2582,[char]0x2583,[char]0x2584,[char]0x2585,[char]0x2586,[char]0x2587,[char]0x2588

# Rolling history for sparklines (last 10 samples)
$script:CpuHistory  = [System.Collections.Generic.Queue[int]]::new()
$script:RamHistory  = [System.Collections.Generic.Queue[int]]::new()
$script:DiskHistory = [System.Collections.Generic.Queue[int]]::new()

# ============================================================
# PRIMITIVES
# ============================================================

function Write-At {
    param([int]$X, [int]$Y, [string]$Text, [string]$Fg = "White", [string]$Bg = $null)
    if ($Y -lt 0 -or $X -lt 0) { return }
    try {
        [Console]::SetCursorPosition($X, $Y)
        if ($Bg) { Write-Host $Text -ForegroundColor $Fg -BackgroundColor $Bg -NoNewline }
        else      { Write-Host $Text -ForegroundColor $Fg -NoNewline }
    } catch {}
}

function Draw-Box {
    param(
        [int]$X, [int]$Y, [int]$W, [int]$H,
        [string]$Title = "",
        [string]$BorderColor = "DarkCyan",
        [string]$TitleColor  = "Cyan"
    )
    $inner = $W - 2
    if ($Title) {
        $t   = " $Title "
        $pad = $inner - $t.Length
        if ($pad -lt 0) { $t = $t.Substring(0, $inner); $pad = 0 }
        $l   = [int]($pad / 2)
        $r   = $pad - $l
        $top = "$($script:TL)$([string]$script:HZ * $l)$t$([string]$script:HZ * $r)$($script:TR)"
    } else {
        $top = "$($script:TL)$([string]$script:HZ * $inner)$($script:TR)"
    }
    Write-At $X $Y $top $BorderColor
    for ($i = 1; $i -lt $H - 1; $i++) {
        Write-At $X         ($Y + $i) $script:VT $BorderColor
        Write-At ($X+$W-1)  ($Y + $i) $script:VT $BorderColor
    }
    Write-At $X ($Y + $H - 1) "$($script:BL)$([string]$script:HZ * $inner)$($script:BR)" $BorderColor
}

function Get-Sparkline {
    param([System.Collections.Generic.Queue[int]]$History, [int]$Length = 10)
    $line = ""
    $vals = @($History)
    while ($vals.Count -lt $Length) { $vals = @(0) + $vals }
    $vals = $vals | Select-Object -Last $Length
    foreach ($v in $vals) {
        $idx = [int]([math]::Min($v, 99) / 100 * ($script:Sparks.Count - 1))
        $line += $script:Sparks[$idx]
    }
    return $line
}

# ============================================================
# DATA COLLECTORS
# ============================================================

function Get-DashboardStatus {
    # Services
    $svc = Get-XamppStatus   # returns @{ Apache=[bool]; MySQL=[bool] }

    # PHP version
    $phpVer = "Not found"
    try {
        $php = Get-Command php -ErrorAction Stop
        $raw = & $php.Source -r "echo PHP_VERSION;" 2>$null
        if ($raw -match '[\d\.]+') { $phpVer = $raw.Trim() }
    } catch {}

    # SSL cert
    $sslReady = $false
    if ($script:XamppRoot) {
        $sslReady = Test-Path (Join-Path $script:XamppRoot "apache\conf\ssl.crt\server.crt")
    }

    # Config valid (cached apache syntax — only check if Apache is running)
    $configOk = $false
    if ($svc.Apache -and $script:XamppRoot) {
        $httpd = Join-Path $script:XamppRoot "apache\bin\httpd.exe"
        if (Test-Path $httpd) {
            $result = & $httpd -t 2>&1
            $configOk = ($result -join "") -match "Syntax OK"
        }
    }

    # VHost count
    $vhostCount = 0
    $vhostPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "xampp-tools\config\vhosts.json"
    if (-not (Test-Path $vhostPath)) {
        $vhostPath = Join-Path $PSScriptRoot "..\config\vhosts.json"
    }
    if (Test-Path $vhostPath) {
        try {
            $vhosts = Get-Content $vhostPath -Raw | ConvertFrom-Json
            $vhostCount = @($vhosts.sites).Count
        } catch {}
    }

    # PHP extension count
    $phpExtCount = 0
    try {
        $extList = & php -m 2>$null
        $phpExtCount = @($extList | Where-Object { $_ -notmatch '^\[' -and $_.Trim() }).Count
    } catch {}

    # System info (cached - expensive)
    $sysInfo = $null
    try { $sysInfo = Get-WindowsPhpConfig } catch {}

    return @{
        Apache      = $svc.Apache
        MySQL       = $svc.MySQL
        PHP         = $phpVer
        SSL         = $sslReady
        ConfigOK    = $configOk
        VHostCount  = $vhostCount
        PhpExtCount = $phpExtCount
        SysInfo     = $sysInfo
        XamppRoot   = $script:XamppRoot
    }
}

function Get-SystemMetrics {
    $m = @{ CPU = 0; RamUsed = 0; RamTotal = 0; DiskFree = 0; DiskTotal = 0 }
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
        $m.CPU = [int]($cpu | Measure-Object -Property LoadPercentage -Average).Average
    } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $m.RamUsed  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
        $m.RamTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    } catch {}
    try {
        $d = Get-PSDrive -Name C -ErrorAction Stop
        $m.DiskFree  = [math]::Round($d.Free  / 1GB, 0)
        $m.DiskTotal = [math]::Round(($d.Used + $d.Free) / 1GB, 0)
    } catch {}

    # Push to history queues (keep last 10)
    $script:CpuHistory.Enqueue($m.CPU)
    $ramPct = if ($m.RamTotal -gt 0) { [int]($m.RamUsed / $m.RamTotal * 100) } else { 0 }
    $script:RamHistory.Enqueue($ramPct)
    $diskPct = if ($m.DiskTotal -gt 0) { [int](($m.DiskTotal - $m.DiskFree) / $m.DiskTotal * 100) } else { 0 }
    $script:DiskHistory.Enqueue($diskPct)
    while ($script:CpuHistory.Count  -gt 10) { [void]$script:CpuHistory.Dequeue()  }
    while ($script:RamHistory.Count  -gt 10) { [void]$script:RamHistory.Dequeue()  }
    while ($script:DiskHistory.Count -gt 10) { [void]$script:DiskHistory.Dequeue() }

    return $m
}

function Get-LogPreview {
    param([int]$Lines = 5)
    $logPath = $null
    if ($script:XamppRoot) {
        $logPath = Join-Path $script:XamppRoot "apache\logs\error.log"
    }
    if (-not $logPath -or -not (Test-Path $logPath)) {
        return @("  No log file found")
    }
    $raw = Get-Content $logPath -Tail $Lines -ErrorAction SilentlyContinue
    if (-not $raw) { return @("  Log is empty") }
    return @($raw)
}

# ============================================================
# PANEL RENDERERS
# ============================================================

function Draw-CommandCenter {
    param([array]$Modules, [int]$SelectedIdx, [int]$X, [int]$Y, [int]$W, [int]$H)

    Draw-Box $X $Y $W $H "COMMAND CENTER"
    Write-At ($X+2) ($Y+1) "Select option and press ENTER" "DarkGray"

    $maxRows  = $H - 4
    $scroll   = [math]::Max(0, $SelectedIdx - [int]($maxRows / 2))
    $scroll   = [math]::Min($scroll, [math]::Max(0, $Modules.Count - $maxRows))

    for ($i = 0; $i -lt $maxRows; $i++) {
        $mi = $i + $scroll
        if ($mi -ge $Modules.Count) { break }
        $m   = $Modules[$mi]
        $row = $Y + 2 + $i
        $num = "{0,2}" -f ($mi + 1)

        # Clear line
        Write-At ($X+1) $row (" " * ($W-2)) "White"

        if ($mi -eq $SelectedIdx) {
            $label = ("  $num  $($m.Icon) $($m.Name)").PadRight($W - 2)
            Write-At ($X+1) $row $label "Black" "Green"
        } else {
            $color = switch -Wildcard ($m.Cmd) {
                "*mysql*"    { "Blue"    }
                "*backup*"   { "Blue"    }
                "*restore*"  { "Blue"    }
                "*redeploy*" { "Magenta" }
                "*deploy*"   { "Magenta" }
                "*build*"    { "Magenta" }
                "*config*"   { "Magenta" }
                "*ssl*"      { "Yellow"  }
                "*firewall*" { "Yellow"  }
                "*php*"      { "Yellow"  }
                "*service*"  { "Cyan"    }
                "*kill*"     { "Red"     }
                "*exit*"     { "DarkGray"}
                default      { "Gray"    }
            }
            Write-At ($X+1) $row "  $num  $($m.Icon) $($m.Name)" $color
        }
    }

    # Scroll indicator
    if ($Modules.Count -gt $maxRows) {
        $pct = [int]($scroll / [math]::Max(1, $Modules.Count - $maxRows) * ($maxRows - 1))
        Write-At ($X+$W-1) ($Y+2+$pct) [char]0x2588 "DarkGreen"
    }
}

function Draw-SystemStatus {
    param($Status, [int]$X, [int]$Y, [int]$W, [int]$H)

    Draw-Box $X $Y $W $H "SYSTEM STATUS"
    Write-At ($X+$W-20) $Y " [AUTO-REFRESH: ON] " "DarkGray"

    # Row 1: service status cards
    $cards = @(
        @{ Label="APACHE"; Val=if($Status.Apache){"Running"}else{"Stopped"}; Sub="Port 80";   Color=if($Status.Apache){"Green"}else{"Red"} },
        @{ Label="MYSQL";  Val=if($Status.MySQL) {"Running"}else{"Stopped"}; Sub="Port 3306"; Color=if($Status.MySQL) {"Green"}else{"Red"} },
        @{ Label="PHP";    Val=$Status.PHP;                                   Sub="CLI Ready"; Color=if($Status.PHP -ne "Not found"){"Green"}else{"Red"} },
        @{ Label="SSL";    Val=if($Status.SSL)   {"Active"}  else{"None"};   Sub="HTTPS";     Color=if($Status.SSL)   {"Green"}else{"Yellow"} }
    )
    $spacing = [int](($W - 4) / $cards.Count)
    for ($i = 0; $i -lt $cards.Count; $i++) {
        $cx = $X + 3 + ($i * $spacing)
        $c  = $cards[$i]
        Write-At $cx ($Y+2) $c.Label "DarkGray"
        Write-At $cx ($Y+3) $c.Val   $c.Color
        Write-At $cx ($Y+4) $c.Sub   "DarkGray"
    }

    # Row 2: config details
    $configStr  = "CONFIG: $(if($Status.ConfigOK){'Valid'}else{'N/A'})"
    $vhostStr   = "VHOSTS: $($Status.VHostCount) sites"
    $extStr     = "PHP EXT: $($Status.PhpExtCount) loaded"
    $configColor = if ($Status.ConfigOK) { "Green" } else { "DarkGray" }
    Write-At ($X+3)  ($Y+6) $configStr  $configColor
    Write-At ($X+22) ($Y+6) $vhostStr   "Cyan"
    Write-At ($X+42) ($Y+6) $extStr     "Cyan"

    # Row 3: paths
    $root = if ($Status.XamppRoot) { $Status.XamppRoot } else { "C:\xampp" }
    Write-At ($X+3)  ($Y+8) "XAMPP ROOT: $root"   "Yellow"
    Write-At ($X+3)  ($Y+9) "BACKUPS:    .\backups\" "Yellow"

    # Row 4: system info
    if ($Status.SysInfo) {
        $arch = "$($Status.SysInfo.Arch)  $($Status.SysInfo.OS)"
        $rt   = if ($Status.SysInfo.Runtimes.Count) { $Status.SysInfo.Runtimes -join ' ' } else { "None detected" }
        $rtColor = if ($Status.SysInfo.Runtimes.Count) { "Green" } else { "Yellow" }
        Write-At ($X+3)  ($Y+11) "ARCH: $arch"  "Gray"
        Write-At ($X+3)  ($Y+12) "VC++: $rt"    $rtColor
    }
}

function Draw-QuickStats {
    param($Metrics, [int]$X, [int]$Y, [int]$W, [int]$H)

    Draw-Box $X $Y $W $H "QUICK STATS"

    $cpuColor  = if ($Metrics.CPU -gt 80)    { "Red"     } elseif ($Metrics.CPU -gt 50)    { "Yellow"  } else { "Green"   }
    $ramPct    = if ($Metrics.RamTotal -gt 0) { [int]($Metrics.RamUsed / $Metrics.RamTotal * 100) } else { 0 }
    $ramColor  = if ($ramPct -gt 85)          { "Red"     } elseif ($ramPct -gt 65)          { "Yellow"  } else { "Magenta" }
    $diskColor = if ($Metrics.DiskFree -lt 10){ "Red"     } elseif ($Metrics.DiskFree -lt 30){ "Yellow"  } else { "Yellow"  }

    $colW = [int](($W - 4) / 3)

    # CPU
    $cx = $X + 3
    Write-At $cx ($Y+1) "CPU"                                      "DarkGray"
    Write-At $cx ($Y+2) "$($Metrics.CPU)%"                         $cpuColor
    Write-At $cx ($Y+3) (Get-Sparkline $script:CpuHistory)         $cpuColor

    # RAM
    $rx = $X + 3 + $colW
    Write-At $rx ($Y+1) "RAM"                                       "DarkGray"
    Write-At $rx ($Y+2) "$($Metrics.RamUsed) GB / $($Metrics.RamTotal) GB" $ramColor
    Write-At $rx ($Y+3) (Get-Sparkline $script:RamHistory)          $ramColor

    # Disk
    $dx = $X + 3 + ($colW * 2)
    Write-At $dx ($Y+1) "DISK  C:\"                                  "DarkGray"
    Write-At $dx ($Y+2) "$($Metrics.DiskFree) GB Free"               $diskColor
    Write-At $dx ($Y+3) (Get-Sparkline $script:DiskHistory)          $diskColor
}

function Draw-SystemHealth {
    param($Status, [int]$X, [int]$Y, [int]$W, [int]$H)

    Draw-Box $X $Y $W $H "SYSTEM HEALTH"

    $checks = @(
        @{ N="Apache";  OK=$Status.Apache  },
        @{ N="MySQL";   OK=$Status.MySQL   },
        @{ N="PHP";     OK=($Status.PHP -ne "Not found") },
        @{ N="SSL";     OK=$Status.SSL     },
        @{ N="Config";  OK=$Status.ConfigOK},
        @{ N="VHosts";  OK=($Status.VHostCount -gt 0) }
    )
    $okCount   = ($checks | Where-Object { $_.OK }).Count
    $score     = [int]($okCount / $checks.Count * 100)
    $hColor    = if ($score -eq 100) { "Green" } elseif ($score -ge 66) { "Yellow" } else { "Red" }
    $hLabel    = if ($score -eq 100) { "Everything looks good!" } elseif ($score -ge 66) { "Some issues detected." } else { "Attention required." }
    $hSubLabel = if ($score -eq 100) { "Your environment is running smoothly." } else { "Check the items marked below." }

    # ASCII circle
    Write-At ($X+3) ($Y+1) "   .-------."   $hColor
    Write-At ($X+3) ($Y+2) "  /         \"  $hColor
    Write-At ($X+3) ($Y+3) " |   $("{0,3}%" -f $score)   |"  $hColor
    Write-At ($X+3) ($Y+4) "  \         /"  $hColor
    Write-At ($X+3) ($Y+5) "   +-------+"   $hColor
    Write-At ($X+5) ($Y+7) " HEALTHY"        $hColor

    Write-At ($X+18) ($Y+2) $hLabel    $hColor
    Write-At ($X+18) ($Y+3) $hSubLabel "Gray"

    # Check grid
    $col = $X + 18; $row = $Y + 5
    foreach ($chk in $checks) {
        $ico = if ($chk.OK) { "OK  " } else { "FAIL" }
        $clr = if ($chk.OK) { "Green" } else { "Red"  }
        Write-At $col $row "$($chk.N): $ico" $clr
        $col += 16
        if ($col -gt ($X + $W - 16)) { $col = $X + 18; $row++ }
    }
}

function Draw-Shortcuts {
    param([array]$Modules, [int]$X, [int]$Y, [int]$W, [int]$H)

    Draw-Box $X $Y $W $H "SHORTCUTS"

    $pins = @(
        @{ Cmd="redeploy";      Label="REDEPLOY";  Color="Magenta" },
        @{ Cmd="view-logs";     Label="LOGS";      Color="Gray"    },
        @{ Cmd="backup-mysql";  Label="BACKUP DB"; Color="Blue"    },
        @{ Cmd="setup-ssl";     Label="SETUP SSL"; Color="Yellow"  },
        @{ Cmd="kill-services"; Label="KILL";      Color="Red"     },
        @{ Cmd="alias";         Label="ALIAS";     Color="Gray"    }
    )

    for ($i = 0; $i -lt $pins.Count; $i++) {
        $col = if ($i % 2 -eq 0) { $X + 2 } else { $X + [int]($W/2) }
        $row = $Y + 2 + [int]($i / 2) * 2
        Write-At $col $row "[ $($pins[$i].Label.PadRight(8)) ]" $pins[$i].Color
    }
}

function Draw-LogPreview {
    param([string[]]$Lines, [int]$X, [int]$Y, [int]$W, [int]$H)

    Draw-Box $X $Y $W $H "LIVE LOG PREVIEW"
    Write-At ($X+$W-15) $Y " [LAST 5 LINES] " "DarkGray"

    $maxLines = $H - 2
    $display  = @($Lines | Select-Object -Last $maxLines)

    for ($i = 0; $i -lt $display.Count; $i++) {
        $line = $display[$i]
        $color = switch -Regex ($line) {
            "error|crit|alert|emerg" { "Red"    }
            "warn"                   { "Yellow" }
            "\[SUCCESS\]"            { "Green"  }
            "\[INFO\]"               { "Cyan"   }
            default                  { "DarkGray" }
        }
        $maxLen = $W - 4
        if ($line.Length -gt $maxLen) { $line = $line.Substring(0, $maxLen - 2) + ".." }
        Write-At ($X+2) ($Y+1+$i) (" " * ($W-4)) "White"
        Write-At ($X+2) ($Y+1+$i) $line $color
    }
}

function Draw-HelpInfo {
    param([int]$X, [int]$Y, [int]$W, [int]$H)

    Draw-Box $X $Y $W $H "HELP & INFO"

    $lines = @(
        @{ T="> xampp-tools --help";    C="Green"    },
        @{ T="A powerful dev toolkit";  C="Gray"     },
        @{ T="for local environments";  C="Gray"     },
        @{ T="";                        C="DarkGray" },
        @{ T="[up/dn]  navigate";       C="DarkGray" },
        @{ T="[enter]  execute";        C="DarkGray" },
        @{ T="[/]      search";         C="DarkGray" },
        @{ T="[F5]     refresh";        C="DarkGray" },
        @{ T="[Q][0]   exit";          C="DarkGray" }
    )

    for ($i = 0; $i -lt [math]::Min($lines.Count, $H - 2); $i++) {
        Write-At ($X+2) ($Y+1+$i) $lines[$i].T $lines[$i].C
    }
}

# ============================================================
# FULL FRAME RENDER
# ============================================================

function Render-Frame {
    param(
        [array]   $Modules,
        [int]     $SelectedIdx,
        $Status,
        $Metrics,
        [string[]]$LogLines,
        [bool]    $SearchMode,
        [string]  $SearchQuery
    )

    $W = [math]::Max($Host.UI.RawUI.WindowSize.Width,  120)
    $H = [math]::Max($Host.UI.RawUI.WindowSize.Height, 36)

    # Column widths
    $LW = 32
    $RW = 32
    $CW = $W - $LW - $RW

    # Row heights
    $BY      = 3    # body start (below header)
    $bodyH   = $H - $BY - 3   # leave room for footer

    $statusH = [int]($bodyH * 0.40)
    $quickH  = [int]($bodyH * 0.20)
    $healthH = $bodyH - $statusH - $quickH

    $shortH  = [int]($bodyH * 0.32)
    $logH    = [int]($bodyH * 0.32)
    $helpH   = $bodyH - $shortH - $logH

    # Enforce minimums
    $statusH = [math]::Max($statusH, 10)
    $quickH  = [math]::Max($quickH,  6)
    $healthH = [math]::Max($healthH, 8)
    $shortH  = [math]::Max($shortH,  8)
    $logH    = [math]::Max($logH,    7)
    $helpH   = [math]::Max($helpH,   7)

    $CX = $LW
    $RX = $LW + $CW

    [Console]::CursorVisible = $false

    # Jump to top without clearing (no flash)
    [Console]::SetCursorPosition(0, 0)

    # ── HEADER ──────────────────────────────────────────────
    $brand    = "  > xampp-tools    v2.0.0"
    $title    = "XAMPP-TOOLS DASHBOARD"
    $subtitle = "POWERFUL. SIMPLE. YOURS."
    $time     = Get-Date -Format "HH:mm:ss"
    $adminStr = if (Test-Administrator) { " [ADMIN] " } else { " [USER]  " }
    $adminClr = if (Test-Administrator) { "Green" }     else { "Yellow"  }

    $line0 = " " * $W
    [Console]::SetCursorPosition(0, 0); Write-Host $line0 -NoNewline
    Write-At 0             0 $brand    "Green"
    Write-At 20            0 $adminStr $adminClr "DarkGray"
    Write-At ([int](($W - $title.Length) / 2)) 0 $title "Cyan"
    Write-At ($W - 9)      0 $time     "Blue"

    $line1 = " " * $W
    [Console]::SetCursorPosition(0, 1); Write-Host $line1 -NoNewline
    Write-At ([int](($W - $subtitle.Length) / 2)) 1 $subtitle "Magenta"

    Write-At 0 2 ([string]$script:HZ * $W) "DarkGray"

    # ── PANELS ──────────────────────────────────────────────
    Draw-CommandCenter $Modules $SelectedIdx 0       $BY $LW $bodyH
    Draw-SystemStatus  $Status               $CX     $BY $CW $statusH
    Draw-QuickStats    $Metrics              $CX     ($BY + $statusH)               $CW $quickH
    Draw-SystemHealth  $Status               $CX     ($BY + $statusH + $quickH)     $CW $healthH
    Draw-Shortcuts     $Modules              $RX     $BY                             $RW $shortH
    Draw-LogPreview    $LogLines             $RX     ($BY + $shortH)                 $RW $logH
    Draw-HelpInfo                            $RX     ($BY + $shortH + $logH)         $RW $helpH

    # ── FOOTER ──────────────────────────────────────────────
    $FY = $BY + $bodyH
    Write-At 0 $FY ([string]$script:HZ * $W) "DarkGray"

    $statusLine = " " * $W
    [Console]::SetCursorPosition(0, $FY+1); Write-Host $statusLine -NoNewline

    Write-At 0         ($FY+1) " READY "  "Black"   "Green"
    Write-At 7         ($FY+1) " $($script:VT) "    "DarkGray"
    if ($SearchMode) {
        Write-At 10 ($FY+1) "  Search: $SearchQuery█" "White"
    } else {
        Write-At 10 ($FY+1) "  Use ↑↓ navigate  ENTER select  / search  F5 refresh  Q quit" "DarkGray"
    }
    Write-At ($W - 14) ($FY+1) " xampp-tools" "Magenta"

    [Console]::CursorVisible = $false
}

# ============================================================
# MODULE INVOKE
# ============================================================

function Invoke-DashboardModule {
    param($Module)

    [Console]::CursorVisible = $true
    Clear-Host

    Write-Host ""
    Write-Host "  Running: $($Module.Icon) $($Module.Name)" -ForegroundColor Cyan
    Write-Host "  $([string]([char]0x2500) * 50)" -ForegroundColor DarkGray
    Write-Host ""

    try {
        & $Module.Path
    } catch {
        Write-Host ""
        Write-Host "  Error running module: $_" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  $([string]([char]0x2500) * 50)" -ForegroundColor DarkGray
    Write-Host "  Press any key to return to dashboard..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null
}

# ============================================================
# MAIN LOOP
# ============================================================

function Start-Dashboard {
    param([array]$Modules)

    $visibleMods = @($Modules | Where-Object { -not $_.Hidden })

    # Append an Exit entry
    $exitMod = @{ Name="Exit"; Icon=[char]0x23FB; Cmd="exit"; Order=999; Hidden=$false; Path=""; Description="Exit dashboard" }
    $allMods = @($visibleMods) + @($exitMod)

    $idx          = 0
    $searchMode   = $false
    $searchQuery  = ""
    $filtered     = $allMods

    # Initial empty metrics
    $status  = @{ Apache=$false; MySQL=$false; PHP="..."; SSL=$false; ConfigOK=$false; VHostCount=0; PhpExtCount=0; SysInfo=$null; XamppRoot=$script:XamppRoot }
    $metrics = @{ CPU=0; RamUsed=0; RamTotal=0; DiskFree=0; DiskTotal=0 }
    $logs    = @("Loading...")

    $refreshEvery = 12   # seconds between status refresh
    $lastRefresh  = [datetime]::MinValue

    [Console]::TreatControlCAsInput = $false

    try {
        while ($true) {

            # Refresh data
            if (([datetime]::Now - $lastRefresh).TotalSeconds -ge $refreshEvery) {
                $status      = Get-DashboardStatus
                $metrics     = Get-SystemMetrics
                $logs        = Get-LogPreview -Lines 5
                $lastRefresh = [datetime]::Now
            }

            # Render
            Render-Frame `
                -Modules      $filtered `
                -SelectedIdx  $idx `
                -Status       $status `
                -Metrics      $metrics `
                -LogLines     $logs `
                -SearchMode   $searchMode `
                -SearchQuery  $searchQuery

            # Wait for input (100ms polling keeps CPU low)
            $deadline = [datetime]::Now.AddMilliseconds(100)
            $gotKey   = $false
            while ([datetime]::Now -lt $deadline) {
                if ([Console]::KeyAvailable) { $gotKey = $true; break }
                Start-Sleep -Milliseconds 20
            }

            if (-not $gotKey) {
                # Auto-refresh tick — if refresh is due just loop again
                continue
            }

            $key = [Console]::ReadKey($true)

            # ── SEARCH MODE ─────────────────────────────────
            if ($searchMode) {
                switch ($key.Key) {
                    "Escape" {
                        $searchMode  = $false
                        $searchQuery = ""
                        $filtered    = $allMods
                        $idx         = 0
                    }
                    "Backspace" {
                        if ($searchQuery.Length -gt 0) {
                            $searchQuery = $searchQuery.Substring(0, $searchQuery.Length - 1)
                        }
                        $filtered = if ($searchQuery) {
                            @($allMods | Where-Object { $_.Name -like "*$searchQuery*" -or $_.Cmd -like "*$searchQuery*" })
                        } else { $allMods }
                        $idx = 0
                    }
                    "Enter" {
                        $searchMode = $false
                        if ($filtered.Count -gt 0 -and $filtered[$idx].Cmd -ne "exit") {
                            Invoke-DashboardModule $filtered[$idx]
                            $lastRefresh = [datetime]::MinValue
                        } elseif ($filtered[$idx].Cmd -eq "exit") { return }
                        $filtered    = $allMods
                        $searchQuery = ""
                        $idx         = 0
                    }
                    "UpArrow"   { if ($idx -gt 0)                     { $idx-- } }
                    "DownArrow" { if ($idx -lt $filtered.Count - 1)   { $idx++ } }
                    default {
                        if ($key.KeyChar -match '[a-zA-Z0-9\-\s]') {
                            $searchQuery += $key.KeyChar
                            $filtered = @($allMods | Where-Object { $_.Name -like "*$searchQuery*" -or $_.Cmd -like "*$searchQuery*" })
                            $idx = 0
                        }
                    }
                }
            }
            # ── NORMAL MODE ──────────────────────────────────
            else {
                switch ($key.Key) {
                    "UpArrow"   { if ($idx -gt 0)                     { $idx-- } }
                    "DownArrow" { if ($idx -lt $filtered.Count - 1)   { $idx++ } }
                    "Enter" {
                        if ($filtered.Count -gt 0) {
                            $sel = $filtered[$idx]
                            if ($sel.Cmd -eq "exit") { return }
                            Invoke-DashboardModule $sel
                            $lastRefresh = [datetime]::MinValue
                        }
                    }
                    "F5" { $lastRefresh = [datetime]::MinValue }
                    default {
                        switch ($key.KeyChar) {
                            "/"          { $searchMode = $true; $searchQuery = "" }
                            { $_ -in "q","Q","0" } { return }
                        }
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        Clear-Host
    }
}
