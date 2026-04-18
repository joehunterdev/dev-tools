# PHP Version Installer — Implementation Plan

> Module: `bin/modules/Switch-PHP.ps1` (cmd: `install-php`, order: 13)

## Current State

The module **downloads** PHP versions to side-folders (`C:\xampp\php74`, `php80`, etc.) but does **not** switch the active Apache PHP. It's install-only — no backup, no Apache reconfig, no restart.

## Goal

Full PHP version switching for XAMPP:
1. Backup current PHP folder
2. Stop Apache/MySQL
3. Swap PHP folder
4. Patch Apache config (`httpd-xampp.conf`)
5. Copy `php.ini` settings from old version
6. Restart services
7. Verify

## Architecture

### Hooks (from Service-Helpers.ps1)
- `Get-XamppStatus` — pre-flight check
- `Invoke-XamppStop` — stop before swap
- `Invoke-XamppStart` — start after swap
- `Open-XamppControlPanel` — visual feedback
- `Test-ApacheConfigSyntax` — validate before restart
- `Show-XamppStatus` — post-restart confirmation

### Hooks (from Common.ps1)
- `Load-EnvFile` — read `.env` for `XAMPP_ROOT_DIR`, `PHP_VERSION`
- `Prompt-YesNo` — confirmations
- `Show-Step` — progress UI

---

## Flow

```
┌──────────────────────────────────────┐
│  1. Show current PHP + available     │
│     versions (installed / remote)    │
├──────────────────────────────────────┤
│  2. User selects version             │
├──────────────────────────────────────┤
│  3. Download if not already in       │
│     C:\xampp\php{ver} side-folder    │  ← existing Install-PhpVersion
├──────────────────────────────────────┤
│  4. Pre-flight                       │
│     - Open XAMPP Control Panel       │  ← Open-XamppControlPanel
│     - Show status                    │  ← Show-XamppStatus
│     - Stop services                  │  ← Invoke-XamppStop
├──────────────────────────────────────┤
│  5. Backup current C:\xampp\php      │
│     → C:\xampp\php_backup_{ver}_{ts} │
├──────────────────────────────────────┤
│  6. Swap folders                     │
│     - Rename php → php{old_ver}      │
│     - Copy php{new_ver} → php        │
│     (or rename if no side-folder     │
│      needed for old version)         │
├──────────────────────────────────────┤
│  7. Patch Apache config              │
│     - httpd-xampp.conf LoadFile      │
│       php{X}ts.dll                   │
│     - httpd-xampp.conf LoadModule    │
│       php{X}apache2_4.dll            │
├──────────────────────────────────────┤
│  8. Migrate php.ini                  │
│     - Copy critical settings from    │
│       old php.ini into new one       │
│     - Or use our template if avail   │
├──────────────────────────────────────┤
│  9. Validate                         │
│     - Test-ApacheConfigSyntax        │
│     - If FAIL → rollback (restore    │
│       backup folder, revert conf)    │
├──────────────────────────────────────┤
│ 10. Restart                          │
│     - Invoke-XamppStart              │
│     - Show-XamppStatus               │
│     - php -v to confirm              │
├──────────────────────────────────────┤
│ 11. Update .env PHP_VERSION          │
└──────────────────────────────────────┘
```

---

## New Functions to Add

### `Switch-ActivePhp`
Main orchestrator. Params: `-Version` (e.g. `"8.3"`)

```
Steps:
  1. Resolve paths ($xamppRoot\php, $xamppRoot\php{ver})
  2. Assert target version is downloaded (call Install-PhpVersion if not)
  3. Open-XamppControlPanel
  4. Invoke-XamppStop
  5. Backup-CurrentPhp
  6. Swap-PhpFolders
  7. Patch-ApachePhpConfig
  8. Migrate-PhpIni
  9. Test-ApacheConfigSyntax → rollback on fail
 10. Invoke-XamppStart
 11. Verify-PhpVersion
 12. Update-EnvPhpVersion
```

### `Backup-CurrentPhp`
```powershell
# Renames C:\xampp\php → C:\xampp\php_backup_{ver}_{yyyyMMdd_HHmmss}
# Also archives to backups\ dir as zip (optional)
```

### `Swap-PhpFolders`
```powershell
# 1. Rename current php → php{old_ver}  (e.g. php84)
#    - Skip if php{old_ver} already exists (backup is enough)
# 2. Copy php{new_ver} → php
#    - Use Copy-Item -Recurse (keep side-folder intact)
```

### `Patch-ApachePhpConfig`
```powershell
# Target: apache\conf\extra\httpd-xampp.conf
# Replace:
#   LoadFile "C:/xampp/php/php8ts.dll"    → php{X}ts.dll
#   LoadModule php_module "C:/xampp/php/php8apache2_4.dll" → correct module
# Also handle 7.x → 8.x transition (php7ts.dll vs php8ts.dll)
```

### `Migrate-PhpIni`
```powershell
# Strategy:
#   1. If our template exists in config/optimized/templates/php/ → build from template
#   2. Otherwise, copy key settings from old php.ini:
#      - extension_dir, extensions list
#      - upload_max_filesize, post_max_size, memory_limit
#      - curl.cainfo, openssl.cafile
#      - error_reporting, display_errors
#      - date.timezone
#      - All custom settings from .env
```

### `Verify-PhpVersion`
```powershell
# Run C:\xampp\php\php.exe -v
# Confirm output matches expected version
# Run php -m to check extensions loaded
```

### `Restore-PhpBackup` (rollback)
```powershell
# If config test fails after swap:
#   1. Remove new php folder
#   2. Rename backup → php
#   3. Revert httpd-xampp.conf
#   4. Start services
#   5. Report failure
```

---

## Menu Restructure

Current menu only has install. New menu:

```
  🔄 PHP Version Manager
  ─────────────────────────────────────────

  Current: PHP 8.4.13 (C:\xampp\php)

  Installed:
    ✅ 8.4.13  ← ACTIVE
    ✅ 8.3.15  (C:\xampp\php83)
    ⚫ 8.2     [Not installed]
    ⚫ 8.1     [Not installed]

  1) Switch active PHP version
  2) Install additional PHP version
  3) Remove installed version
  4) Rebuild php.ini from template
  0) Back

  >:
```

Option 1 → `Switch-ActivePhp` (full swap flow)
Option 2 → `Install-PhpVersion` (existing, download-only)
Option 3 → Remove side-folder
Option 4 → Rebuild php.ini using Build-Configs template pipeline

---

## Files Modified

| File | Change |
|---|---|
| `bin/modules/Switch-PHP.ps1` | Rewrite with switch + install + rollback |
| `bin/Service-Helpers.ps1` | No changes (already has everything needed) |
| `.env` | `PHP_VERSION` updated after switch |
| `config/config.json` | `php.curlCainfo` / `php.opensslCafile` already there |
| `apache/conf/extra/httpd-xampp.conf` | Patched by `Patch-ApachePhpConfig` |

---

## Safety

- **Backup before swap** — timestamped folder + optional zip
- **Config test before restart** — `httpd -t` validates Apache won't break
- **Auto-rollback** — if config test fails, restore backup automatically
- **XAMPP Control Panel open** — user sees services stop/start visually
- **Version verify** — `php -v` confirms the switch worked
- **.env updated last** — only after everything succeeds

---

## Edge Cases

| Case | Handling |
|---|---|
| Same version selected | Skip with message |
| Download fails | Abort, no changes made |
| Apache config test fails | Rollback to backup |
| Services won't stop | `Stop-Process -Force` fallback (existing in Service-Helpers) |
| Missing VC++ redistributable | Detect via `php.exe -v` error, show download link |
| Thread safety mismatch | Registry only lists TS builds |
| Old php.ini has custom extensions | Migrate-PhpIni copies them across |
