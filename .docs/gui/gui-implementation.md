# GUI Implementation — XAMPP-Tools TUI Dashboard

> Pure PowerShell terminal UI. No external dependencies. Full-screen dashboard with keyboard navigation, live status, sparklines, and search.

---

## Files

| File | Role |
|---|---|
| `xampp-tools/bin/Dashboard.ps1` | Full TUI engine — panels, input loop, data collectors |
| `xampp-tools/Xampp-Tools.ps1` | Entry point — dot-sources Dashboard.ps1, calls `Start-Dashboard` |

---

## How to Run

```powershell
.\xampp-tools\Xampp-Tools.ps1
```

Requires **Windows Terminal** or VS Code terminal (ANSI + Unicode support). Minimum 120×36.

---

## Architecture

```
Xampp-Tools.ps1
  ├── Common.ps1            (dot-sourced — Load-EnvFile, Test-Administrator, Get-WindowsPhpConfig)
  ├── Service-Helpers.ps1   (dot-sourced — Get-XamppStatus, $script:XamppRoot)
  └── Dashboard.ps1         (dot-sourced — Start-Dashboard)
        │
        ├── Data Collectors
        │     ├── Get-DashboardStatus()   Apache/MySQL/PHP/SSL/config/vhosts
        │     ├── Get-SystemMetrics()     CPU/RAM/Disk + sparkline history queues
        │     └── Get-LogPreview()        Last N lines of apache/logs/error.log
        │
        ├── Primitives
        │     ├── Write-At()              Cursor-positioned colored Write-Host
        │     ├── Draw-Box()              Box with optional title (box-drawing chars)
        │     └── Get-Sparkline()         ▁▂▃▄▅▆▇█ from rolling history queue
        │
        ├── Panel Renderers
        │     ├── Draw-CommandCenter()    Left — scrollable module list
        │     ├── Draw-SystemStatus()     Center-top — Apache/MySQL/PHP/SSL cards
        │     ├── Draw-QuickStats()       Center-mid — CPU/RAM/Disk + sparklines
        │     ├── Draw-SystemHealth()     Center-bot — score circle + check grid
        │     ├── Draw-Shortcuts()        Right-top — 6 quick-launch buttons
        │     ├── Draw-LogPreview()       Right-mid — last 5 apache log lines
        │     └── Draw-HelpInfo()         Right-bot — key legend
        │
        ├── Render-Frame()               Full redraw: header + all panels + footer
        ├── Invoke-DashboardModule()     Run selected module, wait for keypress, return
        └── Start-Dashboard()           Main loop — input, search, auto-refresh
```

---

## Layout

```
  > xampp-tools    v2.0.0  [ADMIN]       XAMPP-TOOLS DASHBOARD                    14:37:22
                                        POWERFUL. SIMPLE. YOURS.
────────────────────────────────────────────────────────────────────────────────────────────
┌─ COMMAND CENTER ──────────────┬─ SYSTEM STATUS ─────────────────────────────┬─ SHORTCUTS ──────────────┐
│ Select option and press ENTER │                             [AUTO-REFRESH: ON]│ [ REDEPLOY ]  [ LOGS   ] │
│   1   Build Configs           │  APACHE    MYSQL    PHP      SSL              │ [ BACKUP DB ] [ SETUP SSL│
│   2   Deploy Configs          │  Running   Running  8.3.6    Active           │ [ KILL      ] [ ALIAS   ]│
│   3   Deploy VHosts           │  Port 80   Port 3306 CLI     HTTPS            ├─ LIVE LOG PREVIEW ───────┤
│▶  4   Redeploy                │                                               │ 14:36:01 [INFO] Apache.. │
│   5   Services                │  CONFIG: Valid   VHOSTS: 4   PHP EXT: 28      │ 14:36:10 [SUCCESS] done  │
│   ...                         ├─ QUICK STATS ───────────────────────────────┤ ...                      │
│                               │  CPU      RAM               DISK             ├─ HELP & INFO ────────────┤
│                               │  12%      3.2 GB / 16 GB    142 GB Free      │ > xampp-tools --help     │
│                               │  ▁▂▁▃▂▁  ▂▃▄▃▂▃▄▃          ▄▃▄▅▄▃▄▃        │ [up/dn] navigate         │
│                               ├─ SYSTEM HEALTH ────────────────────────────┤ [enter] execute          │
│                               │  .-------.  Everything looks good!          │ [/]     search           │
│                               │ /  97%    \ Your environment is running...  │ [F5]    refresh          │
│                               │ | HEALTHY | Apache: OK  MySQL: OK           │ [Q][0]  exit             │
│                               │  +-------+  Config: OK  SSL: Ready          │                          │
└───────────────────────────────┴─────────────────────────────────────────────┴──────────────────────────┘
────────────────────────────────────────────────────────────────────────────────────────────────────────────
 READY  │  Use ↑↓ navigate  ENTER select  / search  F5 refresh  Q quit         xampp-tools
```

---

## Keyboard Controls

| Key | Action |
|---|---|
| `↑` / `↓` | Navigate module list |
| `Enter` | Execute selected module |
| `/` | Enter search mode — type to filter live |
| `Esc` | Exit search mode, restore full list |
| `F5` | Force status refresh |
| `Q` / `0` | Exit dashboard |

---

## Data Refresh

Status data (Apache, MySQL, PHP, SSL, config, vhosts) refreshes every **12 seconds** automatically, or immediately after a module runs. CPU/RAM/Disk are sampled each refresh and pushed into rolling 10-sample queues for sparkline rendering.

The render loop polls for keypresses every 100ms (`[Console]::KeyAvailable`) with 20ms micro-sleeps — CPU usage is negligible.

---

## Module Color Coding

| Color | Modules |
|---|---|
| Magenta | Build Configs, Deploy Configs, Deploy VHosts, Redeploy, Backup Configs |
| Blue | Create Database, Backup MySQL, Restore MySQL, Setup MySQL, Cleanup MySQL |
| Yellow | Install PHP, Setup SSL, Firewall |
| Cyan | Services |
| Red | Kill Services |
| Gray | Alias, View Logs, XAMPP Controller, Startup Check, Create Shortcuts |

---

## Adding a New Module

Create `bin/modules/MyModule.ps1` with metadata headers — it auto-appears in the menu:

```powershell
# Name:        My Module
# Description: Does something useful
# Icon:        🔧
# Cmd:         my-module
# Order:       21
# Hidden:      false
```

No changes to `Xampp-Tools.ps1` or `Dashboard.ps1` needed.

---

## Optional Future Upgrades

| Upgrade | Effort | Notes |
|---|---|---|
| Section dividers in menu | 30m | Inject non-selectable header rows between Order ranges |
| Status bar message on module run | 30m | Pass last-action string into footer |
| Confirm dialog for destructive modules | 1h | Show-Confirm overlay before Kill/Restore |
| Notification dot on log errors | 30m | Check log for error lines, show badge on panel title |
| Right-click shortcut remapping | 1h | Config file for which 6 cmds appear in shortcuts panel |
