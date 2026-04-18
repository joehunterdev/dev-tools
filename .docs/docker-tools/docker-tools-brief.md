# Docker Tools — Brief

## Overview

docker-tools is a PowerShell automation suite for managing Docker-based local development environments. It is a direct sibling to xampp-tools and shares the same configuration architecture: a single `.env` file, `vhosts.json` for declarative multi-site definitions, and a modular `bin/modules/` structure with identical CLI patterns.

The system's primary output is a generated `docker-compose.yml` and per-site Nginx configs compiled from templates using `.env` variable substitution — the same template-to-dist pipeline xampp-tools uses to generate `httpd.conf`, `php.ini`, and `my.ini`.

---

## Goals

- Mirror xampp-tools' module set, metadata pattern, and interactive CLI style exactly
- Reuse `.env` keys wherever possible; add Docker-specific keys in a dedicated section
- Share `vhosts.json` as the single source of truth for multi-site definitions
- Generate `docker-compose.yml` dynamically from templates (same as `Build-Configs` generates Apache configs)
- Support the same site types: `laravel`, `react`, `wordpress`, `static`, `default`

---

## What It Is Not

- Not a replacement for xampp-tools — they coexist as alternatives
- Not a general-purpose Docker management tool — scoped to this dev environment
- Not a cloud deployment tool — local development only

---

## Architecture

Identical pattern to xampp-tools:

```
docker-tools/
├── .env.example                   # shared base + Docker-specific additions
├── bin/
│   ├── Common.ps1                 # shared helpers: logging, env loading, prompts, header
│   └── modules/
│       └── *.ps1                  # one module per feature, same metadata header format
├── config/
│   ├── config.json                # template → dist mappings + compose config
│   ├── vhosts.json                # shared with xampp-tools (same schema + optional Docker fields)
│   └── templates/
│       ├── docker/                # docker-compose base template
│       ├── nginx/                 # nginx.conf + per-type server{} block templates
│       ├── php/                   # php.ini template (reused from xampp-tools)
│       └── mysql/                 # my.cnf template (adapted from my.ini.template)
└── config/dist/                   # generated output (gitignored)
    ├── docker-compose.yml
    ├── nginx/conf.d/              # one .conf per vhost site
    ├── php/php.ini
    └── mysql/my.cnf
```

---

## Module List

| Module | Cmd | Description |
|--------|-----|-------------|
| `Build-Compose.ps1` | `build` | Core: compile all templates → dist, generate docker-compose.yml + nginx configs |
| `Docker-Controller.ps1` | `docker` | Start / Stop / Restart / Status for all containers |
| `Services.ps1` | `services` | Thin wrapper around Docker-Controller actions |
| `Redeploy.ps1` | `redeploy` | Full pipeline: backup → build → docker compose up --force-recreate |
| `Startup-Check.ps1` | `check` | Validate Docker daemon, .env, ports, compose config |
| `Backup-MySQL.ps1` | `backup-db` | Dump databases via `docker exec mysqldump` → `.sql.gz` |
| `Restore-MySQL.ps1` | `restore-db` | Restore from `.sql.gz` via `docker exec -i mysql` |
| `Create-Database.ps1` | `create-db` | Create new database + optional user inside MySQL container |
| `Cleanup-MySQL.ps1` | `cleanup-db` | Remove orphaned Docker volumes for MySQL data |
| `Backup-Configs.ps1` | `backup-cfg` | Snapshot the current `dist/` folder contents |
| `Kill-Services.ps1` | `kill` | `docker compose kill` + force-remove containers |
| `View-Logs.ps1` | `logs` | `docker compose logs -f` with per-service selection |
| `Setup-SSL.ps1` | `ssl` | Generate local trusted certs, import to Windows trust store |
| `Switch-PHP.ps1` | `php` | Update `DOCKER_PHP_VERSION` in `.env`, trigger image rebuild |
| `Firewall.ps1` | `firewall` | Windows Firewall rules blocking external access to Docker ports |
| `Alias.ps1` | `alias` | Create shell aliases for docker-tools commands |

---

## Shared Configuration

### .env (shared keys)

The following `.env` keys are identical between xampp-tools and docker-tools:

```ini
MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_ROOT_PASSWORD
PHP_POST_MAX_SIZE, PHP_UPLOAD_MAX_FILESIZE
PMA_*, WP_*
VHOSTS_EXTENSION, IS_IPV6
XAMPP_DOCUMENT_ROOT    # used as the host-side volume mount path for www files
```

New Docker-specific section added to the shared `.env`:

```ini
# Docker Settings
DOCKER_COMPOSE_PROJECT=dev
DOCKER_NETWORK=dev-network
DOCKER_PHP_VERSION=8.4
DOCKER_MYSQL_VERSION=8.0
DOCKER_INCLUDE_PMA=true
DOCKER_DATA_DIR=.docker/data
```

### vhosts.json (shared schema)

Same file, same required fields. Optional Docker-specific fields added (ignored by xampp-tools):

```json
{
  "name": "Api Idiliq",
  "folder": "api.idiliq.dev",
  "type": "laravel",
  "ssl": false,
  "phpVersion": "8.1",       // optional: per-site PHP override
  "extraEnv": {},             // optional: env vars passed to site container
  "extraVolumes": []          // optional: additional volume mounts
}
```

---

## Service Stack

| Service | Image | Role |
|---------|-------|------|
| `nginx` | `nginx:alpine` | Web server, reverse proxy, virtual host routing |
| `php-fpm` | `php:{version}-fpm` | PHP processing for Laravel, WordPress, Static |
| `mysql` | `mysql:{version}` | Single database server for all sites |
| `phpmyadmin` | `phpmyadmin:latest` | Optional database UI (controlled by `DOCKER_INCLUDE_PMA`) |

React sites proxy to a separately running dev server (same `port` field from `vhosts.json`) — no additional container needed.

---

## Core Pipeline: Build-Compose

The equivalent of xampp-tools' `Redeploy` pipeline:

```
1. Backup-Configs     → snapshot dist/ folder
2. Build-Compose      → compile templates → dist/
                        generate docker-compose.yml
                        generate nginx conf.d/*.conf per site
3. docker compose up -d --force-recreate
4. Startup-Check      → verify all containers healthy
```

---

## Relation to xampp-tools

```
dev-tools/
├── xampp-tools/       ← Apache + MySQL on Windows host
│   ├── .env           ← shared config file (docker-tools reads this too)
│   ├── config/vhosts.json
│   └── ...
└── docker-tools/      ← same sites, same .env, running in Docker
    ├── bin/modules/
    ├── config/templates/
    └── config/dist/   ← generated docker-compose.yml + nginx configs
```

Both tools read the same `.env` and `vhosts.json`. Running docker-tools does not require xampp-tools to be stopped (different ports can be configured), but they should not both bind port 80 simultaneously.
