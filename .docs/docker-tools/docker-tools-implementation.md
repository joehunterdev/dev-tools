# Docker Tools — Implementation Plan

## Status: Ready to Build

All architectural decisions resolved (see `docker-tools-plan.md`). This document is the phase-by-phase build guide. Each phase has clear goals, file deliverables, and validation steps.

---

## Guiding Principles

1. **Single source of truth** — `.env`, `vhosts.json`, and shared helpers live at `dev-tools/` root. Never duplicate.
2. **Executor injection** — shared modules accept script block parameters so one file supports both XAMPP and Docker execution.
3. **Additive migration** — xampp-tools keeps working throughout. No big-bang moves.
4. **Convention over configuration** — same metadata header format, same launcher pattern, same module resolution as xampp-tools.

---

## Pre-flight Checklist

Before any code is written:

- [x] `docker-tools-brief.md`, `docker-tools-plan.md`, `proposed-architecture.md` reviewed and agreed
- [x] Merge conflict in `dev-tools.code-workspace` resolved
- [ ] Current xampp-tools is committed (clean working tree)
- [ ] A feature branch is cut: `git checkout -b feature/docker-tools-and-shared-core`

---

## Phase 0 — Shared Core Migration

**Goal:** extract shared code from xampp-tools into top-level `common/` without breaking xampp-tools.

**Why first:** docker-tools should consume the shared core from day one, not reproduce it.

### 0.1 Create top-level directories

```
dev-tools/
├── common/
│   ├── assets/
│   └── modules/
└── config/                        ← new
```

### 0.2 Move shared config files

| Action | Source | Destination |
|--------|--------|-------------|
| Move | `xampp-tools/.env.example` | `dev-tools/.env.example` (root) |
| Move | `xampp-tools/.env` | `dev-tools/.env` (root) |
| Move | `xampp-tools/config/vhosts.json` | `dev-tools/config/vhosts.json` |
| Move | `xampp-tools/bin/assets/signature-lg.txt` | `dev-tools/common/assets/signature-lg.txt` |

Append the Docker section from `proposed-architecture.md` to the new root `.env.example`.

### 0.3 Split Common.ps1

Current `xampp-tools/bin/Common.ps1` is a mix of:
- Truly shared helpers (Show-Header, Show-Signature, Show-Step, Write-Info/Success/Error2/Warning2, Prompt-YesNo, Prompt-Continue, Load-EnvFile, Test-Administrator, Write-AuditLog)
- XAMPP-specific helper (Load-FilesConfig — currently reads `xampp-tools/config/config.json`)

**Action:** split into two files.

`common/Common.ps1` — keep all truly shared helpers. Update `Show-Signature` to read from `common/assets/signature-lg.txt`:

```powershell
function Show-Signature {
    param([string]$Color = "DarkCyan")
    $signaturePath = Join-Path $PSScriptRoot "assets\signature-lg.txt"
    if (Test-Path $signaturePath) {
        Get-Content $signaturePath | ForEach-Object { Write-Host $_ -ForegroundColor $Color }
    }
}
```

Update `Show-Header` to use `$script:ToolName`:

```powershell
function Show-Header {
    Clear-Host
    Show-Signature -Color "DarkCyan"
    $title = if ($script:ToolName) { $script:ToolName } else { "Dev Tools" }
    Write-Host ""
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "  by Joe Hunter - github.com/joehunterdev" -ForegroundColor DarkGray
    Write-Host ""
}
```

Add shared path/resolve helpers to `common/Common.ps1`:

```powershell
function Get-DevToolsRoot {
    if ($script:DevToolsRoot) { return $script:DevToolsRoot }
    return Split-Path $PSScriptRoot -Parent
}

function Get-SharedEnvPath {
    return Join-Path (Get-DevToolsRoot) ".env"
}

function Get-SharedVhostsPath {
    return Join-Path (Get-DevToolsRoot) "config\vhosts.json"
}

function Load-SharedEnv {
    $envFile = Get-SharedEnvPath
    return Load-EnvFile $envFile
}

function Load-SharedVhosts {
    $vhostsFile = Get-SharedVhostsPath
    if (Test-Path $vhostsFile) {
        return Get-Content $vhostsFile -Raw | ConvertFrom-Json
    }
    return $null
}
```

### 0.4 Move Service-Helpers.ps1

```
Move: xampp-tools/bin/Service-Helpers.ps1 → common/Service-Helpers.ps1
```

Update any `$PSScriptRoot`-based paths inside to resolve correctly from the new location.

### 0.5 Update Xampp-Tools.ps1 launcher

Update paths at the top of `xampp-tools/Xampp-Tools.ps1`:

```powershell
$script:ToolName     = "XAMPP Tools"
$script:ToolRoot     = $PSScriptRoot
$script:DevToolsRoot = Split-Path $PSScriptRoot -Parent
$script:CommonDir    = Join-Path $script:DevToolsRoot "common"
$script:EnvFile      = Join-Path $script:DevToolsRoot ".env"
$script:VhostsFile   = Join-Path $script:DevToolsRoot "config\vhosts.json"
$script:BinDir       = Join-Path $PSScriptRoot "bin"
$script:ModulesDir   = Join-Path $PSScriptRoot "bin\modules"

. (Join-Path $script:CommonDir "Common.ps1")
. (Join-Path $script:CommonDir "Service-Helpers.ps1")
```

Update `Get-AvailableModules` to discover from BOTH `common/modules/` AND `bin/modules/`:

```powershell
function Get-AvailableModules {
    $modules = @()
    $modules += Discover-ModulesIn (Join-Path $script:CommonDir "modules")
    $modules += Discover-ModulesIn (Join-Path $script:ModulesDir)
    # Deduplicate by Cmd — tool-specific shadows shared
    $seen = @{}
    $unique = @()
    foreach ($m in ($modules | Sort-Object { if ($_.IsLocal) { 0 } else { 1 } })) {
        if (-not $seen[$m.Cmd]) { $seen[$m.Cmd] = $true; $unique += $m }
    }
    return $unique | Sort-Object { $_.Order }
}
```

### 0.6 Update any xampp-tools module that references moved files

Grep for `$PSScriptRoot`-based paths to `.env`, `vhosts.json`, `signature-lg.txt`, `Common.ps1`, `Service-Helpers.ps1` and update to use the shared helpers (`Load-SharedEnv`, `Get-SharedVhostsPath`, etc.) or the new `$script:DevToolsRoot`-based paths.

### 0.7 Move truly shared modules (optional, can defer to Phase 3)

Candidates for `common/modules/`:
- `Alias.ps1` — identical in both tools
- `Create-Ascii.ps1` — identical
- `Firewall.ps1` — accepts port list parameter
- `Backup-MySQL.ps1`, `Restore-MySQL.ps1`, `Create-Database.ps1`, `Cleanup-MySQL.ps1` — UI identical, refactor to accept `$DbExecutor` script block
- `View-Logs.ps1` — UI identical, refactor to accept `$LogSource` script block

Defer this migration until the shared docker-tools modules exist (Phase 3) so the executor-injection pattern can be validated against two consumers simultaneously.

### 0.8 Validation

- [ ] `.\xampp-tools\Xampp-Tools.ps1` launches and shows the menu
- [ ] Header banner displays correctly
- [ ] Every xampp-tools module still executes (smoke test each one)
- [ ] `.env` values load correctly
- [ ] `vhosts.json` parses correctly
- [ ] Commit with message: `refactor: extract shared core to dev-tools/common`

---

## Phase 0.5 — Shared Utilities, Engines & Non-XAMPP Modules

**Goal:** Extract generic engines and tool-agnostic modules out of xampp-tools so docker-tools can consume them from day one.

**Why between Phase 0 and Phase 1:** docker-tools' `Build-Compose.ps1` (Phase 1) will consume the template engine, hosts helpers, env validator, and vhost validator. Building these first means zero duplication in Build-Compose.

---

### 0.5.1 Extract: `common/Template-Engine.ps1`

Pull the `{{PLACEHOLDER}}` substitution logic and the `[name]...[/name]` named-block parser out of `xampp-tools/bin/modules/Build-Configs.ps1`.

**Exported functions:**

```powershell
function Compile-Template {
    param([string]$Content, [hashtable]$Vars)
    foreach ($key in $Vars.Keys) {
        $value = if ($null -eq $Vars[$key]) { "" } else { [string]$Vars[$key] }
        $Content = $Content -replace "\{\{$key\}\}", [regex]::Escape($value).Replace('\\','\')
    }
    return $Content
}

function Invoke-TemplateBuild {
    # Process a list of template→output mappings from config.json
    param(
        [string]$SourceDir,
        [string]$DistDir,
        [array]$Files,             # @(@{template=...; output=...; type=...}, ...)
        [hashtable]$Vars,
        [hashtable]$TypeHandlers   # @{ hosts = { param($content) ... } }
    )
    # Returns @{ Built = @(); Skipped = @(); UnreplacedPlaceholders = @() }
}

function Get-NamedBlock {
    param([string]$TemplateContent, [string]$BlockName, [string]$Fallback = 'default')
    if ($TemplateContent -match "(?s)\[$BlockName\](.*?)\[/$BlockName\]") {
        return $matches[1].Trim()
    }
    if ($Fallback -and $TemplateContent -match "(?s)\[$Fallback\](.*?)\[/$Fallback\]") {
        return $matches[1].Trim()
    }
    return ""
}

function Test-UnreplacedPlaceholders {
    param([string]$Content)
    $m = [regex]::Matches($Content, "\{\{([A-Z_][A-Z0-9_]*)\}\}")
    return $m | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
}
```

**Update:** `xampp-tools/bin/modules/Build-Configs.ps1` dot-sources `common/Template-Engine.ps1` and calls these functions instead of inline logic. Zero behavior change.

---

### 0.5.2 Extract: `common/Hosts-Helpers.ps1`

Pull managed-block hosts file writer out of xampp-tools' `Build-Configs.ps1` / `Deploy-VHosts.ps1`.

**Exported functions:**

```powershell
function Update-HostsBlock {
    param(
        [string]$MarkerLabel,                          # e.g. "docker-tools" or "xampp-tools"
        [string[]]$Entries,                            # raw lines, e.g. "127.0.0.1  site.local"
        [string]$HostsPath = "$env:WinDir\System32\drivers\etc\hosts"
    )
    # Idempotently replace the block between marker comments, or append if absent.
    # Requires admin — returns $false with warning otherwise.
}

function Remove-HostsBlock {
    param([string]$MarkerLabel, [string]$HostsPath = "$env:WinDir\System32\drivers\etc\hosts")
}

function Get-HostsBlock {
    param([string]$MarkerLabel, [string]$HostsPath = "$env:WinDir\System32\drivers\etc\hosts")
    # Returns string[] of current entries or $null if no block
}

function Test-HostsEntriesPresent {
    param([string[]]$RequiredEntries, [string]$HostsPath = "$env:WinDir\System32\drivers\etc\hosts")
    # Returns array of missing entries
}
```

**Marker format** used by both tools (distinct labels so entries don't conflict):
```
# --- {label} managed: do not edit ---
127.0.0.1  site.local
# --- /{label} managed ---
```

xampp-tools uses `MarkerLabel = "xampp-tools"`, docker-tools uses `MarkerLabel = "docker-tools"`. Both can have blocks present simultaneously — the active tool's entries take precedence at the same IP (identical entries are idempotent).

---

### 0.5.3 Extract: `common/Env-Validator.ps1`

Pull required-env-key validation (scattered across xampp-tools modules).

```powershell
function Test-RequiredEnvKeys {
    param([hashtable]$EnvVars, [string[]]$Required)
    $missing = @()
    foreach ($key in $Required) {
        if (-not $EnvVars.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($EnvVars[$key])) {
            $missing += $key
        }
    }
    return $missing
}

function Assert-EnvKeys {
    # Calls Test-RequiredEnvKeys; Write-Error2 + exit 1 on any missing
    param([hashtable]$EnvVars, [string[]]$Required)
}
```

Used by `Startup-Check.ps1` in both tools with different required-key lists.

---

### 0.5.4 Extract: `common/Vhost-Validator.ps1`

Pull vhost folder validation + duplicate domain detection out of xampp-tools' `Build-Configs.ps1`.

```powershell
function Test-VhostFolders {
    param([array]$Vhosts, [string]$DocumentRoot)
    # Returns array of missing folders with vhost metadata
}

function Find-DuplicateDomains {
    param([array]$Vhosts, [string]$Extension)
    # Returns array of @{ domain = ...; sites = @(...) }
}

function Get-VhostDomain {
    param($Vhost, [string]$Extension)
    if ($Vhost.domain) { return $Vhost.domain }
    return "$($Vhost.folder)$Extension"
}
```

---

### 0.5.5 Extract: `common/Php-Versions.ps1`

Move the PHP version registry (currently inside `xampp-tools/bin/modules/Switch-PHP.ps1`) — the **data** is tool-agnostic, only the install action differs.

```powershell
$script:PhpVersions = @{
    "7.4" = @{ Version = "7.4.33"; DownloadUrl = "..."; DockerImageTag = "7.4-fpm"; ApacheModule = "php7apache2_4.dll" }
    "8.0" = @{ Version = "8.0.30"; DownloadUrl = "..."; DockerImageTag = "8.0-fpm"; ApacheModule = "php8apache2_4.dll" }
    "8.1" = @{ Version = "8.1.29"; DownloadUrl = "..."; DockerImageTag = "8.1-fpm"; ApacheModule = "php8apache2_4.dll" }
    "8.2" = @{ Version = "8.2.25"; DownloadUrl = "..."; DockerImageTag = "8.2-fpm"; ApacheModule = "php8apache2_4.dll" }
    "8.3" = @{ Version = "8.3.15"; DownloadUrl = "..."; DockerImageTag = "8.3-fpm"; ApacheModule = "php8apache2_4.dll" }
    "8.4" = @{ Version = "8.4.2";  DownloadUrl = "..."; DockerImageTag = "8.4-fpm"; ApacheModule = "php8apache2_4.dll" }
}

function Get-PhpVersions   { return $script:PhpVersions }
function Get-PhpVersionInfo { param([string]$Version) return $script:PhpVersions[$Version] }
function Test-PhpVersionValid { param([string]$Version) return $script:PhpVersions.ContainsKey($Version) }
```

xampp-tools' `Switch-PHP.ps1` uses `DownloadUrl` + `ApacheModule`. docker-tools' `Switch-PHP.ps1` uses `DockerImageTag`. Same registry, different fields consumed.

---

### 0.5.6 Move: `common/modules/Install-Stripe-Package.ps1`

Current file `xampp-tools/bin/modules/Install-Stripe-Package.ps1` installs Stripe CLI, Composer, or Node.js — **nothing XAMPP-specific**. Just dev-tool installers with SRP integration.

Move as-is → `common/modules/Install-Stripe-Package.ps1`. Adds value to docker-tools immediately (same install flows work).

Consider renaming to `Install-Dev-Tools.ps1` for clarity since Stripe is just one of the tools, but defer rename to avoid churn.

---

### 0.5.7 Move: `common/modules/Create-Shortcuts.ps1`

Current file `xampp-tools/bin/modules/Create-Shortcuts.ps1` creates Windows desktop shortcuts. Generic Windows utility.

**Add parameter:**
```powershell
param(
    [string]$LauncherPath = $null,      # path to the tool's .ps1 entry point
    [string]$LauncherName = "Dev Tools" # shortcut display name
)
```

xampp-tools passes `Xampp-Tools.ps1` + "XAMPP Tools". docker-tools passes `Docker-Tools.ps1` + "Docker Tools". Both tools can register shortcuts.

---

### 0.5.8 Move: SRP module cluster

Software Restriction Policy modules in `xampp-tools/bin/modules/.private/` are Windows OS features, not XAMPP-related:

| Current | New location |
|---------|--------------|
| `Build-SoftwareRestrictionPolicy.ps1` | `common/modules/.private/Build-SoftwareRestrictionPolicy.ps1` |
| `Deploy-SoftwareRestrictionPolicy.ps1` | `common/modules/.private/Deploy-SoftwareRestrictionPolicy.ps1` |
| `Add-SiteToSrp.ps1` | `common/modules/.private/Add-SiteToSrp.ps1` |
| `Add-SrpPath.ps1` | `common/modules/.private/Add-SrpPath.ps1` |
| `Log-SrpIssue.ps1` | `common/modules/.private/Log-SrpIssue.ps1` |

Move as-is. Any path references to `xampp-tools` internals should be updated to resolve via `$script:DevToolsRoot` or `$script:ToolRoot`. SRP template at `xampp-tools/config/optimized/templates/softwarepolicy/` stays in xampp-tools (currently only consumed by xampp-tools' build pipeline) — revisit in Phase 5 if docker-tools needs it too.

---

### 0.5.9 Move: `common/modules/Fix-VSCodeTerminal.ps1`

Currently in `.private/`. VSCode terminal integration fix — not XAMPP-related. Move as-is.

---

### 0.5.10 Move: VSCode theme assets

```
xampp-tools/config/optimized/templates/vscode/  →  common/assets/vscode/
```

The `joehunter-dark.json` theme and `package.json` are personal, not XAMPP-related. Move the templates.

**Deploy mapping impact:** xampp-tools' `config.json` currently has deployMappings for these — either:
- **Option A:** keep the mapping entries in `xampp-tools/config/config.json` but update the source paths to point to `common/assets/vscode/`
- **Option B:** move the VSCode deploy logic to a new `common/modules/Deploy-VSCode-Theme.ps1` that both tools can invoke independently

Recommendation: Option B — the theme deploy has nothing to do with either tool's pipeline, it should be its own module.

---

### 0.5.11 Optional: Pipeline abstractions

These are lower-priority — can be done later if module duplication becomes painful:

```powershell
# common/Pipeline-Runner.ps1
function Invoke-StepPipeline {
    param([array]$Steps)   # @(@{Name=...; Action=[scriptblock]}, ...)
    $n = 1
    foreach ($step in $Steps) {
        Show-Step $n $step.Name "current"
        try {
            & $step.Action
            Show-Step $n $step.Name "done"
        } catch {
            Show-Step $n $step.Name "error"
            Write-Error2 $_.Exception.Message
            if ($step.Required -ne $false) { throw }
        }
        $n++
    }
}

function Invoke-Checklist {
    param([array]$Checks)  # @(@{Name=...; Check=[scriptblock]; OnFail=...}, ...)
    # Runs each check, collects results, reports pass/fail/warn per item
}
```

Use in `Redeploy.ps1` (both tools) and `Startup-Check.ps1` (both tools). Defer this until after Phase 3 when both tools' pipelines exist and duplication is visible.

---

### 0.5.12 Validation

- [ ] xampp-tools' `Build-Configs` now calls `Compile-Template` from `common/Template-Engine.ps1` — output byte-identical to before
- [ ] xampp-tools' hosts file writes now go through `Update-HostsBlock` with label `"xampp-tools"`
- [ ] xampp-tools' `Switch-PHP` reads version registry from `common/Php-Versions.ps1`
- [ ] `Install-Stripe-Package`, `Create-Shortcuts`, `Fix-VSCodeTerminal`, SRP cluster all discoverable from the xampp-tools menu (via common/modules discovery)
- [ ] VSCode theme deploy still works
- [ ] All xampp-tools modules smoke-tested — no regressions
- [ ] Commit: `refactor: extract shared engines and non-XAMPP modules to common/`

---

## Phase 1 — Docker Tools Foundation

**Goal:** `docker compose up` from `docker-tools/` starts nginx + php-fpm + mysql + pma, serving all sites from `vhosts.json`.

### 1.1 Create docker-tools directory structure

```
docker-tools/
├── Docker-Tools.ps1
├── Dockerfile
├── .gitignore
├── bin/
│   └── modules/
└── config/
    ├── config.json
    └── templates/
        ├── docker/
        ├── nginx/
        ├── php/
        └── mysql/
```

### 1.2 File: `docker-tools/.gitignore`

```gitignore
docker-compose.yml
config/dist/
data/
backups/
*.log
```

### 1.3 File: `docker-tools/Dockerfile`

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

### 1.4 File: `docker-tools/config/config.json`

```json
{
  "description": "Docker Tools configuration",

  "templates": {
    "sourceDir": "config\\templates",
    "distDir":   "config\\dist",
    "files": [
      { "template": "nginx\\nginx.conf.template", "output": "nginx\\nginx.conf" },
      { "template": "php\\php.ini.template",       "output": "php\\php.ini" },
      { "template": "mysql\\my.cnf.template",      "output": "mysql\\my.cnf" }
    ]
  },

  "vhosts": {
    "blocksTemplate": "config\\templates\\nginx\\vhost-blocks.template",
    "outputDir":      "config\\dist\\nginx\\conf.d"
  },

  "compose": {
    "baseTemplate": "config\\templates\\docker\\docker-compose.yml.template",
    "output":       "docker-compose.yml"
  },

  "ssl": {
    "certsDir": "config\\dist\\certs"
  },

  "backups": {
    "sourceDir": "config\\dist",
    "targetDir": "backups"
  }
}
```

### 1.5 Template: `docker-tools/config/templates/docker/docker-compose.yml.template`

See `docker-tools-plan.md` for full YAML. Contains these placeholders that `Build-Compose.ps1` injects:
- `{{DOCKER_ADMINER_SERVICE}}` — adminer service block or empty
- `{{DOCKER_POSTGRES_SERVICE}}` — postgres service block or empty
- `{{DOCKER_POSTGRES_VOLUME}}` — `postgres-data:` volume decl or empty
- `{{DOCKER_WWW_ROOT}}` — resolved www root (DOCKER_DOCUMENT_ROOT ?? XAMPP_DOCUMENT_ROOT)

### 1.6 Template: `docker-tools/config/templates/nginx/nginx.conf.template`

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
                    '$status $body_bytes_sent "$http_referer" "$http_user_agent"';

    sendfile on;
    keepalive_timeout 65;
    client_max_body_size {{PHP_UPLOAD_MAX_FILESIZE}};

    include /etc/nginx/conf.d/*.conf;
}
```

### 1.7 Template: `docker-tools/config/templates/nginx/vhost-blocks.template`

Block-per-type format (same bracket syntax as Apache). Full content in `docker-tools-plan.md`. Block names: `[laravel]`, `[react]`, `[wordpress]`, `[static]`, `[default]`.

### 1.8 Template: `docker-tools/config/templates/php/php.ini.template`

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

### 1.9 Template: `docker-tools/config/templates/mysql/my.cnf.template`

```ini
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci

innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2

max_connections = 100
max_allowed_packet = 64M

[client]
default-character-set = utf8mb4
```

### 1.10 File: `docker-tools/Docker-Tools.ps1` (entry point)

```powershell
<#
.SYNOPSIS
    Docker Tools - Main Entry Point
#>

$script:ToolName     = "Docker Tools"
$script:ToolRoot     = $PSScriptRoot
$script:DevToolsRoot = Split-Path $PSScriptRoot -Parent
$script:CommonDir    = Join-Path $script:DevToolsRoot "common"
$script:EnvFile      = Join-Path $script:DevToolsRoot ".env"
$script:VhostsFile   = Join-Path $script:DevToolsRoot "config\vhosts.json"
$script:BinDir       = Join-Path $PSScriptRoot "bin"
$script:ModulesDir   = Join-Path $script:BinDir "modules"
$script:DistDir      = Join-Path $PSScriptRoot "config\dist"
$script:ComposeFile  = Join-Path $PSScriptRoot "docker-compose.yml"

. (Join-Path $script:CommonDir "Common.ps1")
. (Join-Path $script:CommonDir "Service-Helpers.ps1")

function Get-AvailableModules {
    # Same pattern as Xampp-Tools.ps1 — discover shared + local, dedupe by Cmd
    $modules = @()
    $modules += Discover-ModulesIn (Join-Path $script:CommonDir "modules")
    $modules += Discover-ModulesIn $script:ModulesDir
    $seen = @{}
    $unique = @()
    foreach ($m in ($modules | Sort-Object { if ($_.IsLocal) { 0 } else { 1 } })) {
        if (-not $seen[$m.Cmd]) { $seen[$m.Cmd] = $true; $unique += $m }
    }
    return $unique | Sort-Object { $_.Order }
}

function Show-MainMenu {
    Show-Header
    # ... identical menu pattern to Xampp-Tools.ps1
}

Show-MainMenu
```

`Discover-ModulesIn` is a helper added to `common/Common.ps1` during Phase 0 — it reads metadata headers from each `.ps1` file in a directory.

### 1.11 Module: `docker-tools/bin/modules/Build-Compose.ps1` (CORE ENGINE)

**Metadata header:**
```powershell
# Name: Build Compose
# Description: Generate docker-compose.yml and nginx configs from templates
# Icon: 🔨
# Cmd: build
# Order: 2
```

**Core algorithm (15 steps):**

```
1.  Load config.json (docker-tools/config/config.json)
2.  Load shared .env (via Load-SharedEnv)
3.  Load shared vhosts.json (via Load-SharedVhosts)
4.  Resolve DOCKER_WWW_ROOT:
      $wwwRoot = $envVars['DOCKER_DOCUMENT_ROOT']
      if (-not $wwwRoot) { $wwwRoot = $envVars['XAMPP_DOCUMENT_ROOT'] }
5.  Validate: every vhost folder exists in $wwwRoot → collect warnings (don't abort)
6.  Detect duplicate domains → warn, continue
7.  Ensure dist/ subdirs exist (nginx/conf.d, php, mysql, postgres, certs)
8.  Compile base templates to dist/:
      For each entry in config.templates.files:
        Read template → substitute {{PLACEHOLDER}} with envVars → write to distDir
9.  Load vhost-blocks.template → extract blocks by regex [(\w+)](.*?)[/\1]
10. Per vhost:
      $serverName = $site.domain ?? ($site.folder + $envVars['VHOSTS_EXTENSION'])
      $port       = $site.port ?? 8081
      $blockType  = $site.type.ToLower()
      $block      = Get-VhostBlock $blockType (fallback: 'default')
      $conf       = Compile-Template $block @{
                      FOLDER = $site.folder
                      SERVER_NAME = $serverName
                      PORT = $port
                      VHOSTS_EXTENSION = $envVars['VHOSTS_EXTENSION']
                    }
      Write to dist/nginx/conf.d/$($site.folder).conf
11. Build conditional service blocks:
      $adminerBlock = if ($envVars['DOCKER_INCLUDE_ADMINER'] -eq 'true')
                        { Read-AdminerTemplate + substitute } else { "" }
      $postgresBlock = if ($envVars['DOCKER_INCLUDE_POSTGRES'] -eq 'true')
                        { Read-PostgresTemplate + substitute } else { "" }
      $postgresVolume = if ($envVars['DOCKER_INCLUDE_POSTGRES'] -eq 'true')
                          { "  postgres-data:" } else { "" }
12. Compile docker-compose.yml.template:
      $envVars['DOCKER_WWW_ROOT']         = $wwwRoot
      $envVars['DOCKER_ADMINER_SERVICE']  = $adminerBlock
      $envVars['DOCKER_POSTGRES_SERVICE'] = $postgresBlock
      $envVars['DOCKER_POSTGRES_VOLUME']  = $postgresVolume
      Write compiled → $script:ComposeFile (docker-tools/docker-compose.yml)
13. Update Windows hosts file:
      - Read C:\Windows\System32\drivers\etc\hosts
      - Remove existing "# docker-tools managed" block (if present)
      - Append new block with 127.0.0.1 entries for each vhost
      - Write atomically (requires admin)
      - If not admin: skip + warn
14. Build summary output:
      - N sites built
      - Optional services enabled (PMA, Adminer, Postgres)
      - Warnings (missing folders, duplicate domains)
15. Exit 0
```

**Dependencies from `common/`:**

```powershell
. (Join-Path $script:CommonDir "Template-Engine.ps1")   # Compile-Template, Get-NamedBlock, Invoke-TemplateBuild
. (Join-Path $script:CommonDir "Hosts-Helpers.ps1")     # Update-HostsBlock
. (Join-Path $script:CommonDir "Env-Validator.ps1")     # Assert-EnvKeys
. (Join-Path $script:CommonDir "Vhost-Validator.ps1")   # Test-VhostFolders, Find-DuplicateDomains, Get-VhostDomain
```

**Build-Compose flow using shared engines:**

```powershell
# Step 5: validate via shared helper
$missingFolders = Test-VhostFolders -Vhosts $vhosts -DocumentRoot $wwwRoot
foreach ($m in $missingFolders) { Write-Warning2 "Folder missing: $($m.folder)" }

# Step 6: duplicate detection via shared helper
$dupes = Find-DuplicateDomains -Vhosts $vhosts -Extension $envVars['VHOSTS_EXTENSION']
foreach ($d in $dupes) { Write-Warning2 "Duplicate domain: $($d.domain)" }

# Step 8: base template compilation via shared engine
$buildResult = Invoke-TemplateBuild `
    -SourceDir (Join-Path $toolRoot $config.templates.sourceDir) `
    -DistDir   (Join-Path $toolRoot $config.templates.distDir) `
    -Files     $config.templates.files `
    -Vars      $envVars

# Step 10: per-vhost nginx conf via shared engine
$blocksTemplate = Get-Content (Join-Path $toolRoot $config.vhosts.blocksTemplate) -Raw
foreach ($site in $vhosts) {
    $block = Get-NamedBlock -TemplateContent $blocksTemplate -BlockName $site.type -Fallback 'default'
    $vars = @{
        FOLDER           = $site.folder
        SERVER_NAME      = Get-VhostDomain -Vhost $site -Extension $envVars['VHOSTS_EXTENSION']
        PORT             = if ($site.port) { $site.port } else { 8081 }
        VHOSTS_EXTENSION = $envVars['VHOSTS_EXTENSION']
    }
    $conf = Compile-Template -Content $block -Vars $vars
    $outPath = Join-Path $toolRoot "$($config.vhosts.outputDir)\$($site.folder).conf"
    Set-Content -Path $outPath -Value $conf
}

# Step 13: hosts file via shared helper
$entries = $vhosts | ForEach-Object {
    $domain = Get-VhostDomain -Vhost $_ -Extension $envVars['VHOSTS_EXTENSION']
    "127.0.0.1  $domain"
}
Update-HostsBlock -MarkerLabel "docker-tools" -Entries $entries
```

No duplicated utility code — everything reused from `common/`.

### 1.12 Module: `docker-tools/bin/modules/Docker-Controller.ps1`

**Metadata:**
```powershell
# Name: Docker Controller
# Description: Start, stop, restart containers and view status
# Icon: 🐳
# Cmd: docker
# Order: 1
```

**Menu:**
```
1) Start All         → docker compose -f $script:ComposeFile up -d
2) Stop All          → docker compose -f $script:ComposeFile down
3) Restart All       → docker compose -f $script:ComposeFile restart
4) Status            → docker compose -f $script:ComposeFile ps
5) Open Shell        → prompt service → docker exec -it {container} sh
6) Rebuild Images    → docker compose -f $script:ComposeFile build --no-cache
0) Back
```

**Exported helpers** (added to `common/Service-Helpers.ps1` so other modules can call):

```powershell
function Invoke-DockerStart {
    docker compose -f $script:ComposeFile up -d
}
function Invoke-DockerStop {
    docker compose -f $script:ComposeFile down
}
function Invoke-DockerRestart {
    docker compose -f $script:ComposeFile restart
}
function Get-DockerStatus {
    $json = docker compose -f $script:ComposeFile ps --format json 2>&1
    if ($LASTEXITCODE -ne 0) { return @() }
    # Each line is a JSON object
    return ($json -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}
function Test-DockerRunning {
    docker info 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}
function Get-ContainerName {
    param([string]$Service, [hashtable]$EnvVars)
    $project = if ($EnvVars['DOCKER_COMPOSE_PROJECT']) { $EnvVars['DOCKER_COMPOSE_PROJECT'] } else { "dev" }
    return "$project-$Service"
}
```

### 1.13 Module: `docker-tools/bin/modules/Startup-Check.ps1`

**Metadata:**
```powershell
# Name: Startup Check
# Description: Validate environment before starting Docker services
# Icon: ✅
# Cmd: check
# Order: 3
```

**Checks (fail-fast or warn):**

| # | Check | Method | Failure action |
|---|-------|--------|---------------|
| 1 | Docker daemon running | `Test-DockerRunning` | Fatal — exit 1 |
| 2 | `.env` file exists | `Test-Path $envFile` | Fatal — exit 1 |
| 3 | Required env keys present | Validate key list | Fatal — exit 1 |
| 4 | `vhosts.json` parseable | `ConvertFrom-Json` | Fatal — exit 1 |
| 5 | XAMPP processes running | `Get-Process httpd, mysqld` | Prompt → `Invoke-XamppStop` |
| 6 | Ports 80/443/3306 free | `Test-NetConnection` | Warn |
| 7 | `docker-compose.yml` exists | `Test-Path` | Prompt to run `Build-Compose` |
| 8 | Compose config valid | `docker compose config` | Fatal — show output |
| 9 | `DOCKER_WWW_ROOT` exists | `Test-Path` | Warn |
| 10 | Hosts file entries | Parse + compare | Warn + offer Build |

Required env keys:
```
XAMPP_DOCUMENT_ROOT, XAMPP_SERVER_PORT, XAMPP_SSL_PORT,
MYSQL_PORT, MYSQL_ROOT_PASSWORD,
DOCKER_COMPOSE_PROJECT, DOCKER_NETWORK,
DOCKER_PHP_VERSION, DOCKER_MYSQL_VERSION
```

**XAMPP auto-stop flow (check #5):**
```powershell
$xamppRunning = (Get-Process -Name httpd, mysqld -ErrorAction SilentlyContinue)
if ($xamppRunning) {
    Write-Warning2 "XAMPP is running ($($xamppRunning.Name -join ', '))"
    if (Prompt-YesNo "Stop XAMPP before starting Docker?") {
        Invoke-XamppStop     # from common/Service-Helpers.ps1
        Start-Sleep -Seconds 3
    }
}
```

### 1.14 Phase 1 validation

```powershell
cd C:\dev-tools\docker-tools
.\Docker-Tools.ps1
```

- [ ] Menu loads with modules listed
- [ ] `check` runs all 10 checks, Docker-related pass after installing Docker Desktop
- [ ] `build` produces:
  - `docker-tools/docker-compose.yml` at root
  - `docker-tools/config/dist/nginx/nginx.conf`
  - `docker-tools/config/dist/nginx/conf.d/{folder}.conf` — one per vhost
  - `docker-tools/config/dist/php/php.ini`
  - `docker-tools/config/dist/mysql/my.cnf`
  - Windows hosts file updated with docker-tools managed block
- [ ] `docker` → Start All → containers run, `docker ps` shows `dev-nginx`, `dev-php`, `dev-mysql`, `dev-pma`
- [ ] Browser test: `http://api.idiliq.dev` → Laravel site loads
- [ ] Browser test: `http://localhost:8080` → phpMyAdmin loads, can log in as root

Commit: `feat: docker-tools foundation — build, controller, startup-check`

---

## Phase 2 — Database Operations

**Goal:** Backup, restore, create databases in the MySQL container. PostgreSQL support if enabled.

### 2.1 Refactor shared DB modules with executor injection

Move these from `xampp-tools/bin/modules/` to `common/modules/` and refactor to accept executor script blocks:

| Module | Parameters added |
|--------|------------------|
| `Backup-MySQL.ps1` | `$DbExecutor`, `$DbDumper`, `$BackupRoot` |
| `Restore-MySQL.ps1` | `$DbExecutor`, `$DbRestorer`, `$BackupRoot` |
| `Create-Database.ps1` | `$DbExecutor` |
| `Cleanup-MySQL.ps1` | `$CleanupStrategy` (dir vs volume) |

**Pattern:**
```powershell
param(
    [scriptblock]$DbExecutor = $null,    # executes a SQL statement, returns output
    [scriptblock]$DbDumper   = $null,    # dumps a db to a file path
    [string]$BackupRoot      = $null
)

# Default to XAMPP local execution if not provided — preserves backwards compat
if (-not $DbExecutor) {
    $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $moduleRoot "common\Common.ps1")
    $envVars = Load-SharedEnv
    $mysqlExe = Join-Path $envVars['XAMPP_ROOT_DIR'] "mysql\bin\mysql.exe"
    $mysqldumpExe = Join-Path $envVars['XAMPP_ROOT_DIR'] "mysql\bin\mysqldump.exe"
    $rootPwd = $envVars['MYSQL_ROOT_PASSWORD']

    $DbExecutor = { param($sql) & $mysqlExe -u root -p"$rootPwd" -e $sql }
    $DbDumper   = { param($db, $out) & $mysqldumpExe -u root -p"$rootPwd" $db | Out-File $out }
}

# ... UI flow uses $DbExecutor and $DbDumper ...
```

### 2.2 Docker-tools wrapper modules

docker-tools doesn't need new `Backup-MySQL.ps1` files — it has **thin wrapper modules** that invoke the shared common module with Docker executors:

`docker-tools/bin/modules/Backup-MySQL.ps1` (Docker wrapper, Hidden: true — only callable via `backup-db` which the shared module owns):

Actually a cleaner approach: put the Docker executor setup inside `Docker-Tools.ps1` launcher and inject it into shared modules via `$script:DbExecutor` globals.

**Chosen pattern:** launcher sets `$script:DbExecutor` script blocks before invoking any module. Shared modules read from `$script:` scope if parameters not passed.

```powershell
# Docker-Tools.ps1 — after env load, before menu
$envVars = Load-SharedEnv
$mysqlContainer = Get-ContainerName "mysql" $envVars
$rootPwd = $envVars['MYSQL_ROOT_PASSWORD']

$script:DbExecutor = {
    param($sql)
    docker exec $mysqlContainer mysql -u root -p"$rootPwd" -e $sql
}
$script:DbDumper = {
    param($db, $outPath)
    docker exec $mysqlContainer sh -c "mysqldump -u root -p'$rootPwd' $db | gzip" | Set-Content $outPath -AsByteStream
}
$script:DbRestorer = {
    param($db, $inPath)
    Get-Content $inPath -AsByteStream | docker exec -i $mysqlContainer sh -c "gunzip | mysql -u root -p'$rootPwd' $db"
}
```

Shared module reads via fallback chain: parameter → `$script:` scope → local default.

### 2.3 PostgreSQL support

New shared modules (if `DOCKER_INCLUDE_POSTGRES=true`):
- `common/modules/Backup-Postgres.ps1` — `pg_dump` via docker exec
- `common/modules/Restore-Postgres.ps1` — `psql` via docker exec
- Registered in Docker-Tools.ps1 only (xampp-tools doesn't ship Postgres)

### 2.4 Phase 2 validation

```powershell
> create-db test_db               # created in container
> backup-db test_db               # .sql.gz in backups/
> restore-db test_db backup.gz    # restored
> cleanup-db                      # orphaned volumes pruned
```

- [ ] xampp-tools backup/restore still works (backwards compat)
- [ ] docker-tools backup/restore uses docker exec
- [ ] Commit: `feat: shared DB modules with executor injection`

---

## Phase 3 — Operations

**Goal:** Full pipeline, log viewing, kill, services wrapper, config backups.

### 3.1 Module: `docker-tools/bin/modules/Redeploy.ps1`

```powershell
Show-Step 1 "Backup current configs"   current
& (Join-Path $common "modules\Backup-Configs.ps1") -SourceDir $distDir -TargetDir $backupDir
Show-Step 1 "Backup current configs"   done

Show-Step 2 "Build compose + configs"  current
& (Join-Path $modules "Build-Compose.ps1") -Silent
Show-Step 2 "Build compose + configs"  done

Show-Step 3 "Stop containers"          current
Invoke-DockerStop
Show-Step 3 "Stop containers"          done

Show-Step 4 "Start containers"         current
docker compose -f $script:ComposeFile up -d --force-recreate
Show-Step 4 "Start containers"         done

Show-Step 5 "Startup check"            current
& (Join-Path $modules "Startup-Check.ps1") -Silent
Show-Step 5 "Startup check"            done
```

### 3.2 Module: `docker-tools/bin/modules/View-Logs.ps1`

Wraps shared `common/modules/View-Logs.ps1` (which accepts `$LogSource` script block). Docker version:

```powershell
$script:LogSource = {
    param($service)
    docker compose -f $script:ComposeFile logs -f $service
}
```

Menu: All / nginx / php-fpm / mysql / phpmyadmin / adminer / postgres.

### 3.3 Module: `docker-tools/bin/modules/Kill-Services.ps1`

```powershell
docker compose -f $script:ComposeFile kill
Start-Sleep -Seconds 2
docker compose -f $script:ComposeFile rm -f
# Also clean dangling containers from project
docker ps -a --filter "label=com.docker.compose.project=$project" --format "{{.ID}}" | ForEach-Object {
    docker rm -f $_
}
```

### 3.4 Module: `docker-tools/bin/modules/Services.ps1`

Thin wrapper — 3-option menu (Start/Stop/Restart) calling `Invoke-DockerStart/Stop/Restart` from Service-Helpers.

### 3.5 Shared: `common/modules/Backup-Configs.ps1`

Parameterized — takes `-SourceDir` and `-TargetDir`. xampp-tools passes `config/optimized/dist/`, docker-tools passes `config/dist/` (plus copies `docker-compose.yml`).

### 3.6 Phase 3 validation

- [ ] `redeploy` completes all 5 steps without errors
- [ ] `logs` streams nginx logs, ctrl-c exits cleanly
- [ ] `kill` removes all project containers
- [ ] `services` → Stop All → all containers down
- [ ] `backup-cfg` creates timestamped backup folder

Commit: `feat: docker-tools operations — redeploy, logs, kill, services, backups`

---

## Phase 4 — Extended

**Goal:** SSL, PHP version switching, Docker installer, firewall, aliases.

### 4.1 Module: `docker-tools/bin/modules/Setup-SSL.ps1`

```powershell
# Pre-check: mkcert installed?
$mkcert = Get-Command mkcert -ErrorAction SilentlyContinue
if (-not $mkcert) {
    Write-Error2 "mkcert not found. Install via: scoop install mkcert"
    return
}

# Step 1: install local CA (one-time)
if (Prompt-YesNo "Run 'mkcert -install' to set up local CA? (admin required)") {
    mkcert -install
}

# Step 2: generate certs per SSL-enabled vhost
$certsDir = Join-Path $script:DistDir "certs"
New-Item -ItemType Directory -Path $certsDir -Force | Out-Null

foreach ($site in $vhosts | Where-Object { $_.ssl -eq $true }) {
    $domain = if ($site.domain) { $site.domain } else { $site.folder + $envVars['VHOSTS_EXTENSION'] }
    $certFile = Join-Path $certsDir "$($site.folder).pem"
    $keyFile = Join-Path $certsDir "$($site.folder)-key.pem"
    mkcert -cert-file $certFile -key-file $keyFile $domain
}

Write-Success "Run 'redeploy' to apply SSL to nginx."
```

Update `vhost-blocks.template` to include a 443 server block when `ssl: true`.

### 4.2 Module: `docker-tools/bin/modules/Switch-PHP.ps1`

```powershell
# 1. Show current DOCKER_PHP_VERSION
# 2. List available versions (7.4, 8.0, 8.1, 8.2, 8.3, 8.4 — same as xampp-tools registry)
# 3. Prompt selection
# 4. Update DOCKER_PHP_VERSION in $script:EnvFile
# 5. Prompt: rebuild now?
# 6. If yes: docker compose build --no-cache php-fpm
# 7. Prompt: restart php-fpm?
# 8. If yes: docker compose restart php-fpm
```

### 4.3 Module: `docker-tools/bin/modules/Install-Docker.ps1`

```powershell
# 1. Check if docker already installed: docker --version
# 2. If yes: show version + link to update
# 3. If no:
#    a. Detect Windows version
#    b. Download Docker Desktop installer:
#       $url = "https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe"
#    c. Run installer: Start-Process -Wait -ArgumentList "install --quiet"
#    d. Verify post-install
# 4. Check mkcert:
#    a. If Scoop available: scoop install mkcert
#    b. Else: download to C:\Windows\System32\mkcert.exe
# 5. Print post-install checklist
```

### 4.4 Module: `common/modules/Firewall.ps1` (refactored shared)

Accepts `-Ports` parameter with hashtable of name/port/protocol entries. xampp-tools passes the XAMPP port list, docker-tools passes the Docker port list.

### 4.5 Module: `common/modules/Alias.ps1`

Already identical between tools. Use `$script:ToolRoot` to place aliases in the right bin folder. No functional changes needed beyond moving.

### 4.6 Phase 4 validation

- [ ] `ssl` generates certs for all `ssl: true` vhosts, browser trusts them
- [ ] `php` updates .env, rebuilds image, containers restart
- [ ] `install` (fresh Windows VM test) downloads and installs Docker Desktop
- [ ] `firewall` creates inbound block rules for Docker ports
- [ ] `alias` creates `.bat` aliases in `docker-tools/bin/aliases/`

Commit: `feat: docker-tools extended — ssl, php, install, firewall, alias`

---

## Phase 5 — Polish

- [ ] Update `dev-tools.code-workspace` to add Docker Tools folder entry
- [ ] Update root `README.md` describing both tools
- [ ] Add `docker-tools/README.md` with quickstart
- [ ] Remove deprecated per-tool `.env.example` and `vhosts.json` files from `xampp-tools/`
- [ ] Verify all shared modules have backwards-compat default executors (xampp-tools still works when invoked directly)
- [ ] Smoke test: fresh clone → `.\Xampp-Tools.ps1` and `.\Docker-Tools.ps1` both work

---

## File-by-File Build Order

When working through phases, build files in this order to minimize broken states:

**Phase 0 — Core Migration:**
1. Create `common/` and top-level `config/` directories
2. Move `.env.example`, `.env`, `vhosts.json`, `signature-lg.txt` to their shared locations
3. Create `common/Common.ps1` (split shared helpers out of xampp-tools/bin/Common.ps1)
4. Move `common/Service-Helpers.ps1`
5. Update `xampp-tools/Xampp-Tools.ps1` launcher to use new paths
6. Update xampp-tools modules that referenced moved files
7. Smoke test every xampp-tools module end-to-end
8. Commit: `refactor: extract shared core to dev-tools/common`

**Phase 0.5 — Shared Utilities & Engines:**
1. Create `common/Template-Engine.ps1` — move `{{PLACEHOLDER}}` + named-block logic out of `Build-Configs.ps1`
2. Create `common/Hosts-Helpers.ps1` — move managed-block hosts writer
3. Create `common/Env-Validator.ps1` — extract required-key validation
4. Create `common/Vhost-Validator.ps1` — extract folder/duplicate validation
5. Create `common/Php-Versions.ps1` — move version registry data out of `Switch-PHP.ps1`
6. Move `Install-Stripe-Package.ps1` → `common/modules/`
7. Move `Create-Shortcuts.ps1` → `common/modules/` + add `-LauncherPath` parameter
8. Move SRP cluster → `common/modules/.private/`
9. Move `Fix-VSCodeTerminal.ps1` → `common/modules/`
10. Move VSCode theme templates → `common/assets/vscode/`; create `common/modules/Deploy-VSCode-Theme.ps1`
11. Refactor xampp-tools' `Build-Configs.ps1` to consume shared engines (zero behaviour change — output byte-identical)
12. Refactor xampp-tools' `Switch-PHP.ps1` to read registry from `common/Php-Versions.ps1`
13. Smoke test xampp-tools — all modules still work
14. Commit: `refactor: extract shared engines and non-XAMPP modules to common/`

**Phase 1 — Docker Tools Foundation:**
1. Create `docker-tools/` directory tree
2. Write `docker-tools/.gitignore` and `Dockerfile`
3. Write all templates (docker-compose, nginx, php, mysql)
4. Write `docker-tools/config/config.json`
5. Write `docker-tools/Docker-Tools.ps1` launcher
6. Write `Build-Compose.ps1` — consuming Template-Engine, Hosts-Helpers, Vhost-Validator, Env-Validator
7. Write `Docker-Controller.ps1` — test start/stop
8. Write `Startup-Check.ps1` — uses `Assert-EnvKeys` from Env-Validator
9. End-to-end: build → check → start → open browser
10. Commit: `feat: docker-tools foundation`

**Phase 2 — Database Operations:**
1. Refactor shared DB modules (`Backup-MySQL`, `Restore-MySQL`, `Create-Database`, `Cleanup-MySQL`) with executor injection — move to `common/modules/`
2. Wire xampp-tools default executors (local mysql.exe) for backwards compat
3. Wire docker-tools executors in `Docker-Tools.ps1` (`docker exec`)
4. Add PostgreSQL modules (`common/modules/Backup-Postgres.ps1`, `Restore-Postgres.ps1`) — docker-tools only
5. Smoke test DB ops in both tools
6. Commit

**Phase 3 — Operations:**
1. Move/refactor `Backup-Configs.ps1` → `common/modules/` with `-SourceDir`/`-TargetDir` params
2. Move/refactor `View-Logs.ps1` → `common/modules/` with `$LogSource` script block
3. Write `docker-tools/bin/modules/Redeploy.ps1` — docker pipeline
4. Write `docker-tools/bin/modules/Kill-Services.ps1`
5. Write `docker-tools/bin/modules/Services.ps1`
6. Wire docker-tools' `$script:LogSource` in launcher
7. Smoke test both tools
8. Commit

**Phase 4 — Extended:**
1. Refactor `Firewall.ps1` → `common/modules/` with `-Ports` param
2. Move `Alias.ps1` → `common/modules/`
3. Move `Create-Ascii.ps1` → `common/modules/`
4. Write `docker-tools/bin/modules/Setup-SSL.ps1` (mkcert)
5. Write `docker-tools/bin/modules/Switch-PHP.ps1` (rebuild image, reads `common/Php-Versions.ps1`)
6. Write `docker-tools/bin/modules/Install-Docker.ps1`
7. Commit

**Phase 5 — Polish:**
1. Update `dev-tools.code-workspace` with Docker Tools folder entries
2. Write/update root `README.md`
3. Write `docker-tools/README.md` quickstart
4. Remove now-dead `.env.example` and `vhosts.json` from `xampp-tools/` root
5. Fresh-clone smoke test — both tools work from zero
6. Commit

---

## Common Module Inventory (after all phases)

For quick reference — what lives where when done:

**`common/` (loaded by both tools):**
```
common/
├── Common.ps1                  # header, logging, env loading, prompts, path helpers
├── Service-Helpers.ps1         # Invoke-XamppStart/Stop, Invoke-DockerStart/Stop, Get-*Status
├── Template-Engine.ps1         # Compile-Template, Get-NamedBlock, Invoke-TemplateBuild
├── Hosts-Helpers.ps1           # Update-HostsBlock, Remove-HostsBlock, Test-HostsEntriesPresent
├── Env-Validator.ps1           # Test-RequiredEnvKeys, Assert-EnvKeys
├── Vhost-Validator.ps1         # Test-VhostFolders, Find-DuplicateDomains, Get-VhostDomain
├── Php-Versions.ps1            # $script:PhpVersions registry
├── Pipeline-Runner.ps1         # (optional, Phase 5) Invoke-StepPipeline, Invoke-Checklist
├── assets/
│   ├── signature-lg.txt
│   └── vscode/
│       ├── joehunter-dark.json
│       └── package.json
└── modules/
    ├── Alias.ps1                       # shared
    ├── Create-Ascii.ps1                # shared
    ├── Firewall.ps1                    # shared (-Ports param)
    ├── Backup-MySQL.ps1                # shared (executor injection)
    ├── Restore-MySQL.ps1               # shared (executor injection)
    ├── Create-Database.ps1             # shared (executor injection)
    ├── Cleanup-MySQL.ps1               # shared (strategy param)
    ├── View-Logs.ps1                   # shared ($LogSource)
    ├── Backup-Configs.ps1              # shared (source/target params)
    ├── Install-Stripe-Package.ps1      # shared
    ├── Create-Shortcuts.ps1            # shared (-LauncherPath)
    ├── Fix-VSCodeTerminal.ps1          # shared
    ├── Deploy-VSCode-Theme.ps1         # shared
    └── .private/
        ├── Build-SoftwareRestrictionPolicy.ps1
        ├── Deploy-SoftwareRestrictionPolicy.ps1
        ├── Add-SiteToSrp.ps1
        ├── Add-SrpPath.ps1
        └── Log-SrpIssue.ps1
```

**`xampp-tools/bin/modules/` (xampp-only):**
```
Build-Configs.ps1, Deploy-Configs.ps1, Deploy-VHosts.ps1,
Setup-MySQL.ps1, Setup-SSL.ps1 (OpenSSL), Switch-PHP.ps1 (install zip),
Services.ps1, Kill-Services.ps1, Startup-Check.ps1, Redeploy.ps1,
Xampp-Controller.ps1
```

**`docker-tools/bin/modules/` (docker-only):**
```
Build-Compose.ps1, Docker-Controller.ps1, Startup-Check.ps1,
Setup-SSL.ps1 (mkcert), Switch-PHP.ps1 (rebuild image),
Install-Docker.ps1, Services.ps1, Kill-Services.ps1, Redeploy.ps1
```

Note `Startup-Check.ps1`, `Services.ps1`, `Kill-Services.ps1`, `Redeploy.ps1`, `Setup-SSL.ps1`, `Switch-PHP.ps1` exist in BOTH tools' `bin/modules/` with the same `Cmd:` — discovery dedupe logic prefers local over shared.

---

## Conventions Recap

Every module in either tool follows these rules:

1. **Metadata header** — `# Name:`, `# Description:`, `# Icon:`, `# Cmd:`, `# Order:`, `# Hidden:`
2. **First line after header** — dot-source `common/Common.ps1` via `$script:CommonDir` (fallback: walk up `$PSScriptRoot`)
3. **Env access** — always via `Load-SharedEnv`, never hardcoded paths
4. **Vhost access** — always via `Load-SharedVhosts`
5. **Path helpers** — `Get-DevToolsRoot`, `Get-SharedEnvPath`, `Get-SharedVhostsPath`, `Get-ComposePath` (docker-tools), `Get-ContainerName`
6. **Show-Header** — called once at module start
7. **Emoji step indicators** — `Show-Step`, `Write-Info`, `Write-Success`, `Write-Error2`, `Write-Warning2`
8. **Interactive prompts** — `Prompt-YesNo`, `Prompt-Continue`
9. **Executor injection for shared modules** — parameter with `$script:` fallback with local default (for xampp-tools backwards compat)
10. **Exit codes** — `exit 0` success, `exit 1` fatal error
