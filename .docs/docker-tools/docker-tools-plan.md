# Docker Tools — Plan

## Status: Decisions Pending

Work through each decision in order before implementation begins. Mark each with the chosen option when resolved.

---

## Decisions to Resolve

---

### Decision 1: Web Server — Nginx vs Traefik

**Context:** Virtual host routing needs a mechanism. xampp-tools generates Apache `VirtualHost` blocks per site from a template. Docker needs an equivalent.

**Option A — Nginx (recommended)**
- Generate `server {}` blocks per site from `vhost-blocks.template`
- Direct 1:1 mirror of the Apache VHost approach
- Simple bind mount: `./dist/nginx/conf.d:/etc/nginx/conf.d`
- Easy to debug, well-understood config format

**Option B — Traefik**
- Container labels drive routing — no nginx config files generated
- Auto-discovers containers, supports Let's Encrypt natively
- Compose output is more complex (labels per service per site)
- Requires Traefik container + dashboard, more moving parts for local dev

**Recommendation:** Nginx. Same template pattern as Apache. Traefik can be added as an optional mode later if needed (e.g. for multi-project environments).

**Decision: [ ] A — Nginx   [ ] B — Traefik   [ ] Other: ______**

---

### Decision 2: Shared vhosts.json vs Separate

**Context:** Both tools need to know about the same sites. Question is whether one file serves both.

**Option A — Shared (recommended)**
- docker-tools references `../xampp-tools/config/vhosts.json` in its `config.json`
- Single source of truth — add a site once, both tools pick it up
- Optional Docker-specific fields added to vhosts.json schema (ignored by xampp-tools)

**Option B — Separate**
- docker-tools has its own `config/vhosts.json`
- Sites can diverge between XAMPP and Docker environments
- Risk of drift, duplication

**Recommendation:** Shared. The sites are the same projects. Add optional Docker fields to the existing schema — they are no-ops in xampp-tools.

**Decision: [ ] A — Shared   [ ] B — Separate**

---

### Decision 3: Shared .env vs Separate

**Context:** Many settings are identical (MySQL credentials, PHP limits, site extension). Docker needs additional keys.

**Option A — Shared + Extended (recommended)**
- docker-tools loads the same `.env` as xampp-tools (at `../xampp-tools/.env` or a root `.env`)
- A `# Docker Settings` section is added to that shared `.env`
- One file to update for credentials

**Option B — Separate docker.env**
- docker-tools loads xampp-tools `.env` first, then its own `docker.env` on top (override pattern)
- Credentials stay in one place, Docker specifics are isolated

**Option C — Fully Separate**
- docker-tools has its own `.env` with all keys duplicated
- Diverges immediately, duplication risk

**Recommendation:** Option A. Add a `# Docker Settings` block to the shared `.env`. One file, full shared state. If isolation becomes necessary later, migrate to Option B.

**Decision: [ ] A — Shared+Extended   [ ] B — Two files   [ ] C — Separate**

---

### Decision 4: PHP Delivery — Single FPM vs Per-Site

**Context:** PHP-FPM is needed for Laravel and WordPress sites. React sites don't need it. Question is one shared container or per-site containers.

**Option A — Single php-fpm container (recommended)**
- All Laravel and WordPress sites route to one `php:8.4-fpm` container
- Simple compose: one service, one image
- `DOCKER_PHP_VERSION` in `.env` controls the version
- Per-site PHP version not supported without rebuild

**Option B — Per-site php-fpm containers**
- Each site gets its own `php-fpm` service in compose output
- Supports per-site `phpVersion` from vhosts.json
- Compose output grows significantly, more resource usage

**Option C — One per app-type**
- One php-fpm for all `laravel` sites, one for all `wordpress` sites
- Middle ground — supports some isolation without full per-site overhead

**Recommendation:** Option A initially. Add `phpVersion` as an optional vhosts.json field that is documented but only activates per-site containers in a future phase.

**Decision: [ ] A — Single   [ ] B — Per-site   [ ] C — Per-type**

---

### Decision 5: MySQL — Single vs Per-Site

**Context:** XAMPP uses one MySQL instance with multiple databases. Replicate or isolate per site?

**Option A — Single MySQL container (recommended)**
- Mirrors XAMPP exactly: one container, one port, all databases within it
- `docker exec mysql mysql -e "CREATE DATABASE..."` — same as current `Create-Database.ps1`
- Backups cover all databases in one operation

**Option B — Per-site MySQL containers**
- Full isolation: each site has its own MySQL container and port
- Compose grows significantly, not practical for 12+ sites

**Recommendation:** Single MySQL container. Identical to XAMPP behavior.

**Decision: [ ] A — Single   [ ] B — Per-site**

---

### Decision 6: phpMyAdmin

**Context:** xampp-tools configures phpMyAdmin as part of XAMPP. Docker needs it as a separate container.

**Option A — Always included**
- `phpmyadmin` service always in the generated compose

**Option B — Optional flag (recommended)**
- `DOCKER_INCLUDE_PMA=true` in `.env` controls whether the pma service is emitted
- Excluded from compose output when `false`

**Recommendation:** Option B. Useful by default, but shouldn't be forced on environments where it isn't needed.

**Decision: [ ] A — Always   [ ] B — Optional flag**

---

### Decision 7: SSL Handling

**Context:** xampp-tools' `Setup-SSL.ps1` generates self-signed certs via OpenSSL and imports them to the Windows trust store. Docker needs a similar approach.

**Option A — mkcert (recommended)**
- `mkcert` generates locally-trusted certs without OpenSSL flag wrestling
- Works with both XAMPP and Docker setups
- Certs volume-mounted into the nginx container
- One-time `mkcert -install` sets up the local CA

**Option B — Reuse existing OpenSSL approach**
- Same `Setup-SSL.ps1` logic, certs placed in `dist/nginx/certs/`
- Volume-mounted into nginx
- Consistent with XAMPP tooling

**Option C — Let's Encrypt via Traefik**
- Only available if Decision 1 = Traefik
- Not applicable for local development anyway

**Recommendation:** Option A — mkcert. Simpler, fewer edge cases than OpenSSL on Windows, produces browser-trusted certs. Can be installed via Scoop or manual download.

**Decision: [ ] A — mkcert   [ ] B — OpenSSL (existing)   [ ] C — Let's Encrypt**

---

### Decision 8: React Sites — Dev Server Proxy vs Static Build

**Context:** React sites currently use a `port` field in vhosts.json (e.g. 8081) and XAMPP proxies to a locally-running dev server. What does Docker do?

**Option A — Dev server proxy (recommended)**
- Nginx proxies `proxy_pass http://host.docker.internal:{port}` to the dev server running on the Windows host
- Same behavior as XAMPP — `npm run dev` runs separately, nginx routes to it
- `port` field in vhosts.json drives the proxy target

**Option B — Static build served by nginx**
- `npm run build` output mounted into nginx container
- No live reload, not useful for active development
- Better suited for staging environments

**Recommendation:** Option A. Mirror XAMPP behavior. Developer runs `npm run dev`, nginx proxies. Simple, no additional containers.

**Decision: [ ] A — Dev server proxy   [ ] B — Static build**

---

### Decision 9: Compose Generation — Template vs Programmatic

**Context:** `docker-compose.yml` is YAML, not INI/conf. Template substitution is straightforward for fixed sections but awkward for dynamic per-site service blocks.

**Option A — Hybrid (recommended)**
- Base `docker-compose.yml.template` covers fixed services: nginx, php-fpm, mysql, pma
- `Build-Compose.ps1` programmatically generates per-site nginx conf files
- No per-site Docker services needed (sites are directories, not containers)
- Compose file stays predictable and small

**Option B — Fully template-based**
- One master template, placeholders replaced with generated blocks
- Works if all sites are served by shared services (nginx + php-fpm)
- Limiting if per-site containers are ever needed

**Option C — Fully programmatic**
- PowerShell builds YAML in-memory, no template files
- Maximum flexibility, least readable

**Recommendation:** Option A — hybrid. The compose file has a stable set of services (nginx, php-fpm, mysql, pma). Site routing is handled via nginx conf files, not compose services. Template covers the stable part; PowerShell generates nginx confs per site.

**Decision: [ ] A — Hybrid   [ ] B — Fully template   [ ] C — Programmatic**

---

### Decision 10: Volume Strategy for www Files

**Context:** Sites live in `XAMPP_DOCUMENT_ROOT` (e.g. `E:\www\`). Nginx needs to serve files from there.

**Option A — Single root volume (recommended)**
- Mount entire `XAMPP_DOCUMENT_ROOT` into nginx: `E:\www:/var/www/html`
- All sites available, nginx conf uses `/var/www/html/{folder}` as document root

**Option B — Per-site volumes**
- Each site folder mounted separately in compose
- Compose grows, but provides isolation

**Recommendation:** Option A. Single mount of `XAMPP_DOCUMENT_ROOT`. Same `folder` field from vhosts.json maps to `/var/www/html/{folder}`. Identical mental model to XAMPP.

**Decision: [ ] A — Single root   [ ] B — Per-site**

---

## Module Breakdown

### `Build-Compose.ps1` — Core Engine

The equivalent of xampp-tools' `Build-Configs.ps1` + `Deploy-VHosts.ps1` combined.

**Steps:**
1. Load `.env` and `config.json`
2. Load `vhosts.json`, validate all site folders exist in `XAMPP_DOCUMENT_ROOT`
3. Detect duplicate domains
4. Compile base templates → `dist/` (nginx.conf, php.ini, my.cnf)
5. For each vhost: select correct block template by `type`, substitute variables, write to `dist/nginx/conf.d/{folder}.conf`
6. Compile `docker-compose.yml.template` → `dist/docker-compose.yml`
7. Output build summary

**Template variable substitution:** Same `{{PLACEHOLDER}}` system. All `.env` keys available as uppercase placeholders.

**Per-type nginx block templates** (in `nginx/vhost-blocks.template`):

```
[laravel]    document root = /var/www/html/{folder}/public
             fastcgi_pass php-fpm:9000
[wordpress]  document root = /var/www/html/{folder}
             fastcgi_pass php-fpm:9000
[static]     document root = /var/www/html/{folder}
             try_files $uri $uri/ =404
[react]      proxy_pass http://host.docker.internal:{port}
[default]    catch-all, document root = /var/www/html
```

---

### `Docker-Controller.ps1`

```
1) Start All         → docker compose -f {compose_file} up -d
2) Stop All          → docker compose down
3) Restart All       → docker compose restart
4) Status            → docker compose ps (with health indicators)
5) Open Shell        → docker exec -it {service} sh
0) Back
```

Exported helper functions (dot-sourceable by other modules):
```powershell
Invoke-DockerStart    # docker compose up -d
Invoke-DockerStop     # docker compose down
Invoke-DockerRestart  # docker compose restart
Get-DockerStatus      # returns hashtable per service: { Running: bool, Health: string }
Get-ComposePath       # returns resolved path to dist/docker-compose.yml
```

---

### `Startup-Check.ps1`

Pre-flight checks before any operation:

| Check | Method |
|-------|--------|
| Docker daemon running | `docker info` exit code |
| `.env` file exists | `Test-Path` |
| Required `.env` keys present | Validate key list |
| `vhosts.json` parseable | `ConvertFrom-Json` |
| `docker compose config` valid | `docker compose -f {file} config` |
| Ports 80, 443, 3306 available | `Test-NetConnection` |
| `XAMPP_DOCUMENT_ROOT` exists | `Test-Path` |

---

### `Backup-MySQL.ps1`

```powershell
docker exec {MYSQL_CONTAINER} mysqldump -u root -p{password} {database} | gzip > backup.sql.gz
```

Same interactive flow as xampp-tools: list databases, select one or all, confirm, run.

---

### `Restore-MySQL.ps1`

```powershell
docker exec -i {MYSQL_CONTAINER} mysql -u root -p{password} {database} < backup.sql
```

---

### `Create-Database.ps1`

```powershell
docker exec {MYSQL_CONTAINER} mysql -u root -p{password} -e "CREATE DATABASE \`{name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
```

---

### `Redeploy.ps1`

Five-step pipeline mirroring xampp-tools:

```
Step 1: Backup-Configs      (snapshot dist/)
Step 2: Build-Compose       (compile templates → dist/)
Step 3: docker compose down (stop running containers)
Step 4: docker compose up -d --force-recreate
Step 5: Startup-Check       (verify health)
```

---

### `View-Logs.ps1`

```
1) All services       → docker compose logs -f
2) nginx              → docker compose logs -f nginx
3) php-fpm            → docker compose logs -f php-fpm
4) mysql              → docker compose logs -f mysql
5) phpmyadmin         → docker compose logs -f phpmyadmin
```

---

## Template Design

### `docker-compose.yml.template`

```yaml
name: {{DOCKER_COMPOSE_PROJECT}}

services:

  nginx:
    image: nginx:alpine
    ports:
      - "{{XAMPP_SERVER_PORT}}:80"
      - "{{XAMPP_SSL_PORT}}:443"
    volumes:
      - {{XAMPP_DOCUMENT_ROOT}}:/var/www/html
      - ./dist/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./dist/nginx/conf.d:/etc/nginx/conf.d:ro
    networks:
      - {{DOCKER_NETWORK}}
    depends_on:
      - php-fpm

  php-fpm:
    image: php:{{DOCKER_PHP_VERSION}}-fpm
    volumes:
      - {{XAMPP_DOCUMENT_ROOT}}:/var/www/html
      - ./dist/php/php.ini:/usr/local/etc/php/php.ini:ro
    networks:
      - {{DOCKER_NETWORK}}

  mysql:
    image: mysql:{{DOCKER_MYSQL_VERSION}}
    ports:
      - "{{MYSQL_PORT}}:3306"
    environment:
      MYSQL_ROOT_PASSWORD: {{MYSQL_ROOT_PASSWORD}}
    volumes:
      - mysql-data:/var/lib/mysql
      - ./dist/mysql/my.cnf:/etc/mysql/conf.d/custom.cnf:ro
    networks:
      - {{DOCKER_NETWORK}}

  # PMA block injected conditionally by Build-Compose when DOCKER_INCLUDE_PMA=true

networks:
  {{DOCKER_NETWORK}}:
    driver: bridge

volumes:
  mysql-data:
```

### `nginx/vhost-blocks.template`

One named block per site type, same bracket syntax as Apache version:

```nginx
[laravel]
server {
    listen 80;
    server_name {{SERVER_NAME}};
    root /var/www/html/{{FOLDER}}/public;
    index index.php index.html;
    location / { try_files $uri $uri/ /index.php?$query_string; }
    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }
    access_log /var/log/nginx/{{FOLDER}}-access.log;
    error_log  /var/log/nginx/{{FOLDER}}-error.log;
}
[/laravel]

[react]
server {
    listen 80;
    server_name {{SERVER_NAME}};
    location / {
        proxy_pass http://host.docker.internal:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}
[/react]

[wordpress]
server {
    listen 80;
    server_name {{SERVER_NAME}};
    root /var/www/html/{{FOLDER}};
    index index.php index.html;
    location / { try_files $uri $uri/ /index.php?$query_string; }
    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }
    access_log /var/log/nginx/{{FOLDER}}-access.log;
    error_log  /var/log/nginx/{{FOLDER}}-error.log;
}
[/wordpress]

[static]
server {
    listen 80;
    server_name {{SERVER_NAME}};
    root /var/www/html/{{FOLDER}};
    index index.html index.php;
    location / { try_files $uri $uri/ =404; }
    access_log /var/log/nginx/{{FOLDER}}-access.log;
    error_log  /var/log/nginx/{{FOLDER}}-error.log;
}
[/static]

[default]
server {
    listen 80 default_server;
    server_name _;
    root /var/www/html;
    index index.php index.html;
    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
[/default]
```

---

## config.json Structure

```json
{
  "description": "Docker Tools configuration",

  "templates": {
    "sourceDir": "config\\templates",
    "distDir": "config\\dist",
    "files": [
      { "template": "nginx\\nginx.conf.template", "output": "nginx\\nginx.conf" },
      { "template": "php\\php.ini.template",       "output": "php\\php.ini" },
      { "template": "mysql\\my.cnf.template",      "output": "mysql\\my.cnf" }
    ]
  },

  "vhosts": {
    "description": "Shared with xampp-tools",
    "blocksTemplate": "nginx\\vhost-blocks.template",
    "outputDir": "nginx\\conf.d",
    "sitesFile": "..\\xampp-tools\\config\\vhosts.json"
  },

  "compose": {
    "baseTemplate": "docker\\docker-compose.yml.template",
    "output": "docker-compose.yml"
  },

  "backups": {
    "files": [
      { "source": "config\\dist\\docker-compose.yml", "target": "docker-compose.yml" },
      { "source": "config\\dist\\nginx\\conf.d",      "target": "nginx\\conf.d" },
      { "source": "config\\dist\\php\\php.ini",       "target": "php\\php.ini" },
      { "source": "config\\dist\\mysql\\my.cnf",      "target": "mysql\\my.cnf" }
    ]
  }
}
```

---

## .env Additions

Full list of Docker-specific keys to add to the shared `.env`:

```ini
# ============================================================
# Docker Settings
# ============================================================

# Project name (used as docker compose --project-name)
DOCKER_COMPOSE_PROJECT=dev

# Internal Docker network name
DOCKER_NETWORK=dev-network

# PHP version for the php-fpm container image tag
DOCKER_PHP_VERSION=8.4

# MySQL container image version
DOCKER_MYSQL_VERSION=8.0

# Include phpMyAdmin container (true/false)
DOCKER_INCLUDE_PMA=true

# Local directory for Docker persistent data (MySQL volume bind path if not using named volumes)
DOCKER_DATA_DIR=.docker/data
```

---

## vhosts.json Schema Changes

All new fields are **optional**. Existing required fields (`name`, `folder`, `type`) are unchanged.

```json
{
  "name": "Api Idiliq",
  "folder": "api.idiliq.dev",
  "type": "laravel",
  "ssl": false,
  "port": 80,

  "_docker": {
    "phpVersion": "8.1",
    "extraEnv": {
      "APP_ENV": "local"
    },
    "extraVolumes": []
  }
}
```

Using a `_docker` sub-object keeps the schema clean — xampp-tools ignores unknown keys.

---

## Implementation Phases

### Phase 1 — Foundation (start here)
Get to a working `docker compose up` state.

| File | Notes |
|------|-------|
| `bin/Common.ps1` | Clone from xampp-tools, update header text, add `Get-ComposePath` helper |
| `config/templates/docker/docker-compose.yml.template` | Base compose template (see above) |
| `config/templates/nginx/vhost-blocks.template` | Per-type server{} blocks (see above) |
| `config/templates/nginx/nginx.conf.template` | Main nginx config |
| `config/templates/php/php.ini.template` | Copy from xampp-tools templates, remove XAMPP paths |
| `config/templates/mysql/my.cnf.template` | Adapt from xampp-tools `my.ini.template` |
| `config/config.json` | Template/vhost/compose mappings |
| `.env.example` | Shared keys + Docker section |
| `bin/modules/Build-Compose.ps1` | Core engine: template compilation + nginx conf generation + compose output |
| `bin/modules/Docker-Controller.ps1` | Start/Stop/Restart/Status UI |
| `bin/modules/Startup-Check.ps1` | Pre-flight validation |

### Phase 2 — Database Operations
| File | Notes |
|------|-------|
| `bin/modules/Backup-MySQL.ps1` | `docker exec mysqldump` |
| `bin/modules/Restore-MySQL.ps1` | `docker exec mysql <` |
| `bin/modules/Create-Database.ps1` | `docker exec mysql -e "CREATE DATABASE"` |
| `bin/modules/Cleanup-MySQL.ps1` | Volume pruning |

### Phase 3 — Operations
| File | Notes |
|------|-------|
| `bin/modules/Redeploy.ps1` | Full pipeline |
| `bin/modules/Services.ps1` | Thin wrapper |
| `bin/modules/Kill-Services.ps1` | Force-kill containers |
| `bin/modules/View-Logs.ps1` | `docker compose logs -f` |
| `bin/modules/Backup-Configs.ps1` | Snapshot dist/ |

### Phase 4 — Extended
| File | Notes |
|------|-------|
| `bin/modules/Setup-SSL.ps1` | mkcert integration |
| `bin/modules/Switch-PHP.ps1` | Update DOCKER_PHP_VERSION + rebuild |
| `bin/modules/Firewall.ps1` | Port rules for Docker ports |
| `bin/modules/Alias.ps1` | Shell aliases |

---

## Open Questions

1. **Entry point script** — Does docker-tools need a top-level `Docker-Tools.ps1` launcher (equivalent to the xampp-tools launcher that shows the module menu), or will modules be called directly?

2. **Compose file location** — Should the final `docker-compose.yml` live in `config/dist/` (generated, gitignored) or at the docker-tools root (for easy `docker compose up` from the terminal)?

3. **php-fpm image extensions** — The base `php:8.4-fpm` image is minimal. Which extensions need to be pre-installed (pdo_mysql, mbstring, gd, curl, etc.)? Use a custom `Dockerfile` or the `install-php-extensions` helper image?

4. **Windows host.docker.internal** — Confirmed available on Docker Desktop for Windows. Does your Docker setup (WSL2 backend?) require any specific configuration for this to work for React proxy?

5. **Port conflicts** — If XAMPP is running on 80/443 when docker-tools starts, `Startup-Check.ps1` should detect and warn. Should it also offer to stop XAMPP services automatically?

6. **Hosts file** — xampp-tools writes `127.0.0.1 site.local` entries to the Windows hosts file. Docker sites are also on `127.0.0.1` (Docker Desktop port binding). Same hosts file entries should work. Should `Build-Compose.ps1` also update the hosts file, or rely on xampp-tools' existing hosts entries?

7. **MySQL container name** — Need a stable container name for `docker exec` commands. Controlled by `container_name:` in compose. Should this be a fixed constant (`dev-mysql`) or derived from `DOCKER_COMPOSE_PROJECT`?
