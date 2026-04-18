$W=130
$TL=[char]0x250C;$TR=[char]0x2510;$BL=[char]0x2514;$BR=[char]0x2518
$H=[char]0x2500;$V=[char]0x2502
function wa($x,$y,$t,$f='White',$b=$null){[Console]::SetCursorPosition($x,$y);if($b){Write-Host $t -ForegroundColor $f -BackgroundColor $b -NoNewline}else{Write-Host $t -ForegroundColor $f -NoNewline}}
function box($x,$y,$w,$h,$ti='',$bc='DarkCyan'){
  $in=$w-2
  if($ti){$t=' '+$ti+' ';$p=$in-$t.Length;$l=[int]($p/2);$r=$p-$l;$top=$TL+($H*$l)+$t+($H*$r)+$TR}else{$top=$TL+($H*$in)+$TR}
  wa $x $y $top $bc
  for($i=1;$i -lt $h-1;$i++){wa $x ($y+$i) $V $bc;wa ($x+$w-1) ($y+$i) $V $bc;wa ($x+1) ($y+$i) (' '*$in) White}
  wa $x ($y+$h-1) ($BL+($H*$in)+$BR) $bc
}
[Console]::CursorVisible=$false;Clear-Host
$ti='XAMPP-TOOLS DASHBOARD';$su='POWERFUL. SIMPLE. YOURS.';$tm=Get-Date -Format 'HH:mm:ss'
wa 0 0 '  > xampp-tools    v2.0.0' Green
wa ([int](($W-$ti.Length)/2)) 0 $ti Cyan
wa ($W-$tm.Length-1) 0 $tm Blue
wa ([int](($W-$su.Length)/2)) 1 $su Magenta
wa 0 2 ($H*$W) DarkGray
$LW=32;$RW=32;$CW=$W-$LW-$RW;$BY=3
$bodyH=30;$statH=13;$quickH=7;$hlthH=$bodyH-$statH-$quickH
$shortH=10;$logH=10;$helpH=$bodyH-$shortH-$logH
$CX=$LW;$RX=$LW+$CW
box 0 $BY $LW ($bodyH+1) 'COMMAND CENTER' DarkCyan
wa 2 ($BY+1) 'Select option and press ENTER' DarkGray
$items=@(
  @{n='Build Configs';c='Magenta'},@{n='Deploy Configs';c='Magenta'},@{n='Deploy VHosts';c='Magenta'},
  @{n='Redeploy';c='Magenta';s=$true},@{n='Create Shortcuts';c='Gray'},@{n='Services';c='Cyan'},
  @{n='Kill Services';c='Red'},@{n='Create Database';c='Blue'},@{n='Backup MySQL';c='Blue'},
  @{n='Restore MySQL';c='Blue'},@{n='Setup MySQL';c='Blue'},@{n='Cleanup MySQL';c='Blue'},
  @{n='Install PHP';c='Yellow'},@{n='Setup SSL';c='Yellow'},@{n='Backup Configs';c='Magenta'},
  @{n='Alias';c='Gray'},@{n='View Logs';c='Gray'},@{n='XAMPP Controller';c='Gray'},
  @{n='Startup Check';c='Gray'},@{n='Firewall';c='Yellow'},@{n='Exit';c='DarkGray'}
)
for($i=0;$i -lt $items.Count;$i++){
  $m=$items[$i];$row=$BY+2+$i;$num='{0,2}'-f($i+1);if($i -eq 20){$num=' 0'}
  if($m.s){$lbl=('  '+$num+'  > '+$m.n).PadRight($LW-2);wa 1 $row $lbl Black Green}
  else{wa 1 $row ('  '+$num+'    '+$m.n) $m.c}
}
box $CX $BY $CW $statH 'SYSTEM STATUS' DarkCyan
wa ($CX+$CW-20) $BY ' [AUTO-REFRESH: ON] ' DarkGray
wa ($CX+3) ($BY+2) 'APACHE' DarkGray;wa ($CX+3) ($BY+3) 'Running' Green;wa ($CX+3) ($BY+4) 'Port 80' DarkGray
wa ($CX+20) ($BY+2) 'PHP' DarkGray;wa ($CX+20) ($BY+3) '8.3.6' Green;wa ($CX+20) ($BY+4) 'CLI Ready' DarkGray
wa ($CX+37) ($BY+2) 'MYSQL' DarkGray;wa ($CX+37) ($BY+3) 'Running' Green;wa ($CX+37) ($BY+4) 'Port 3306' DarkGray
wa ($CX+55) ($BY+2) 'SSL' DarkGray;wa ($CX+55) ($BY+3) 'Active' Green;wa ($CX+55) ($BY+4) 'HTTPS Ready' DarkGray
wa ($CX+3) ($BY+6) 'CONFIG: Valid' Green;wa ($CX+22) ($BY+6) 'VHOSTS: 4 sites' Cyan;wa ($CX+42) ($BY+6) 'PHP EXT: 28 loaded' Cyan
wa ($CX+3) ($BY+8) 'XAMPP ROOT: C:\xampp' Yellow;wa ($CX+28) ($BY+8) 'BACKUPS: .\backups\' Yellow
wa ($CX+3) ($BY+10) 'ARCH: x64  Windows 10 Pro' Gray;wa ($CX+33) ($BY+10) 'VC++: VC14 VC15 VC16 OK' Green
$QY=$BY+$statH
box $CX $QY $CW $quickH 'QUICK STATS' DarkCyan
wa ($CX+3) ($QY+2) 'CPU' DarkGray;wa ($CX+3) ($QY+3) '12%' Green
wa ($CX+3) ($QY+4) ([string][char]0x2581+[char]0x2582+[char]0x2581+[char]0x2582+[char]0x2583+[char]0x2581+[char]0x2582+[char]0x2581) DarkGreen
wa ($CX+20) ($QY+2) 'RAM' DarkGray;wa ($CX+20) ($QY+3) '3.2 GB / 16 GB' Magenta
wa ($CX+20) ($QY+4) ([string][char]0x2582+[char]0x2583+[char]0x2584+[char]0x2583+[char]0x2583+[char]0x2582+[char]0x2583+[char]0x2584) DarkMagenta
wa ($CX+42) ($QY+2) 'DISK  C:\' DarkGray;wa ($CX+42) ($QY+3) '142 GB Free' Yellow
wa ($CX+42) ($QY+4) ([string][char]0x2584+[char]0x2584+[char]0x2583+[char]0x2584+[char]0x2585+[char]0x2584+[char]0x2584+[char]0x2583) DarkYellow
$HY=$QY+$quickH
box $CX $HY $CW $hlthH 'SYSTEM HEALTH' DarkCyan
wa ($CX+3) ($HY+1) '   .------.' Green
wa ($CX+3) ($HY+2) '  /        \' Green
wa ($CX+3) ($HY+3) ' |   97%   |' Green
wa ($CX+3) ($HY+4) '  \        /' Green
wa ($CX+3) ($HY+5) '   +------+' Green
wa ($CX+4) ($HY+7) ' HEALTHY' Green
wa ($CX+18) ($HY+2) 'Everything looks good!' Green
wa ($CX+18) ($HY+3) 'Your environment is running smoothly.' Gray
wa ($CX+18) ($HY+5) 'Apache: OK' Green;wa ($CX+32) ($HY+5) 'MySQL: OK' Green;wa ($CX+45) ($HY+5) 'PHP: OK' Green;wa ($CX+56) ($HY+5) 'SSL: Ready' Green
wa ($CX+18) ($HY+6) 'Config: OK' Green;wa ($CX+32) ($HY+6) 'VHosts: OK' Green;wa ($CX+45) ($HY+6) 'Backups: OK' Green
box $RX $BY $RW $shortH 'SHORTCUTS' DarkCyan
$sc=@(@{l='REDEPLOY';c='Magenta'},@{l='LOGS';c='Gray'},@{l='BACKUP DB';c='Blue'},@{l='SETUP SSL';c='Yellow'},@{l='KILL';c='Red'},@{l='ALIAS';c='Gray'})
for($i=0;$i -lt $sc.Count;$i++){$col=if($i%2 -eq 0){$RX+2}else{$RX+17};$row=$BY+2+[int]($i/2)*2;wa $col $row ('[ '+$sc[$i].l+' ]') $sc[$i].c}
$LPY=$BY+$shortH
box $RX $LPY $RW $logH 'LIVE LOG PREVIEW' DarkCyan
wa ($RX+$RW-14) $LPY ' [LAST 5 LINES] ' DarkGray
$logs=@(@{t='14:36:01';l='[INFO]   ';m='Apache ready';c='Cyan'},@{t='14:36:02';l='[INFO]   ';m='MySQL OK';c='Cyan'},@{t='14:36:05';l='[INFO]   ';m='Config valid';c='Cyan'},@{t='14:36:10';l='[SUCCESS]';m='Backup done';c='Green'},@{t='14:36:15';l='[INFO]   ';m='System optimal';c='Cyan'})
for($i=0;$i -lt $logs.Count;$i++){wa ($RX+2) ($LPY+1+$i) $logs[$i].t DarkGray;wa ($RX+10) ($LPY+1+$i) $logs[$i].l $logs[$i].c;wa ($RX+20) ($LPY+1+$i) $logs[$i].m Gray}
$HPY=$LPY+$logH
box $RX $HPY $RW $helpH 'HELP & INFO' DarkCyan
wa ($RX+2) ($HPY+1) '> xampp-tools --help' Green
wa ($RX+2) ($HPY+2) 'A powerful dev toolkit' Gray
wa ($RX+2) ($HPY+3) 'for local environments' Gray
wa ($RX+2) ($HPY+5) '[up/dn]  navigate' DarkGray
wa ($RX+2) ($HPY+6) '[enter]  execute' DarkGray
wa ($RX+2) ($HPY+7) '[/]      search' DarkGray
wa ($RX+2) ($HPY+8) '[Q][0]   exit' DarkGray
$FY=$BY+$bodyH+1
wa 0 $FY ($H*$W) DarkGray
wa 0 ($FY+1) ' READY ' Black Green
wa 8 ($FY+1) ' | ' DarkGray
wa 11 ($FY+1) 'Use up/down to navigate, ENTER to select, / to search, Q to quit' DarkGray
wa ($W-13) ($FY+1) 'xampp-tools' Magenta
[Console]::SetCursorPosition(0,$FY+3);[Console]::CursorVisible=$true
