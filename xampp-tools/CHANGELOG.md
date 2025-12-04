# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Redeploy Pipeline** - New `Redeploy.ps1` module that orchestrates complete deployment cycle:
  - Step 1: Backup current configs for safe rollback
  - Step 2: Build all configs from templates
  - Step 3: Deploy base configs (httpd.conf, php.ini, etc.)
  - Step 4: Deploy VHosts and hosts file
  - Step 5: Restart Apache and MySQL servers
  - Interactive prompt for catching-all VirtualHost type selection (Basic/Secure)

- **Dual VirtualHost Catch-All Blocks** - Two configurations available in `vhost-blocks.template`:
  - **Basic** - Simple catch-all with minimal configuration (15 lines)
  - **Secure** - Full-featured with file blocking, upload protection, caching, compression (120 lines)

- **Template Timestamps** - All 8 templates now include `{{TIMESTAMP}}` placeholder for verification:
  - `httpd.conf.template`
  - `httpd-xampp.conf.template`
  - `vhost-blocks.template`
  - `php.ini.template`
  - `php.ini.min.template`
  - `my.ini.template`
  - `config.inc.php.template`
  - `hosts.template`

- **Dashboard Templates** - New root-level dashboard files:
  - `index.php` - XAMPP environment dashboard with VHosts quick access
  - `phpinfo.php` - PHP information page with formatted display

- **Root .htaccess Template** - Security and performance configuration for document root

- **Interactive Build Configuration** - Build-Configs now prompts user to choose catch-all type:
  - Option 1: Basic (simple, minimal security)
  - Option 2: Secure (with file blocking & upload protection)

- **Advanced MySQL Setup** - Enhanced Setup-MySQL.ps1 with:
  - Automatic MySQL startup if not running
  - Force password reset via skip-grant-tables mode
  - Better error handling and recovery options
  - Password reset after configuration

### Changed
- **Deploy-VHosts.ps1** - Added `-Force` parameter support for non-interactive deployment
  - Skips confirmation prompt when `-Force` flag is used
  - Enables seamless integration with Redeploy pipeline

- **Build-Configs.ps1** - Added parameter support:
  - New `-CatchAllType` parameter accepts "Default", "Default-Secure", "Basic", or "Secure"
  - Only prompts user for choice if parameter not provided
  - Defaults to Secure catch-all if neither parameter nor user input provided

- **Redeploy.ps1** - Passes user's catch-all choice to Build-Configs via `-CatchAllType` parameter

- **Deploy-Configs.ps1** - Fixed environment variable substitution in deployment paths
  - Now supports `{{VARIABLE_NAME}}` placeholders in target paths
  - Properly handles both absolute and relative paths

- **vhost-blocks.template** - Enhanced with:
  - Two catch-all options instead of one default
  - Fixed logging paths for Static PHP ({{FOLDER}} instead of {{NAME}})
  - Added "default" app type switch case

- **PMA Variable Names** - Updated .env.example:
  - Changed `PMA_CONTROLUSER` → `PMA_USER`
  - Changed `PMA_CONTROLPASS` → `PMA_PASSWORD`

- **config.json** - Added root dashboard files to template mappings:
  - `root/index.php` → output in dist
  - `root/phpinfo.php` → output in dist

### Fixed
- **VirtualHost Selection Bug** - Catch-all VirtualHost now respects user's choice:
  - Previously defaulted to Basic in non-interactive mode
  - Now correctly passes Secure selection through entire pipeline
  - Default is now Secure instead of Basic

- **Non-Interactive Deployment** - Redeploy pipeline now completes without prompts:
  - Deploy-VHosts no longer blocks on confirmation when called from Redeploy
  - Enables full automation of deployment cycle

- **Environment Variable Handling** - Build-Configs now properly:
  - Strips outer quotes from .env values
  - Escapes special characters in PHP config files
  - Handles {{VAR}} placeholders consistently

### Removed
- Removed hard-coded default "Default" (Basic) catch-all in favor of configurable "Default-Secure"

### Security
- **Secure VirtualHost Block** includes:
  - File access blocking (sensitive extensions: .env, .gitignore, .lock, .sql, etc.)
  - Config directory blocking (config/, .git/, .env files)
  - Composer/package file blocking
  - Dotfile blocking
  - Upload directory PHP execution prevention
  - ETag removal for better caching

### Performance
- **Secure VirtualHost Block** adds:
  - Cache expiration headers for static assets (1 year for CSS/JS, 1 month for images)
  - GZIP compression for text, CSS, JavaScript, JSON, XML
  - ETag optimization
  - Short cache for HTML (1 hour)
  - Default cache 2 weeks

## [Previous Versions]

See git history for earlier changes.
