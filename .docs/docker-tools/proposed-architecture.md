# Docker Tools — Proposed Architecture

## Repo Strategy: Monorepo with Shared Top-Level

`dev-tools` is **the** repo. Shared configuration and reusable code live at the top level. `xampp-tools/` and `docker-tools/` are subdirectories that each contain only what is genuinely tool-specific. Update a shared helper once, both tools receive it.

This mirrors the direction xampp-tools is already evolving in — `bin/Service-Helpers.ps1` was recently extracted as a shared helper between modules. The same pattern applies one level up: shared helpers for both tools live in `common/`.

---

## Filesystem Layout

```
dev-tools/                          ← one git repo, clone this
│
│  ── Shared (top-level, one source of truth) ──────────────
├── .env                            ← gitignored, single env file for both tools
├── .env.example                    ← committed, ALL keys (XAMPP + Docker sections)
├── dev-tools.code-workspace
├── .gitignore
├── .docs/                          ← documentation (brief, plan, implementation)
│
├── config/
│   └── vhosts.json                 ← SHARED: single source of truth for sites
│
├── common/
│   ├── Common.ps1                  ← SHARED helpers: logging, env loading, prompts, header
│   ├── Service-Helpers.ps1         ← SHARED service control abstractions
│   ├── assets/
│   │   └── signature-lg.txt        ← ASCII banner (can be tool-switched by $script:ToolName)
│   └── modules/                    ← SHARED modules (identical logic, both tools use)
│       ├── Alias.ps1
│       ├── Firewall.ps1            ← accepts port list parameter
│       ├── Create-Ascii.ps1
│       ├── Backup-MySQL.ps1        ← accepts $DbExecutor script block
│       ├── Restore-MySQL.ps1       ← accepts $DbExecutor script block
│       ├── Create-Database.ps1     ← accepts $DbExecutor script block
│       └── View-Logs.ps1           ← accepts $LogSource script block
│
│  ── XAMPP-specific ────────────────────────────────────────
├── xampp-tools/
│   ├── Xampp-Tools.ps1             ← loads ../common + own bin/modules
│   ├── config/
│   │   ├── config.json             ← Apache/PHP/MySQL template mappings
│   │   └── optimized/
│   │       ├── templates/          ← Apache, XAMPP-specific templates
│   │       └── dist/               ← generated XAMPP configs
│   └── bin/
│       ├── Service-Helpers.ps1     ← (currently lives here; moves to common/ when docker-tools adopts it)
│       └── modules/                ← ONLY xampp-specific implementations
│           ├── Build-Configs.ps1
│           ├── Deploy-Configs.ps1
│           ├── Deploy-VHosts.ps1
│           ├── Setup-MySQL.ps1
│           ├── Setup-SSL.ps1       ← OpenSSL-based
│           ├── Switch-PHP.ps1      ← XAMPP PHP install
│           ├── Services.ps1
│           ├── Kill-Services.ps1
│           ├── Startup-Check.ps1
│           ├── Redeploy.ps1
│           ├── Xampp-Controller.ps1
│           ├── Install-Stripe-Package.ps1
│           ├── Cleanup-MySQL.ps1
│           ├── Create-Shortcuts.ps1
│           └── .private/
│
│  ── Docker-specific ───────────────────────────────────────
└── docker-tools/
    ├── Docker-Tools.ps1            ← loads ../common + own bin/modules
    ├── docker-compose.yml          ← generated, gitignored
    ├── Dockerfile                  ← php-fpm custom image (committed)
    ├── config/
    │   ├── config.json             ← Nginx/Docker template mappings
    │   ├── templates/
    │   │   ├── docker/
    │   │   │   └── docker-compose.yml.template
    │   │   ├── nginx/
    │   │   │   ├── nginx.conf.template
    │   │   │   └── vhost-blocks.template
    │   │   ├── php/
    │   │   │   └── php.ini.template
    │   │   └── mysql/
    │   │       └── my.cnf.template
    │   └── dist/                   ← generated, gitignored
    │       ├── nginx/
    │       │   ├── nginx.conf
    │       │   └── conf.d/
    │       ├── php/php.ini
    │       ├── mysql/my.cnf
    │       └── certs/
    ├── data/                       ← Docker volumes, gitignored
    │   ├── mysql/
    │   └── postgres/
    └── bin/
        └── modules/                ← ONLY docker-specific implementations
            ├── Build-Compose.ps1
            ├── Docker-Controller.ps1
            ├── Startup-Check.ps1
            ├── Setup-SSL.ps1       ← mkcert-based
            ├── Switch-PHP.ps1      ← rebuilds image
            ├── Install-Docker.ps1
            ├── Services.ps1
            ├── Kill-Services.ps1
            └── Redeploy.ps1
```

---

## Maintenance Impact

Updating **once** propagates to both tools:

| File | Location | Both tools consume |
|------|----------|-------------------|
| `Common.ps1` (header, logging, env, prompts) | `common/` | ✅ |
| `Service-Helpers.ps1` | `common/` | ✅ |
| `.env` | repo root | ✅ |
| `vhosts.json` | `config/` | ✅ |
| `Alias.ps1` | `common/modules/` | ✅ |
| `Firewall.ps1` | `common/modules/` | ✅ |
| `Create-Ascii.ps1` | `common/modules/` | ✅ |
| `Backup/Restore/Create-Database` UI flow | `common/modules/` | ✅ (commands injected via script block param) |
| `View-Logs.ps1` UI | `common/modules/` | ✅ (log source injected) |

Tool-specific (update per tool, as intended):
- Template files (Apache vs Nginx)
- Build/deploy modules (different outputs)
- Service controllers (batch scripts vs docker compose)
- Startup checks (different validation sets)

---

## Shared Module Pattern: Executor Injection

Modules like `Backup-MySQL.ps1` have the same UI flow in both tools — only the underlying command differs. Instead of maintaining two near-identical files, use an **executor script block** parameter:

```powershell
# common/modules/Backup-MySQL.ps1
param(
    [scriptblock]$DbExecutor = $null,
    [scriptblock]$DbDumper = $null
)

# Default to XAMPP local if no executor provided (backwards-compatible)
if (-not $DbExecutor) {
    $DbExecutor = { param($cmd) & mysql.exe -u root -p$rootPwd -e $cmd }
    $DbDumper   = { param($db, $out) & mysqldump.exe -u root -p$rootPwd $db | gzip > $out }
}

# ... rest of UI/flow is identical
$databases = & $DbExecutor "SHOW DATABASES;"
& $DbDumper $selectedDb $backupPath
```

The tool-specific launcher wires in the right executor:

```powershell
# docker-tools/Docker-Tools.ps1 — when invoking Backup-MySQL
$dockerExecutor = {
    param($cmd)
    docker exec $containerName mysql -u root -p"$rootPwd" -e $cmd
}
$dockerDumper = {
    param($db, $out)
    docker exec $containerName sh -c "mysqldump -u root -p'$rootPwd' $db | gzip" | Set-Content $out -AsByteStream
}

& (Join-Path $common "modules\Backup-MySQL.ps1") -DbExecutor $dockerExecutor -DbDumper $dockerDumper
```

---

## Launcher Pattern (Both Tools)

Both `Xampp-Tools.ps1` and `Docker-Tools.ps1` follow the same structure — only the header, module discovery paths, and executor defaults differ:

```powershell
# ============================================================
# CONFIGURATION
# ============================================================
$script:DevToolsRoot = Split-Path $PSScriptRoot -Parent
$script:CommonDir    = Join-Path $script:DevToolsRoot "common"
$script:SharedEnv    = Join-Path $script:DevToolsRoot ".env"
$script:SharedVhosts = Join-Path $script:DevToolsRoot "config\vhosts.json"
$script:ToolName     = "Docker Tools"      # or "XAMPP Tools"
$script:ToolRoot     = $PSScriptRoot

# ============================================================
# LOAD SHARED CORE
# ============================================================
. (Join-Path $script:CommonDir "Common.ps1")
. (Join-Path $script:CommonDir "Service-Helpers.ps1")

# ============================================================
# AUTO-DISCOVER MODULES (shared + tool-specific)
# ============================================================
$modules  = Get-ModulesFrom (Join-Path $script:CommonDir "modules")
$modules += Get-ModulesFrom (Join-Path $PSScriptRoot "bin\modules")
$modules  = $modules | Sort-Object { $_.Order }
```

Tool-specific modules in `bin/modules/` can **override** shared modules with the same `Cmd:` metadata — the discovery function prefers local over shared. Lets you shadow a shared module for one tool if needed.

---

## .env.example — Single File, All Keys

Top-level `.env.example` contains every key both tools care about:

```ini
# ============================================================
# Dev-Tools Configuration (XAMPP + Docker)
# ============================================================

# ------------------------------------------------------------
# XAMPP Paths
# ------------------------------------------------------------
XAMPP_ROOT_DIR=C:\xampp
XAMPP_DOCUMENT_ROOT=E:\www
USERNAME=
VSCODE_THEME_EXTENSION=

# ------------------------------------------------------------
# Server
# ------------------------------------------------------------
XAMPP_SERVER_NAME=
XAMPP_SERVER_IP=
XAMPP_SERVER_PORT=80
XAMPP_SSL_PORT=443

# ------------------------------------------------------------
# MySQL (shared between XAMPP local and Docker container)
# ------------------------------------------------------------
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_ROOT_PASSWORD=

# ------------------------------------------------------------
# phpMyAdmin
# ------------------------------------------------------------
PMA_AUTH_TYPE=cookie
PMA_ALLOW_NO_PASSWORD=false
PMA_BLOWFISH_SECRET=
PMA_USER=pma
PMA_PASSWORD=
PMA_MEMORY_LIMIT=512M
PMA_EXEC_TIME_LIMIT=600

# ------------------------------------------------------------
# PHP
# ------------------------------------------------------------
PHP_POST_MAX_SIZE=600M
PHP_UPLOAD_MAX_FILESIZE=600M
PHP_CURL_CAINFO=
PHP_OPENSSL_CAFILE=

# ------------------------------------------------------------
# VHosts
# ------------------------------------------------------------
VHOSTS_EXTENSION=.local
IS_IPV6=false

# ------------------------------------------------------------
# WordPress
# ------------------------------------------------------------
WP_DB_NAME=
WP_DB_USER=
WP_DB_PASSWORD=
WP_ADMIN_USER=
WP_ADMIN_PASSWORD=
WP_ADMIN_EMAIL=

# ============================================================
# Docker Settings
# ============================================================
DOCKER_COMPOSE_PROJECT=dev
DOCKER_NETWORK=dev-network
DOCKER_PHP_VERSION=8.4
DOCKER_MYSQL_VERSION=8.0
DOCKER_PMA_PORT=8080

# Adminer (optional multi-DB UI)
DOCKER_INCLUDE_ADMINER=false
DOCKER_ADMINER_PORT=8081

# PostgreSQL (optional)
DOCKER_INCLUDE_POSTGRES=false
DOCKER_POSTGRES_VERSION=16
POSTGRES_DB=
POSTGRES_USER=
POSTGRES_PASSWORD=
POSTGRES_PORT=5432

# Optional per-tool www root override (defaults to XAMPP_DOCUMENT_ROOT)
DOCKER_DOCUMENT_ROOT=
```

Both tools' xampp-tools/.env.example and docker-tools/.env.example can be removed — everything lives at the root.

---

## Migration Impact on Existing xampp-tools

To adopt this structure, xampp-tools needs these changes:

1. Move `xampp-tools/.env` → `dev-tools/.env` (root)
2. Move `xampp-tools/config/vhosts.json` → `dev-tools/config/vhosts.json` (root)
3. Extract shared helpers from `xampp-tools/bin/Common.ps1` → `dev-tools/common/Common.ps1`
4. Move `xampp-tools/bin/Service-Helpers.ps1` → `dev-tools/common/Service-Helpers.ps1`
5. Move `xampp-tools/bin/assets/signature-lg.txt` → `dev-tools/common/assets/signature-lg.txt`
6. Update `Xampp-Tools.ps1` to load from `../common/` and `../.env`, `../config/vhosts.json`
7. Identify truly shared modules (`Alias.ps1`, `Firewall.ps1`, `Create-Ascii.ps1`, `View-Logs.ps1`, DB ops) → move to `common/modules/` with executor injection parameters
8. Keep XAMPP-specific modules in `xampp-tools/bin/modules/`

This migration is tracked in the implementation doc as **Phase 0**.

---

## .gitignore (repo root)

```gitignore
# Environment
.env

# Generated
docker-tools/dist/
docker-tools/docker-compose.yml
docker-tools/data/
xampp-tools/config/optimized/dist/

# Backups
**/backups/

# Logs
**/*.log
```

---

## Container Naming Convention

All Docker containers prefixed with `DOCKER_COMPOSE_PROJECT`:

| Service | Container name |
|---------|---------------|
| nginx | `{project}-nginx` |
| php-fpm | `{project}-php` |
| mysql | `{project}-mysql` |
| phpmyadmin | `{project}-pma` |
| adminer | `{project}-adminer` |
| postgres | `{project}-postgres` |

Default project = `dev` → `dev-nginx`, `dev-mysql`, etc.

---

## Port Allocation

| Service | Default port | .env key |
|---------|-------------|----------|
| nginx HTTP | 80 | `XAMPP_SERVER_PORT` |
| nginx HTTPS | 443 | `XAMPP_SSL_PORT` |
| MySQL | 3306 | `MYSQL_PORT` |
| phpMyAdmin | 8080 | `DOCKER_PMA_PORT` |
| Adminer | 8081 | `DOCKER_ADMINER_PORT` |
| PostgreSQL | 5432 | `POSTGRES_PORT` |

---

## Path Resolution — Modules

Every module resolves shared resources relative to `$script:DevToolsRoot` set by the launcher:

```powershell
# In any module — shared resources
$devToolsRoot = $script:DevToolsRoot
$envFile      = Join-Path $devToolsRoot ".env"
$vhostsFile   = Join-Path $devToolsRoot "config\vhosts.json"
$commonDir    = Join-Path $devToolsRoot "common"

# Tool-specific resources use $script:ToolRoot
$toolRoot     = $script:ToolRoot       # xampp-tools or docker-tools
$configFile   = Join-Path $toolRoot "config\config.json"
$distDir      = Join-Path $toolRoot "config\dist"   # or dist/ for docker-tools
```

Fallback: if `$script:DevToolsRoot` isn't set (module invoked directly, not via launcher), resolve upward from `$PSScriptRoot`.

---

## Side-by-Side Reference

| Concern | xampp-tools | docker-tools |
|---------|------------|--------------|
| Entry point | `xampp-tools/Xampp-Tools.ps1` | `docker-tools/Docker-Tools.ps1` |
| Header banner | "XAMPP Tools" (via `$script:ToolName`) | "Docker Tools" (via `$script:ToolName`) |
| `.env` location | `dev-tools/.env` | `dev-tools/.env` (same file) |
| `vhosts.json` | `dev-tools/config/vhosts.json` | `dev-tools/config/vhosts.json` (same file) |
| Common helpers | `dev-tools/common/Common.ps1` | `dev-tools/common/Common.ps1` (same file) |
| Template dir | `xampp-tools/config/optimized/templates/` | `docker-tools/config/templates/` |
| Dist dir | `xampp-tools/config/optimized/dist/` | `docker-tools/config/dist/` + `docker-tools/docker-compose.yml` |
| Web server | Apache (host service) | Nginx (container) |
| PHP delivery | Installed binaries on host | `php-fpm` container |
| DB ops | `mysql.exe` on host | `docker exec {container} mysql` |
| SSL | OpenSSL → Windows cert store | mkcert → Windows cert store + nginx volume |
| Hosts file | Written by `Build-Configs.ps1` | Written by `Build-Compose.ps1` (same entries) |
