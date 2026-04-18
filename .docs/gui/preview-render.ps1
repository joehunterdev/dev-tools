# Static preview render — no interactivity, just draws the dashboard once
# Run: powershell -File preview-render.ps1

$W = 130  # total width

function wa { param($x,$y,$text,$fg="White",$bg=$null)
    [Console]::SetCursorPosition($x,$y)
    if ($bg) { Write-Host $text -ForegroundColor $fg -BackgroundColor $bg -NoNewline }
    else      { Write-Host $text -ForegroundColor $fg -NoNewline }
}

function box { param($x,$y,$w,$h,$title="",$bc="DarkCyan",$tc="Cyan")
    $inner = $w - 2
    if ($title) {
        $t = " $title "; $pad = $inner - $t.Length
        $l = [int]($pad/2); $r = $pad - $l
        $top = "┌" + ("─"*$l) + $t + ("─"*$r) + "┐"
    } else { $top = "┌" + ("─"*$inner) + "┐" }
    wa $x $y $top $bc
    for ($i=1;$i -lt $h-1;$i++){
        wa $x ($y+$i) "│" $bc
        wa ($x+$w-1) ($y+$i) "│" $bc
        # fill interior with spaces
        wa ($x+1) ($y+$i) (" "*($w-2)) "White"
    }
    wa $x ($y+$h-1) ("└"+"─"*$inner+"┘") $bc
}

[Console]::CursorVisible = $false
Clear-Host

# ── HEADER ─────────────────────────────────────────────────────────────────
$title    = "XAMPP-TOOLS DASHBOARD"
$subtitle = "POWERFUL. SIMPLE. YOURS."
$brand    = "  > xampp-tools    v2.0.0"
$time     = Get-Date -Format "HH:mm:ss"
$titleX   = [int](($W - $title.Length) / 2)
$subX     = [int](($W - $subtitle.Length) / 2)

wa 0 0 $brand "Green"
wa $titleX 0 $title "Cyan"
wa ($W - $time.Length - 1) 0 $time "Blue"
wa $subX 1 $subtitle "Magenta"
wa 0 2 ("─"*$W) "DarkGray"

# ── LAYOUT ─────────────────────────────────────────────────────────────────
$LW = 32   # left panel width
$RW = 32   # right panel width
$CW = $W - $LW - $RW  # center width = 66
$BY = 3    # body start Y

$bodyH   = 30
$statH   = 13
$quickH  = 7
$hlthH   = $bodyH - $statH - $quickH  # 10

$shortH  = 10
$logH    = 10
$helpH   = $bodyH - $shortH - $logH   # 10

# ── LEFT: Command Center ────────────────────────────────────────────────────
box 0 $BY $LW ($bodyH+1) "COMMAND CENTER" "DarkCyan" "Cyan"
wa 2 ($BY+1) "Select option and press ENTER" "DarkGray"

$items = @(
    @{n="Build Configs";     i="🔧"; c="Magenta"},
    @{n="Deploy Configs";    i="🚀"; c="Magenta"},
    @{n="Deploy VHosts";     i="📦"; c="Magenta"},
    @{n="Redeploy";          i="♻️ "; c="Magenta"; sel=$true},
    @{n="Create Shortcuts";  i="🔗"; c="Gray"},
    @{n="Services";          i="⚙️ "; c="Cyan"},
    @{n="Kill Services";     i="💀"; c="Red"},
    @{n="Create Database";   i="🗄️ "; c="Blue"},
    @{n="Backup MySQL";      i="💾"; c="Blue"},
    @{n="Restore MySQL";     i="🔄"; c="Blue"},
    @{n="Setup MySQL";       i="🔧"; c="Blue"},
    @{n="Cleanup MySQL";     i="🧹"; c="Blue"},
    @{n="Install PHP";       i="🐘"; c="Yellow"},
    @{n="Setup SSL";         i="🔒"; c="Yellow"},
    @{n="Backup Configs";    i="📋"; c="Magenta"},
    @{n="Alias";             i="🔗"; c="Gray"},
    @{n="View Logs";         i="📋"; c="Gray"},
    @{n="XAMPP Controller";  i="🎮"; c="Gray"},
    @{n="Startup Check";     i="🚀"; c="Gray"},
    @{n="Firewall";          i="🔥"; c="Yellow"},
    @{n="Exit";              i="⏻ "; c="DarkGray"}
)

for ($i=0; $i -lt $items.Count -and $i -lt 21; $i++) {
    $m = $items[$i]
    $row = $BY + 2 + $i
    $num = "{0,2}" -f ($i+1); if ($i -eq 20) { $num = " 0" }
    if ($m.sel) {
        $label = ("  $num  $($m.i) $($m.n)").PadRight($LW-2)
        wa 1 $row $label "Black" "Green"
    } else {
        wa 1 $row "  $num  $($m.i) $($m.n)" $m.c
    }
}

# ── CENTER: System Status ───────────────────────────────────────────────────
$CX = $LW
box $CX $BY $CW ($statH) "SYSTEM STATUS" "DarkCyan" "Cyan"
wa ($CX+$CW-20) $BY " [AUTO-REFRESH: ON] " "DarkGray"

# Apache card
wa ($CX+3)  ($BY+2) "APACHE"          "DarkGray"
wa ($CX+3)  ($BY+3) "🟢 Running"      "Green"
wa ($CX+3)  ($BY+4) "Port 80"         "DarkGray"

# PHP card
wa ($CX+20) ($BY+2) "PHP"             "DarkGray"
wa ($CX+20) ($BY+3) "8.3.6"          "Green"
wa ($CX+20) ($BY+4) "CLI Ready"       "DarkGray"

# MySQL card
wa ($CX+37) ($BY+2) "MYSQL"           "DarkGray"
wa ($CX+37) ($BY+3) "🟢 Running"      "Green"
wa ($CX+37) ($BY+4) "Port 3306"       "DarkGray"

# SSL card
wa ($CX+55) ($BY+2) "SSL"             "DarkGray"
wa ($CX+55) ($BY+3) "✅ Active"       "Green"
wa ($CX+55) ($BY+4) "HTTPS Ready"     "DarkGray"

# divider label
wa ($CX+3) ($BY+6) "APACHE CONFIG:" "DarkGray"
wa ($CX+18) ($BY+6) "✅ Valid" "Green"
wa ($CX+30) ($BY+6) "VHOSTS:" "DarkGray"
wa ($CX+38) ($BY+6) "4 sites" "Cyan"
wa ($CX+50) ($BY+6) "PHP EXT:" "DarkGray"
wa ($CX+59) ($BY+6) "28 loaded" "Cyan"

wa ($CX+3) ($BY+8)  "XAMPP ROOT:" "DarkGray"
wa ($CX+15) ($BY+8) "C:\xampp" "Yellow"
wa ($CX+28) ($BY+8) "BACKUP DIR:" "DarkGray"
wa ($CX+40) ($BY+8) ".\backups\" "Yellow"

wa ($CX+3) ($BY+10) "ARCH:" "DarkGray"
wa ($CX+9) ($BY+10) "x64  Windows 10 Pro" "Gray"
wa ($CX+32) ($BY+10) "VC++:" "DarkGray"
wa ($CX+38) ($BY+10) "VC14 VC15 VC16 ✅" "Green"

# ── CENTER: Quick Stats ─────────────────────────────────────────────────────
$QY = $BY + $statH
box $CX $QY $CW ($quickH) "QUICK STATS" "DarkCyan" "Cyan"

wa ($CX+3)  ($QY+2) "CPU"                    "DarkGray"
wa ($CX+3)  ($QY+3) "12%"                    "Green"
wa ($CX+3)  ($QY+4) "▁▂▁▂▃▁▂▁▂▃"            "DarkGreen"

wa ($CX+20) ($QY+2) "RAM"                    "DarkGray"
wa ($CX+20) ($QY+3) "3.2 GB / 16 GB"        "Magenta"
wa ($CX+20) ($QY+4) "▂▃▄▃▃▂▃▄▃▂"            "DarkMagenta"

wa ($CX+42) ($QY+2) "DISK  C:\"              "DarkGray"
wa ($CX+42) ($QY+3) "142 GB Free"            "Yellow"
wa ($CX+42) ($QY+4) "▄▄▃▄▄▅▄▄▃▄"            "DarkYellow"

# ── CENTER: System Health ───────────────────────────────────────────────────
$HY = $QY + $quickH
box $CX $HY $CW ($hlthH) "SYSTEM HEALTH" "DarkCyan" "Cyan"

# ASCII donut approximation
wa ($CX+3)  ($HY+1) "   ╭──────╮"   "Green"
wa ($CX+3)  ($HY+2) "  ╭╯      ╰╮"  "Green"
wa ($CX+3)  ($HY+3) "  │  97%  │"   "Green"
wa ($CX+3)  ($HY+4) "  ╰╮      ╭╯"  "Green"
wa ($CX+3)  ($HY+5) "   ╰──────╯"   "Green"
wa ($CX+5)  ($HY+7) "HEALTHY"        "Green"

wa ($CX+18) ($HY+2) "Everything looks good!"              "Green"
wa ($CX+18) ($HY+3) "Your environment is running smoothly." "Gray"

wa ($CX+18) ($HY+5) "✅ Apache"    "Green"
wa ($CX+32) ($HY+5) "✅ MySQL"     "Green"
wa ($CX+46) ($HY+5) "✅ PHP"       "Green"
wa ($CX+57) ($HY+5) "✅ SSL"       "Green"

wa ($CX+18) ($HY+6) "✅ Config"    "Green"
wa ($CX+32) ($HY+6) "✅ VHosts"    "Green"
wa ($CX+46) ($HY+6) "✅ Backups"   "Green"
wa ($CX+57) ($HY+6) "✅ Firewall"  "Green"

# ── RIGHT: Shortcuts ────────────────────────────────────────────────────────
$RX = $LW + $CW
box $RX $BY $RW $shortH "SHORTCUTS" "DarkCyan" "Cyan"

$sc = @(
    @{l="REDEPLOY";  c="Magenta"}, @{l="LOGS";     c="Gray"},
    @{l="BACKUP DB"; c="Blue"},    @{l="SETUP SSL"; c="Yellow"},
    @{l="KILL";      c="Red"},     @{l="ALIAS";     c="Gray"}
)
for ($i=0;$i -lt $sc.Count;$i++) {
    $col = if ($i%2 -eq 0) { $RX+2 } else { $RX+17 }
    $row = $BY + 2 + [int]($i/2)*2
    wa $col $row "[ $($sc[$i].l) ]" $sc[$i].c
}

# ── RIGHT: Log Preview ──────────────────────────────────────────────────────
$LPY = $BY + $shortH
box $RX $LPY $RW $logH "LIVE LOG PREVIEW" "DarkCyan" "Cyan"
wa ($RX+$RW-14) $LPY " [LAST 5 LINES] " "DarkGray"

$logs = @(
    @{t="14:36:01"; l="[INFO]   "; m="Apache ready";    c="Cyan"},
    @{t="14:36:02"; l="[INFO]   "; m="MySQL check OK";  c="Cyan"},
    @{t="14:36:05"; l="[INFO]   "; m="Config valid";    c="Cyan"},
    @{t="14:36:10"; l="[SUCCESS]"; m="Backup done";     c="Green"},
    @{t="14:36:15"; l="[INFO]   "; m="System optimal";  c="Cyan"}
)
for ($i=0;$i -lt $logs.Count;$i++) {
    $lg = $logs[$i]
    wa ($RX+2) ($LPY+1+$i) $lg.t "DarkGray"
    wa ($RX+10) ($LPY+1+$i) $lg.l $lg.c
    wa ($RX+20) ($LPY+1+$i) $lg.m "Gray"
}

# ── RIGHT: Help & Info ──────────────────────────────────────────────────────
$HPY = $LPY + $logH
box $RX $HPY $RW $helpH "HELP & INFO" "DarkCyan" "Cyan"
wa ($RX+$RW-6) $HPY " [?] " "DarkGray"

wa ($RX+2) ($HPY+1) "> xampp-tools --help"   "Green"
wa ($RX+2) ($HPY+2) "A powerful dev toolkit" "Gray"
wa ($RX+2) ($HPY+3) "for local environments" "Gray"
wa ($RX+2) ($HPY+5) "↑↓   navigate"          "DarkGray"
wa ($RX+2) ($HPY+6) "ENTER execute"          "DarkGray"
wa ($RX+2) ($HPY+7) "/    search"            "DarkGray"
wa ($RX+2) ($HPY+8) "Q/0  exit"             "DarkGray"

# ── FOOTER ──────────────────────────────────────────────────────────────────
$FY = $BY + $bodyH + 1
wa 0 $FY ("─"*$W) "DarkGray"
wa 0 ($FY+1) " READY " "Black" "Green"
wa 9 ($FY+1) "│" "DarkGray"
wa 11 ($FY+1) "Use ↑↓ to navigate, ENTER to select, / to search, Q to quit" "DarkGray"
wa ($W-14) ($FY+1) "xampp-tools" "Magenta"

# park cursor below UI
[Console]::SetCursorPosition(0, $FY+3)
[Console]::CursorVisible = $true
