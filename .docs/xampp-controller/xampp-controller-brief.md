## Xampp Controller

### Overview
A xampp-tools submodule that wraps XAMPP's native control panel and service management, exposing start/stop/restart/status as named commands. Other modules can call these commands in sequence without needing to know XAMPP internals.

---

### Module: `Xampp-Controller.ps1`
- **Cmd**: `xampp`
- **Order**: `1` (runs before all other service-dependent modules)
- **File**: `c:\dev-tools\xampp-tools\bin\modules\Xampp-Controller.ps1`

---

### Commands

| Option | Command | Description |
|--------|---------|-------------|
| 1 | Start All | Start Apache + MySQL via XAMPP batch scripts |
| 2 | Stop All | Kill `httpd` + `mysqld` processes |
| 3 | Restart All | Stop → wait → Start |
| 4 | Open XAMPP UI | Launch `xampp-control.exe` window |
| 5 | Status | Show live process status for Apache, MySQL |
| 0 | Back | Return to main menu |

---

### XAMPP Integration Points

```
$xamppRoot\apache_start.bat      → starts Apache
$xamppRoot\apache_stop.bat       → stops Apache
$xamppRoot\mysql_start.bat       → starts MySQL
$xamppRoot\mysql_stop.bat        → stops MySQL
$xamppRoot\xampp-control.exe     → opens the XAMPP control panel GUI
```

All paths resolved from `XAMPP_ROOT_DIR` in `.env` (default: `C:\xampp`).

---

### Exported Helper Functions
These will be dot-sourced from `bin\Common.ps1` or called directly by other modules:

```powershell
Invoke-XamppStart   # starts Apache + MySQL
Invoke-XamppStop    # stops Apache + MySQL
Invoke-XamppRestart # restarts both
Get-XamppStatus     # returns hashtable { Apache: bool; MySQL: bool }
```

---

### Integration with Other Modules

Modules that require services to be running (e.g. `Backup-MySQL`, `Setup-MySQL`, `Deploy-VHosts`) can call:

```powershell
$status = Get-XamppStatus
if (-not $status.MySQL) {
    Write-Warning "MySQL not running — starting..."
    Invoke-XamppStart
}
```

This is added at the top of any module that needs a live service before proceeding.

---

### Sequence Flow Example (Redeploy)

```
xampp → stop-all
build-configs → (build templates)
deploy-configs → (write files)
xampp → start-all
startup-check → (verify ports/services)
```

---

### Implementation Notes

- Use `& cmd /c $batchScript` for XAMPP bat files (they rely on `cmd` environment)
- Background launch with `Start-Job` or `Start-Process -NoNewWindow` to avoid blocking
- `Get-Process -Name "httpd"` and `"mysqld"` are the reliable status checks
- `xampp-control.exe` should be launched with `Start-Process` (GUI app, fire-and-forget)
- Wrap all process kills in `ErrorAction SilentlyContinue` — services may already be stopped
- Add a 2–3s `Start-Sleep` after start/stop before re-checking status

---

### .env Dependencies

```ini
XAMPP_ROOT_DIR=C:\xampp
```

---

### Files to Create / Modify

| Action | File |
|--------|------|
| **Create** | `bin\modules\Xampp-Controller.ps1` |
| **Modify** | `bin\Common.ps1` — add `Invoke-XamppStart`, `Invoke-XamppStop`, `Invoke-XamppRestart`, `Get-XamppStatus` |
| **Modify** | `bin\modules\Backup-MySQL.ps1` — add pre-flight MySQL check |
| **Modify** | `bin\modules\Redeploy.ps1` — inject xampp stop/start around deploy steps |