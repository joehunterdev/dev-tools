# Docker Tools — Proposed Architecture

## Repo Strategy: Separate Git Repo

docker-tools is its own git repository, bootstrapped by copying the xampp-tools structure then adapting for Docker. It is self-contained — no cross-repo file references, no relative paths to xampp-tools.

**Why separate repo:**
- `git clone docker-tools` → works immediately, no other repos required
- Own `.env` and `vhosts.json` — Docker environments can diverge from XAMPP without conflict
- Clean git history per tool
- No submodule complexity

**Trade-off:** `vhosts.json` and `.env` are duplicated. Sync is manual (one copy command when sites change). This is acceptable — Docker and XAMPP may legitimately run different site sets.

---

## Filesystem Layout

```
C:\                                     (or wherever you clone)
├── dev-tools\                          ← existing monorepo (xampp-tools lives here)
│   ├── dev-tools.code-workspace        ← add docker-tools folder entry here
│   ├── xampp-tools\
│   └── .docs\
└── docker-tools\                       ← separate git repo (new)
    └── ...
```

The VS Code workspace at `dev-tools.code-workspace` gets a new entry pointing to wherever `docker-tools` is cloned. Both tools visible in one workspace, separate git histories.

---

## docker-tools Directory Structure

```
docker-tools\
│
│  ── Entry points ──────────────────────────────────────────
├── Docker-Tools.ps1                    # interactive menu launcher (copy of Xampp-Tools.ps1, renamed)
├── docker-compose.yml                  # GENERATED — gitignored, produced by Build-Compose.ps1
├── Dockerfile                          # php-fpm custom image — committed to git
├── .env                                # gitignored — copy from .env.example and fill in
├── .env.example                        # committed — ALL keys: shared + docker-specific
├── .gitignore
│
│  ── Shell ─────────────────────────────────────────────────
├── bin\
│   ├── Common.ps1                      # copy from xampp-tools + Docker helpers added at bottom
│   ├── Create-Ascii.ps1                # copy unchanged
│   ├── signature-lg.txt                # copy or replace with docker-tools banner
│   └── modules\
│       │
│       │  Phase 1 — Foundation
│       ├── Docker-Controller.ps1       # new
│       ├── Build-Compose.ps1           # new (core engine)
│       ├── Startup-Check.ps1           # new (Docker-specific checks)
│       │
│       │  Phase 2 — Database
│       ├── Backup-MySQL.ps1            # adapted (docker exec mysqldump)
│       ├── Restore-MySQL.ps1           # adapted (docker exec mysql <)
│       ├── Create-Database.ps1         # adapted (docker exec mysql -e)
│       ├── Cleanup-MySQL.ps1           # adapted (volume pruning)
│       │
│       │  Phase 3 — Operations
│       ├── Redeploy.ps1                # adapted (Docker pipeline)
│       ├── Services.ps1                # adapted (docker compose wrapper)
│       ├── Kill-Services.ps1           # adapted (docker compose kill)
│       ├── View-Logs.ps1               # adapted (docker compose logs -f)
│       ├── Backup-Configs.ps1          # adapted (snapshot dist/)
│       │
│       │  Phase 4 — Extended
│       ├── Setup-SSL.ps1               # adapted (mkcert instead of OpenSSL)
│       ├── Switch-PHP.ps1              # adapted (rebuild image instead of install zip)
│       ├── Firewall.ps1                # copy + update port list
│       ├── Alias.ps1                   # copy + update paths
│       └── Install-Docker.ps1          # new
│
│  ── Config source (committed) ──────────────────────────────
├── config\
│   ├── config.json                     # template→dist mappings, vhosts ref, compose config
│   ├── vhosts.json                     # OWN COPY — starts identical to xampp-tools, can diverge
│   └── templates\
│       ├── docker\
│       │   └── docker-compose.yml.template
│       ├── nginx\
│       │   ├── nginx.conf.template
│       │   └── vhost-blocks.template   # laravel, react, wordpress, static, default blocks
│       ├── php\
│       │   └── php.ini.template        # adapted from xampp-tools (no Windows paths)
│       └── mysql\
│           └── my.cnf.template         # adapted from xampp-tools my.ini.template
│
│  ── Generated output (gitignored) ──────────────────────────
├── dist\
│   ├── nginx\
│   │   ├── nginx.conf
│   │   └── conf.d\                     # one .conf per vhost
│   │       ├── api.idiliq.dev.conf
│   │       └── ...
│   ├── php\
│   │   └── php.ini
│   ├── mysql\
│   │   └── my.cnf
│   └── certs\                          # mkcert SSL output
│       ├── site.pem
│       └── site-key.pem
│
│  ── Persistent data (gitignored) ───────────────────────────
└── data\
    ├── mysql\                          # MySQL volume bind mount
    └── postgres\                       # PostgreSQL volume bind mount (if enabled)
```

---

## What Is Copied vs New vs Adapted

| File | Action | Notes |
|------|--------|-------|
| `Xampp-Tools.ps1` | Copy → rename | Update title text only |
| `bin/Common.ps1` | Copy → extend | Add Docker helpers at bottom, update header |
| `bin/Create-Ascii.ps1` | Copy | Unchanged |
| `bin/signature-lg.txt` | Copy or new | Can reuse or create docker-tools banner |
| `config/vhosts.json` | Copy | Starts identical, diverges independently |
| `.env.example` | Copy → extend | Add full Docker section |
| `Alias.ps1` | Copy → minor | Update internal paths only |
| `Firewall.ps1` | Copy → minor | Update port list for Docker services |
| `View-Logs.ps1` | Adapt | Replace log tail with `docker compose logs -f` |
| `Backup-MySQL.ps1` | Adapt | Replace `mysql.exe` calls with `docker exec` |
| `Restore-MySQL.ps1` | Adapt | Replace `mysql.exe` calls with `docker exec` |
| `Create-Database.ps1` | Adapt | Replace `mysql.exe` calls with `docker exec` |
| `Cleanup-MySQL.ps1` | Adapt | Replace dir cleanup with volume pruning |
| `Redeploy.ps1` | Adapt | Same 5-step structure, Docker pipeline steps |
| `Services.ps1` | Adapt | `docker compose up/down/restart` |
| `Kill-Services.ps1` | Adapt | `docker compose kill` + `docker rm` |
| `Backup-Configs.ps1` | Adapt | Snapshot `dist/` instead of XAMPP paths |
| `Setup-SSL.ps1` | Adapt | mkcert instead of OpenSSL |
| `Switch-PHP.ps1` | Adapt | Rebuild Docker image instead of install zip |
| `Build-Compose.ps1` | **New** | No xampp-tools equivalent |
| `Docker-Controller.ps1` | **New** | Replaces both Xampp-Controller + Services |
| `Startup-Check.ps1` | **New** | Completely different checks |
| `Install-Docker.ps1` | **New** | No xampp-tools equivalent |

---

## docker-compose.yml Location

Generated at the **docker-tools root** — not in `dist/`. This is the single exception to "all generated files go in dist/" and it exists for one reason: `docker compose up` works from the repo root without flags.

The compose file references `./dist/nginx/...` etc. since both `docker-compose.yml` and `dist/` sit at the same level.

---

## .env.example — Full Key List

Single file with all keys — no cross-repo loading:

```ini
# ============================================================
# Docker Tools Configuration
# ============================================================
# Copy to .env and fill in values. Never commit .env.

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
XAMPP_DOCUMENT_ROOT=E:\www
USERNAME=

# ------------------------------------------------------------
# Server
# ------------------------------------------------------------
XAMPP_SERVER_PORT=80
XAMPP_SSL_PORT=443

# ------------------------------------------------------------
# MySQL
# ------------------------------------------------------------
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_ROOT_PASSWORD=

# ------------------------------------------------------------
# PHP Settings
# ------------------------------------------------------------
PHP_POST_MAX_SIZE=600M
PHP_UPLOAD_MAX_FILESIZE=600M

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

# Project name prefix — used for container names and compose project
DOCKER_COMPOSE_PROJECT=dev

# Internal Docker network name
DOCKER_NETWORK=dev-network

# PHP version for the php-fpm image tag
DOCKER_PHP_VERSION=8.4

# MySQL image version
DOCKER_MYSQL_VERSION=8.0

# phpMyAdmin port (always included)
DOCKER_PMA_PORT=8080

# Adminer — lightweight multi-DB UI (useful for PostgreSQL)
DOCKER_INCLUDE_ADMINER=false
DOCKER_ADMINER_PORT=8081

# PostgreSQL (optional)
DOCKER_INCLUDE_POSTGRES=false
DOCKER_POSTGRES_VERSION=16
POSTGRES_DB=
POSTGRES_USER=
POSTGRES_PASSWORD=
POSTGRES_PORT=5432

# Optional: override www root for Docker only
# Defaults to XAMPP_DOCUMENT_ROOT if left blank
DOCKER_DOCUMENT_ROOT=
```

---

## config.json — Updated (No Cross-Repo Refs)

```json
{
  "description": "Docker Tools configuration",

  "templates": {
    "sourceDir": "config\\templates",
    "distDir":   "dist",
    "files": [
      { "template": "nginx\\nginx.conf.template", "output": "nginx\\nginx.conf" },
      { "template": "php\\php.ini.template",       "output": "php\\php.ini" },
      { "template": "mysql\\my.cnf.template",      "output": "mysql\\my.cnf" }
    ]
  },

  "vhosts": {
    "blocksTemplate": "config\\templates\\nginx\\vhost-blocks.template",
    "outputDir":      "dist\\nginx\\conf.d",
    "sitesFile":      "config\\vhosts.json"
  },

  "compose": {
    "baseTemplate": "config\\templates\\docker\\docker-compose.yml.template",
    "output":       "docker-compose.yml"
  },

  "ssl": {
    "certsDir": "dist\\certs"
  },

  "backups": {
    "sourceDir": "dist",
    "targetDir": "backups"
  }
}
```

---

## Path Resolution in Modules

Since docker-tools is self-contained, all paths resolve locally:

```powershell
# In every module — standard path setup (same pattern as xampp-tools)
$moduleRoot  = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$envFile     = Join-Path $moduleRoot ".env"
$vhostsFile  = Join-Path $moduleRoot "config\vhosts.json"
$configFile  = Join-Path $moduleRoot "config\config.json"
$composeFile = Join-Path $moduleRoot "docker-compose.yml"
$distDir     = Join-Path $moduleRoot "dist"

. (Join-Path $moduleRoot "bin\Common.ps1")
$envVars = Load-EnvFile $envFile
```

No `../` references anywhere.

---

## Container Naming Convention

All containers prefixed with `DOCKER_COMPOSE_PROJECT`:

| Service | Container name |
|---------|---------------|
| nginx | `{project}-nginx` |
| php-fpm | `{project}-php` |
| mysql | `{project}-mysql` |
| phpmyadmin | `{project}-pma` |
| adminer | `{project}-adminer` |
| postgres | `{project}-postgres` |

Default: `dev-nginx`, `dev-mysql`, etc.

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

## VS Code Workspace Entry

Add to `dev-tools\dev-tools.code-workspace` (path adjusted to wherever docker-tools is cloned):

```json
{
    "name": "🐳 Docker Tools",
    "path": "C:/docker-tools"
},
{
    "name": "🐳 Docker Dist",
    "path": "C:/docker-tools/dist"
}
```

---

## Syncing vhosts.json Between Repos

When sites change in xampp-tools, sync to docker-tools manually:

```powershell
Copy-Item "C:\dev-tools\xampp-tools\config\vhosts.json" "C:\docker-tools\config\vhosts.json"
```

Or add a one-liner `Sync-Vhosts.ps1` utility if this becomes frequent. Docker-specific `_docker` fields in the docker-tools copy are preserved since they won't exist in the xampp-tools source (the key is unique to docker-tools).

---

## Side-by-Side Comparison

| Concern | xampp-tools | docker-tools |
|---------|------------|--------------|
| Entry point | `Xampp-Tools.ps1` | `Docker-Tools.ps1` |
| Config source | `.env` + `config/vhosts.json` | Own `.env` + own `config/vhosts.json` |
| Template output | `config/optimized/dist/` | `dist/` |
| Web server config | Apache `httpd-vhosts.conf` | Nginx `dist/nginx/conf.d/*.conf` |
| Service control | XAMPP batch scripts | `docker compose` CLI |
| PHP config | Deployed to `C:\xampp\php\` | Volume-mounted from `dist/php/` |
| MySQL config | Deployed to `C:\xampp\mysql\` | Volume-mounted from `dist/mysql/` |
| DB operations | `mysql.exe` on Windows host | `docker exec {container} mysql` |
| SSL | OpenSSL → Windows cert store | mkcert → Windows cert store + nginx volume |
| Hosts file | Written by `Build-Configs.ps1` | Written by `Build-Compose.ps1` |
| Repo | `dev-tools` monorepo | Separate `docker-tools` repo |
