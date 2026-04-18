# Docker Tools — Implementation Plan

## Status: Ready to Build

All decisions resolved. This document is the build guide — work through phases in order. Each section specifies exact file paths, functions, logic, and dependencies.

---

## Pre-Implementation Checklist

Before writing any code:
- [ ] `proposed-architecture.md` reviewed and directory structure agreed
- [ ] `docker-tools/` directory created in dev-tools monorepo
- [ ] Docker section appended to `../xampp-tools/.env.example` and local `.env`
- [ ] `docker-tools/.gitignore` created
- [ ] VS Code workspace updated with docker-tools folders

---

## Phase 1 — Foundation

Goal: `docker compose up` produces running nginx + php-fpm + mysql + pma containers serving all vhost sites.

---

### File: `.gitignore`

```gitignore
# Generated
docker-compose.yml
dist/

# Data volumes
data/

# Environment
.env

# Backups
backups/
```

---

### File: `Dockerfile`

Minimal php-fpm image. Committed to git (not generated).

```dockerfile
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm

RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libzip-dev \
    libgd-dev \
    libonig-dev \
    libexif-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install \
    pdo_mysql \
    mysqli \
    mbstring \
    gd \
    zip \
    exif \
    curl \
    intl

EXPOSE 9000
```

Build command (used by `Switch-PHP.ps1`):
```
docker build --build-arg PHP_VERSION={version} -t dev-php:{version} .
```

---

### File: `bin/Common.ps1`

Clone from `../xampp-tools/bin/Common.ps1`. Changes:

1. Update `Show-Header` — change title text from "XAMPP Tools" to "Docker Tools"
2. Add Docker-specific helpers at the bottom:

```powershell
# ============================================================
# Docker Helpers
# ============================================================

function Get-DockerToolsRoot {
    return Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

function Get-SharedEnvPath {
    $root = Get-DockerToolsRoot
    return Join-Path (Split-Path $root -Parent) "xampp-tools\.env"
}

function Get-SharedVhostsPath {
    $root = Get-DockerToolsRoot
    return Join-Path (Split-Path $root -Parent) "xampp-tools\config\vhosts.json"
}

function Get-ComposePath {
    return Join-Path (Get-DockerToolsRoot) "docker-compose.yml"
}

function Get-DistDir {
    return Join-Path (Get-DockerToolsRoot) "dist"
}

function Get-ContainerName {
    param([string]$Service, [hashtable]$EnvVars)
    $project = if ($EnvVars['DOCKER_COMPOSE_PROJECT']) { $EnvVars['DOCKER_COMPOSE_PROJECT'] } else { "dev" }
    return "$project-$Service"
}

function Test-DockerRunning {
    $result = docker info 2>&1
    return $LASTEXITCODE -eq 0
}

function Get-DockerStatus {
    param([string]$ComposePath)
    $output = docker compose -f $ComposePath ps --format json 2>&1
    if ($LASTEXITCODE -ne 0) { return @{} }
    try {
        return $output | ConvertFrom-Json
    } catch {
        return @{}
    }
}
```

---

### File: `config/config.json`

```json
{
  "description": "Docker Tools configuration",

  "shared": {
    "envFile": "..\\xampp-tools\\.env",
    "vhostsFile": "..\\xampp-tools\\config\\vhosts.json"
  },

  "templates": {
    "sourceDir": "config\\templates",
    "distDir": "dist",
    "files": [
      { "template": "nginx\\nginx.conf.template",  "output": "nginx\\nginx.conf" },
      { "template": "php\\php.ini.template",        "output": "php\\php.ini" },
      { "template": "mysql\\my.cnf.template",       "output": "mysql\\my.cnf" }
    ]
  },

  "vhosts": {
    "blocksTemplate": "config\\templates\\nginx\\vhost-blocks.template",
    "outputDir":      "dist\\nginx\\conf.d"
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

### File: `config/templates/docker/docker-compose.yml.template`

```yaml
name: {{DOCKER_COMPOSE_PROJECT}}

services:

  nginx:
    image: nginx:alpine
    container_name: {{DOCKER_COMPOSE_PROJECT}}-nginx
    ports:
      - "{{XAMPP_SERVER_PORT}}:80"
      - "{{XAMPP_SSL_PORT}}:443"
    volumes:
      - {{DOCKER_WWW_ROOT}}:/var/www/html
      - ./dist/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./dist/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./dist/certs:/etc/nginx/certs:ro
    networks:
      - {{DOCKER_NETWORK}}
    depends_on:
      - php-fpm
    restart: unless-stopped

  php-fpm:
    build:
      context: .
      args:
        PHP_VERSION: {{DOCKER_PHP_VERSION}}
    image: {{DOCKER_COMPOSE_PROJECT}}-php:{{DOCKER_PHP_VERSION}}
    container_name: {{DOCKER_COMPOSE_PROJECT}}-php
    volumes:
      - {{DOCKER_WWW_ROOT}}:/var/www/html
      - ./dist/php/php.ini:/usr/local/etc/php/php.ini:ro
    networks:
      - {{DOCKER_NETWORK}}
    restart: unless-stopped

  mysql:
    image: mysql:{{DOCKER_MYSQL_VERSION}}
    container_name: {{DOCKER_COMPOSE_PROJECT}}-mysql
    ports:
      - "{{MYSQL_PORT}}:3306"
    environment:
      MYSQL_ROOT_PASSWORD: {{MYSQL_ROOT_PASSWORD}}
    volumes:
      - mysql-data:/var/lib/mysql
      - ./dist/mysql/my.cnf:/etc/mysql/conf.d/custom.cnf:ro
    networks:
      - {{DOCKER_NETWORK}}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-p{{MYSQL_ROOT_PASSWORD}}"]
      interval: 10s
      timeout: 5s
      retries: 5

  phpmyadmin:
    image: phpmyadmin:latest
    container_name: {{DOCKER_COMPOSE_PROJECT}}-pma
    ports:
      - "{{DOCKER_PMA_PORT}}:80"
    environment:
      PMA_HOST: mysql
      PMA_PORT: 3306
      PMA_USER: root
      PMA_PASSWORD: {{MYSQL_ROOT_PASSWORD}}
      UPLOAD_LIMIT: {{PHP_UPLOAD_MAX_FILESIZE}}
    networks:
      - {{DOCKER_NETWORK}}
    depends_on:
      mysql:
        condition: service_healthy
    restart: unless-stopped

{{DOCKER_ADMINER_SERVICE}}

{{DOCKER_POSTGRES_SERVICE}}

networks:
  {{DOCKER_NETWORK}}:
    driver: bridge

volumes:
  mysql-data:
{{DOCKER_POSTGRES_VOLUME}}
```

**Note:** `{{DOCKER_ADMINER_SERVICE}}`, `{{DOCKER_POSTGRES_SERVICE}}`, `{{DOCKER_POSTGRES_VOLUME}}` are injected programmatically by `Build-Compose.ps1` based on `.env` flags. Empty string when disabled.

**Adminer service block (injected when `DOCKER_INCLUDE_ADMINER=true`):**
```yaml
  adminer:
    image: adminer:latest
    container_name: {{DOCKER_COMPOSE_PROJECT}}-adminer
    ports:
      - "{{DOCKER_ADMINER_PORT}}:8080"
    networks:
      - {{DOCKER_NETWORK}}
    restart: unless-stopped
```

**Postgres service block (injected when `DOCKER_INCLUDE_POSTGRES=true`):**
```yaml
  postgres:
    image: postgres:{{DOCKER_POSTGRES_VERSION}}
    container_name: {{DOCKER_COMPOSE_PROJECT}}-postgres
    ports:
      - "{{POSTGRES_PORT}}:5432"
    environment:
      POSTGRES_DB: {{POSTGRES_DB}}
      POSTGRES_USER: {{POSTGRES_USER}}
      POSTGRES_PASSWORD: {{POSTGRES_PASSWORD}}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./dist/postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro
    networks:
      - {{DOCKER_NETWORK}}
    restart: unless-stopped
```

---

### File: `config/templates/nginx/nginx.conf.template`

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    sendfile        on;
    keepalive_timeout 65;

    client_max_body_size {{PHP_UPLOAD_MAX_FILESIZE}};

    include /etc/nginx/conf.d/*.conf;
}
```

---

### File: `config/templates/nginx/vhost-blocks.template`

One named block per site type. `Build-Compose.ps1` extracts the correct block by type name, substitutes variables, and writes one `.conf` file per site.

```nginx
[laravel]
server {
    listen 80;
    server_name {{SERVER_NAME}};
    root /var/www/html/{{FOLDER}}/public;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
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
        proxy_cache_bypass $http_upgrade;
    }

    access_log /var/log/nginx/{{FOLDER}}-access.log;
    error_log  /var/log/nginx/{{FOLDER}}-error.log;
}
[/react]

[wordpress]
server {
    listen 80;
    server_name {{SERVER_NAME}};
    root /var/www/html/{{FOLDER}};
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. {
        deny all;
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

    location / {
        try_files $uri $uri/ =404;
    }

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

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
[/default]
```

---

### File: `config/templates/php/php.ini.template`

Adapted from xampp-tools `php.ini.template` — remove Windows-specific extension paths, keep runtime settings:

```ini
[PHP]
display_errors = On
display_startup_errors = On
error_reporting = E_ALL
log_errors = On

post_max_size = {{PHP_POST_MAX_SIZE}}
upload_max_filesize = {{PHP_UPLOAD_MAX_FILESIZE}}
max_execution_time = 300
max_input_time = 300
memory_limit = 512M

date.timezone = Europe/London

[Session]
session.cookie_httponly = 1
```

---

### File: `config/templates/mysql/my.cnf.template`

Adapted from xampp-tools `my.ini.template` — Linux paths, no Windows socket:

```ini
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci

innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2

max_connections = 100
max_allowed_packet = 64M

slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2

[client]
default-character-set = utf8mb4
```

---

### Module: `bin/modules/Build-Compose.ps1`

**Metadata header:**
```powershell
# Name: Build Compose
# Description: Compile templates and generate docker-compose.yml + nginx configs
# Icon: 🔨
# Cmd: build
# Order: 2
# Hidden: false
```

**Functions to implement:**

```
Invoke-BuildCompose               # main orchestrator
Compile-Template                  # {{PLACEHOLDER}} substitution (port from xampp-tools Build-Configs)
Get-VhostBlock                    # extract named block from vhost-blocks.template by type
Build-NginxConf                   # generate one conf file per vhost
Build-ComposeFile                 # compile docker-compose.yml.template + inject optional services
Build-HostsEntries                # write 127.0.0.1 entries to Windows hosts file
Validate-VhostFolders             # check all vhost folders exist in DOCKER_WWW_ROOT
Detect-DuplicateDomains           # same logic as xampp-tools Build-Configs
Get-ServerName                    # compute domain: folder + VHOSTS_EXTENSION (or domain override)
Get-DockerWwwRoot                 # returns DOCKER_DOCUMENT_ROOT if set, else XAMPP_DOCUMENT_ROOT
```

**Step-by-step logic:**

```
1.  Load config.json
2.  Resolve envFile path (../xampp-tools/.env) → Load-EnvFile
3.  Resolve vhostsFile (../xampp-tools/config/vhosts.json) → ConvertFrom-Json
4.  Resolve DOCKER_WWW_ROOT (DOCKER_DOCUMENT_ROOT ?? XAMPP_DOCUMENT_ROOT)
5.  Validate all vhost folders exist in DOCKER_WWW_ROOT → warn on missing
6.  Detect duplicate domains → warn, continue
7.  Ensure dist/ subdirs exist (nginx/conf.d, php, mysql, postgres, certs)
8.  Compile base templates → dist/ (nginx.conf, php.ini, my.cnf)
9.  Load vhost-blocks.template
10. For each vhost in vhosts.json:
      serverName = compute from folder + VHOSTS_EXTENSION (or site.domain override)
      port       = site.port ?? 8081 (for react), else unused
      block      = Get-VhostBlock -Type site.type
      block      = substitute {{FOLDER}}, {{SERVER_NAME}}, {{PORT}}, {{VHOSTS_EXTENSION}}
      write to   dist/nginx/conf.d/{folder}.conf
11. Build optional service blocks:
      adminerBlock   = if DOCKER_INCLUDE_ADMINER eq "true" → expand adminer template block
      postgresBlock  = if DOCKER_INCLUDE_POSTGRES eq "true" → expand postgres template block
      postgresVolume = if DOCKER_INCLUDE_POSTGRES eq "true" → "  postgres-data:" else ""
12. Substitute all env vars into docker-compose.yml.template
      Replace {{DOCKER_ADMINER_SERVICE}} → adminerBlock or ""
      Replace {{DOCKER_POSTGRES_SERVICE}} → postgresBlock or ""
      Replace {{DOCKER_POSTGRES_VOLUME}} → postgresVolume or ""
      Replace {{DOCKER_WWW_ROOT}} → resolved www root
13. Write compiled compose → ./docker-compose.yml (at docker-tools root)
14. Update Windows hosts file:
      Read existing hosts file
      Remove existing docker-tools-managed block (between marker comments)
      Build new block:
        # docker-tools managed — do not edit
        127.0.0.1  {serverName}      (for each vhost)
        # end docker-tools managed
      Write updated hosts file
15. Print build summary: N sites built, optional services enabled
```

**Compile-Template function:**
```powershell
function Compile-Template {
    param([string]$Content, [hashtable]$Vars)
    foreach ($key in $Vars.Keys) {
        $Content = $Content -replace "\{\{$key\}\}", $Vars[$key]
    }
    return $Content
}
```

**Get-VhostBlock function:**
```powershell
function Get-VhostBlock {
    param([string]$TemplateContent, [string]$Type)
    if ($TemplateContent -match "(?s)\[$Type\](.*?)\[/$Type\]") {
        return $matches[1].Trim()
    }
    # Fallback to [default] block
    if ($TemplateContent -match "(?s)\[default\](.*?)\[/default\]") {
        return $matches[1].Trim()
    }
    return ""
}
```

---

### Module: `bin/modules/Docker-Controller.ps1`

**Metadata header:**
```powershell
# Name: Docker Controller
# Description: Start, Stop, Restart containers and view status
# Icon: 🐳
# Cmd: docker
# Order: 1
# Hidden: false
```

**Menu:**
```
  1) Start All          → docker compose -f {composePath} up -d
  2) Stop All           → docker compose -f {composePath} down
  3) Restart All        → docker compose -f {composePath} restart
  4) Status             → docker compose -f {composePath} ps
  5) Open Shell         → prompt for service → docker exec -it {container} sh
  6) Rebuild Images     → docker compose -f {composePath} build --no-cache
  0) Back
```

**Exported helpers (callable by other modules):**
```powershell
function Invoke-DockerStart   { docker compose -f (Get-ComposePath) up -d }
function Invoke-DockerStop    { docker compose -f (Get-ComposePath) down }
function Invoke-DockerRestart { docker compose -f (Get-ComposePath) restart }
```

**Show-DockerStatus:** Parse `docker compose ps` output, display per-service status with emoji (🟢 running, ⚫ stopped, 🔴 unhealthy).

---

### Module: `bin/modules/Startup-Check.ps1`

**Metadata header:**
```powershell
# Name: Startup Check
# Description: Validate environment before starting Docker services
# Icon: ✅
# Cmd: check
# Order: 3
# Hidden: false
```

**Checks (in order):**

| # | Check | Pass condition | Fail action |
|---|-------|---------------|-------------|
| 1 | Docker daemon | `docker info` exit 0 | Error + exit |
| 2 | `.env` file exists | `Test-Path $envFile` | Error + exit |
| 3 | Required env keys | All keys in required list present | Warn missing keys |
| 4 | `vhosts.json` readable | `ConvertFrom-Json` succeeds | Error + exit |
| 5 | XAMPP processes running | `Get-Process httpd, mysqld` | Prompt to stop |
| 6 | Port 80 available | `Test-NetConnection localhost 80` fails | Warn |
| 7 | Port 443 available | `Test-NetConnection localhost 443` fails | Warn |
| 8 | Port 3306 available | `Test-NetConnection localhost 3306` fails | Warn |
| 9 | `docker-compose.yml` exists | `Test-Path $composePath` | Prompt to run Build |
| 10 | compose config valid | `docker compose config` exit 0 | Error |
| 11 | `XAMPP_DOCUMENT_ROOT` exists | `Test-Path $wwwRoot` | Warn |
| 12 | Hosts file entries | All vhost domains present in hosts | Warn + offer to run Build |

**XAMPP stop flow (check #5):**
```powershell
$xamppCommon = Join-Path $xamppToolsRoot "bin\Common.ps1"
if (Test-Path $xamppCommon) {
    . $xamppCommon
    Write-Warning2 "XAMPP is running. Stopping before Docker starts..."
    Invoke-XamppStop
    Start-Sleep -Seconds 3
}
```

**Required env keys list:**
```powershell
$required = @(
    'XAMPP_DOCUMENT_ROOT', 'XAMPP_SERVER_PORT', 'XAMPP_SSL_PORT',
    'MYSQL_PORT', 'MYSQL_ROOT_PASSWORD',
    'DOCKER_COMPOSE_PROJECT', 'DOCKER_NETWORK',
    'DOCKER_PHP_VERSION', 'DOCKER_MYSQL_VERSION'
)
```

---

### Module: `Docker-Tools.ps1` (entry point)

Near-identical copy of `Xampp-Tools.ps1`. Changes:
- Update `$script:EnvFile` path to `../xampp-tools/.env`
- Update `$script:DistDir` to `dist`
- Update `Show-Header` text (via `Common.ps1`)
- Module discovery path stays `bin/modules/`

---

## Phase 2 — Database Operations

All modules follow the same pattern:
1. Load env via `Get-SharedEnvPath`
2. Derive container name: `Get-ContainerName "mysql" $envVars`
3. Check container is running before proceeding
4. Execute `docker exec` command
5. Report result

---

### Module: `bin/modules/Backup-MySQL.ps1`

**Core logic:**
```powershell
# List databases
$databases = docker exec $mysqlContainer mysql -u root -p"$rootPwd" -e "SHOW DATABASES;" --skip-column-names 2>&1
# Filter system databases
$userDbs = $databases | Where-Object { $_ -notin @('information_schema','performance_schema','mysql','sys') }

# Dump selected database
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupPath = Join-Path $backupDir "$dbName-$timestamp.sql.gz"
docker exec $mysqlContainer mysqldump -u root -p"$rootPwd" $dbName | gzip | Set-Content $backupPath -AsByteStream

# Also backup grants
docker exec $mysqlContainer mysql -u root -p"$rootPwd" -e "SHOW GRANTS;" > "$backupDir\grants-$timestamp.sql"
```

**Note on gzip in PowerShell:** Use `Compress-Archive` or pipe to `7z` if `gzip` not available on Windows host. Alternatively run gzip inside the container:
```powershell
docker exec $mysqlContainer sh -c "mysqldump -u root -p'$rootPwd' $dbName | gzip" | Set-Content $backupPath -AsByteStream
```

---

### Module: `bin/modules/Restore-MySQL.ps1`

```powershell
# Decompress and pipe into container
$content = [System.IO.Compression.GZipStream] ... # or use temp file approach
Get-Content $backupFile -AsByteStream | docker exec -i $mysqlContainer sh -c "gunzip | mysql -u root -p'$rootPwd' $dbName"
```

Safer temp file approach:
```powershell
$tmpSql = "$env:TEMP\restore-$dbName.sql"
# Decompress to temp
[System.IO.Compression.GZipStream] → $tmpSql
# Pipe into container
Get-Content $tmpSql | docker exec -i $mysqlContainer mysql -u root -p"$rootPwd" $dbName
Remove-Item $tmpSql
```

---

### Module: `bin/modules/Create-Database.ps1`

```powershell
docker exec $mysqlContainer mysql -u root -p"$rootPwd" -e `
    "CREATE DATABASE \`$dbName\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# Optional user creation
docker exec $mysqlContainer mysql -u root -p"$rootPwd" -e `
    "CREATE USER '$dbUser'@'%' IDENTIFIED BY '$dbPass'; GRANT ALL PRIVILEGES ON \`$dbName\`.* TO '$dbUser'@'%'; FLUSH PRIVILEGES;"
```

---

### Module: `bin/modules/Cleanup-MySQL.ps1`

```powershell
# List dangling volumes
$volumes = docker volume ls --filter dangling=true --format "{{.Name}}" 2>&1
$mysqlVolumes = $volumes | Where-Object { $_ -match "mysql" }

# Prompt per volume or batch
docker volume rm $volumeName
```

---

## Phase 3 — Operations

---

### Module: `bin/modules/Redeploy.ps1`

Five steps — same pattern as xampp-tools:

```powershell
Show-Step "1" "Backup current configs"   "current"
& (Join-Path $modulesDir "Backup-Configs.ps1")
Show-Step "1" "Backup current configs"   "done"

Show-Step "2" "Build compose + configs"  "current"
& (Join-Path $modulesDir "Build-Compose.ps1") -Silent
Show-Step "2" "Build compose + configs"  "done"

Show-Step "3" "Stop containers"          "current"
docker compose -f $composePath down
Show-Step "3" "Stop containers"          "done"

Show-Step "4" "Start containers"         "current"
docker compose -f $composePath up -d --force-recreate
Show-Step "4" "Start containers"         "done"

Show-Step "5" "Startup check"            "current"
& (Join-Path $modulesDir "Startup-Check.ps1") -Silent
Show-Step "5" "Startup check"            "done"
```

---

### Module: `bin/modules/View-Logs.ps1`

```
  1) All services       → docker compose -f {path} logs -f
  2) nginx              → docker compose -f {path} logs -f nginx
  3) php-fpm            → docker compose -f {path} logs -f php-fpm
  4) mysql              → docker compose -f {path} logs -f mysql
  5) phpmyadmin         → docker compose -f {path} logs -f phpmyadmin
  6) postgres           → docker compose -f {path} logs -f postgres  (if enabled)
  7) adminer            → docker compose -f {path} logs -f adminer    (if enabled)
  0) Back
```

---

### Module: `bin/modules/Kill-Services.ps1`

```powershell
docker compose -f $composePath kill
Start-Sleep -Seconds 2
docker compose -f $composePath rm -f
# Also clean dangling containers from this project
docker ps -a --filter "label=com.docker.compose.project=$project" --format "{{.ID}}" | ForEach-Object {
    docker rm -f $_
}
```

---

### Module: `bin/modules/Backup-Configs.ps1`

```powershell
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupTarget = Join-Path $backupDir $timestamp
New-Item -ItemType Directory -Path $backupTarget -Force

# Copy dist/ folder structure
Copy-Item -Path $distDir -Destination $backupTarget -Recurse -Force
# Copy docker-compose.yml
Copy-Item -Path $composePath -Destination $backupTarget -ErrorAction SilentlyContinue

Write-Success "Configs backed up to backups\$timestamp"
```

---

### Module: `bin/modules/Services.ps1`

Thin wrapper — dot-sources `Docker-Controller.ps1` functions:

```
  1) Start All
  2) Stop All
  3) Restart All
  0) Back
```

---

## Phase 4 — Extended

---

### Module: `bin/modules/Setup-SSL.ps1`

**Metadata:**
```powershell
# Name: Setup SSL
# Description: Generate trusted SSL certificates with mkcert
# Icon: 🔐
# Cmd: ssl
# Order: 13
```

**Logic:**
1. Check `mkcert` is installed (`mkcert -version`)
2. If not: show install instructions (Scoop: `scoop install mkcert`) + link
3. Run `mkcert -install` to set up local CA (requires admin)
4. For each SSL-enabled vhost (`ssl: true` in vhosts.json):
   - Compute domain: `folder + VHOSTS_EXTENSION`
   - Run `mkcert -cert-file dist/certs/{folder}.pem -key-file dist/certs/{folder}-key.pem {domain}`
5. Update nginx vhost conf to add SSL server block (port 443)
6. Remind to run `Redeploy` to apply

---

### Module: `bin/modules/Switch-PHP.ps1`

**Logic:**
1. Show current `DOCKER_PHP_VERSION` from `.env`
2. List available versions (same registry as xampp-tools `Switch-PHP.ps1`)
3. On selection: update `DOCKER_PHP_VERSION` in `../xampp-tools/.env`
4. Prompt: rebuild image now?
5. If yes: `docker compose -f {path} build --no-cache php-fpm`
6. Prompt: restart php-fpm?
7. If yes: `docker compose -f {path} restart php-fpm`

---

### Module: `bin/modules/Install-Docker.ps1`

**Metadata:**
```powershell
# Name: Install Docker
# Description: Download and install Docker Desktop for Windows
# Icon: 📦
# Cmd: install
# Order: 17
```

**Logic:**
1. Check if Docker already installed (`docker --version`)
2. If installed: show version + offer to check for updates
3. If not:
   - Detect Windows version (`[System.Environment]::OSVersion`)
   - Download Docker Desktop installer from official URL
   - Run installer: `Start-Process -FilePath $installerPath -ArgumentList "install --quiet" -Wait`
   - Verify: `docker --version`
4. Check if `mkcert` installed (`mkcert -version`)
5. If not: attempt Scoop install, else provide manual download URL
6. Show post-install checklist

---

### Module: `bin/modules/Firewall.ps1`

Same logic as xampp-tools `Firewall.ps1` but for Docker ports:

```powershell
$rules = @(
    @{ Name = "Docker-HTTP-Block";     Port = 80;   Protocol = "TCP" },
    @{ Name = "Docker-HTTPS-Block";    Port = 443;  Protocol = "TCP" },
    @{ Name = "Docker-MySQL-Block";    Port = 3306; Protocol = "TCP" },
    @{ Name = "Docker-PMA-Block";      Port = 8080; Protocol = "TCP" },
    @{ Name = "Docker-Adminer-Block";  Port = 8081; Protocol = "TCP" },
    @{ Name = "Docker-Postgres-Block"; Port = 5432; Protocol = "TCP" }
)
# Create inbound block rules for external access
New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -LocalPort $rule.Port -Protocol $rule.Protocol -Action Block -RemoteAddress Internet
```

---

## Module Reuse from xampp-tools

Modules that can be **copied with minimal changes** (just update env path and container context):

| xampp-tools module | Change needed |
|---|---|
| `Alias.ps1` | Update paths only |
| `Firewall.ps1` | Update port list |
| `Create-Ascii.ps1` | No changes |
| `View-Logs.ps1` | Replace log tail with `docker compose logs -f` |

Modules that need **significant rework** (different runtime context):

| Module | Reason |
|---|---|
| `Build-Configs.ps1` → `Build-Compose.ps1` | Outputs compose + nginx instead of Apache configs |
| `Deploy-VHosts.ps1` | Merged into Build-Compose — no deploy step needed |
| `Deploy-Configs.ps1` | Not needed — configs are volume-mounted, no copy step |
| `Setup-MySQL.ps1` | MySQL init handled by Docker image env vars |
| `Startup-Check.ps1` | Completely different checks (Docker vs XAMPP) |
| `Switch-PHP.ps1` | Rebuilds Docker image instead of moving PHP dirs |
| `Services.ps1` | docker compose instead of batch scripts |

---

## Testing Each Phase

### Phase 1 test:
```powershell
.\Docker-Tools.ps1     # menu loads, modules discovered
> build                # dist/ populated, docker-compose.yml generated
> check                # all checks pass
> docker               # containers start
# Open browser: http://api.idiliq.dev → Laravel site loads
# Open browser: http://localhost:8080 → phpMyAdmin loads
```

### Phase 2 test:
```powershell
> create-db            # create test database in container
> backup-db            # .sql.gz file appears in backups/
> restore-db           # restore from that file
```

### Phase 3 test:
```powershell
> redeploy             # full pipeline completes without errors
> logs                 # nginx/mysql logs stream
> kill                 # all containers removed
```

### Phase 4 test:
```powershell
> ssl                  # certs generated in dist/certs/, browser trusts them
> php                  # PHP version updated in .env, image rebuilt
```

---

## Key Constants and Conventions

All modules follow these rules:

1. **Env file path:** always resolved via `Get-SharedEnvPath` — never hardcoded
2. **Vhosts path:** always resolved via `Get-SharedVhostsPath`
3. **Compose path:** always resolved via `Get-ComposePath`
4. **Container names:** always derived from `Get-ContainerName "{service}" $envVars`
5. **Dist dir:** always `Get-DistDir` — never hardcoded
6. **Module header:** every module has Name, Description, Icon, Cmd, Order, Hidden comment block
7. **Common.ps1:** always loaded first via `. (Join-Path $moduleRoot "bin\Common.ps1")`
8. **Show-Header:** called at start of every module (clears screen, shows banner)
9. **Exit codes:** `exit 1` on fatal errors, `exit 0` on success
