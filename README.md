# XAMPP Tools - PowerShell XAMPP Management Toolkit for Windows

**Automate your XAMPP local development environment.** Apache virtual hosts generator, MySQL database backup & restore, phpMyAdmin configuration, Windows hosts file manager, and firewall security - all driven by simple JSON configs and environment variables. Built for Laravel, WordPress, React, and PHP developers on Windows.

[![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white)](https://docs.microsoft.com/powershell/)
[![XAMPP](https://img.shields.io/badge/XAMPP-Apache%20%7C%20MySQL%20%7C%20PHP-FB7A24?logo=xampp)](https://www.apachefriends.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **"Slow is Smooth, Smooth is Fast"**

**Perfect for:** Laravel, WordPress, React, and PHP developers who need a streamlined local development workflow.

Built by [Joe Hunter](https://github.com/joehunterdev) • [joe.hunter.dev@gmail.com](mailto:joe.hunter.dev@gmail.com)

---

## ✨ Features

- 🌐 **Virtual Hosts Manager** - Auto-generate Apache vhosts from JSON config
- 🗄️ **MySQL Backup & Restore** - Automated database backups with gzip compression
- 📦 **Config Templates** - Build httpd.conf, php.ini, my.ini from templates with environment variables
- 🛡️ **Firewall Security** - Block external access to XAMPP development ports
- 🔄 **Service Control** - Start/stop Apache and MySQL with one command
- 📋 **Hosts File Manager** - Auto-update Windows hosts file for local domains
- ⚡ **Modular Design** - Drop-in PowerShell modules, auto-discovered menu

---

## 💻 Requirements

- **Windows 10/11** with PowerShell 5.1+
- **XAMPP** installed (default `C:\xampp`, configurable)
- **Administrator privileges** for service management, firewall rules, and hosts file deployment

---

## 🚀 Quick Start Installation

### Step 1: Clone & Setup Environment

```powershell
# Clone the repo to dev-tools
cd C:\dev-tools
git clone https://github.com/joehunterdev/xampp-tools.git
cd xampp-tools

# Copy environment template
Copy-Item .env.example .env
```

Edit `.env` with your settings:

```ini
# Key settings to configure:
XAMPP_ROOT_DIR=C:\xampp
XAMPP_DOCUMENT_ROOT=C:\www
XAMPP_SERVER_PORT=8080
MYSQL_ROOT_PASSWORD=your_secure_password
PMA_USER=pma
PMA_PASSWORD=your_pma_password
VHOSTS_EXTENSION=.local
```

### Step 2: Configure Apache Virtual Hosts

```powershell
# Copy vhosts template
Copy-Item config\vhosts.json.example config\vhosts.json
```

Edit `config\vhosts.json` to define your local sites:

```json
{
  "vhosts": [
    {
      "name": "My Laravel App",
      "folder": "my-laravel-app",
      "type": "laravel"
    },
    {
      "name": "My React App", 
      "folder": "my-react-app",
      "type": "react"
    },
    {
      "name": "My WordPress Site",
      "folder": "my-wordpress",
      "type": "wordpress"
    }
  ]
}
```

**Supported project types:** `laravel`, `react`, `wordpress`, `static`

Server names are auto-generated from folder name + `VHOSTS_EXTENSION`:
- `my-laravel-app` → `my-laravel-app.local`
- `my-wordpress` → `my-wordpress.local`

### Step 3: Run XAMPP Tools

```powershell
# Run as Administrator
.\xampp.ps1
```

### Step 4: Initial Setup Workflow

Follow these steps in order on first run:

| Order | Command | Description |
|-------|---------|-------------|
| 1 | `check` | Validate environment & dependencies |
| 2 | `services` | Start Apache & MySQL |
| 3 | `setup-mysql` | Configure MySQL users (if connection fails) |
| 4 | `backup-mysql` | Backup your databases |
| 5 | `build-configs` | Generate configs from templates |
| 6 | `deploy-configs` | Deploy configs to XAMPP |
| 7 | `deploy-vhosts` | Deploy vhosts + hosts file |

After initial setup, you'll mainly use:
- `services` - Start/stop XAMPP
- `deploy-vhosts` - When adding new sites
- `backup-mysql` - Regular database backups

---

## 📋 Available Commands

### Core Workflow (Local Development)
| Command | Description |
|---------|-------------|
| `check` | Validate XAMPP environment, paths, and dependencies |
| `services` | Start/Stop/Restart Apache and MySQL services |
| `setup-mysql` | Configure MySQL root password and phpMyAdmin user |
| `backup-mysql` | Backup all MySQL/MariaDB databases |
| `build-configs` | Build Apache, PHP, MySQL configs from templates |
| `deploy-configs` | Deploy configuration files to XAMPP |
| `deploy-vhosts` | Deploy Apache virtual hosts + Windows hosts file |

### Utility Commands
| Command | Description |
|---------|-------------|
| `firewall` | Manage Windows Firewall rules for XAMPP port security |
| `backup-configs` | Backup current XAMPP configuration files |
| `restore-mysql` | Restore MySQL databases from backup |
| `cleanup-mysql` | Remove orphaned MySQL database folders |

---

## 📁 Project Structure

```
xampp-tools/
├── xampp.ps1                    # Main entry point
├── .env                         # Your environment config (gitignored)
├── .env.example                 # Environment template
├── bin/
│   ├── Common.ps1               # Shared helper functions
│   ├── signature-lg.txt         # ASCII art header
│   └── modules/                 # Auto-discovered menu modules
│       ├── Startup-Check.ps1    # Environment validation
│       ├── Services.ps1         # Apache & MySQL control
│       ├── Firewall.ps1         # Windows Firewall manager
│       ├── Setup-MySQL.ps1      # MySQL user setup
│       ├── Backup-MySQL.ps1     # Database backup
│       ├── Backup-Configs.ps1   # Config file backup
│       ├── Build-Configs.ps1    # Template compiler
│       ├── Deploy-Configs.ps1   # Config deployment
│       └── Deploy-VHosts.ps1    # VHosts deployment
├── config/
│   ├── config.json              # File mappings & paths
│   ├── vhosts.json              # Your site definitions
│   └── optimized/
│       ├── templates/           # Config templates with {{PLACEHOLDERS}}
│       ├── dist/                # Built configs (generated)
│       └── backups/             # Config backups
└── .docs/                       # Documentation
```

---

## ⚙️ Configuration Files

### `.env` - Environment Variables

All paths, ports, and credentials are configured here:

```ini
# XAMPP Paths
XAMPP_ROOT_DIR=C:\xampp
XAMPP_DOCUMENT_ROOT=C:\www
XAMPP_SERVER_PORT=8080
XAMPP_SSL_PORT=443

# MySQL
MYSQL_ROOT_PASSWORD=your_password
MYSQL_PORT=3306

# phpMyAdmin
PMA_USER=pma
PMA_PASSWORD=your_pma_password
PMA_AUTH_TYPE=config

# VHosts
VHOSTS_EXTENSION=.local
```

### `config/vhosts.json` - Site Definitions

Define your local development sites:

```json
{
  "vhosts": [
    {
      "name": "Display Name",
      "folder": "folder-name",
      "type": "laravel|react|wordpress|static",
      "serverName": "custom.domain.local",  // Optional - overrides auto-generated
      "https": false                         // Optional - enable SSL
    }
  ]
}
```

### `config/config.json` - System Configuration

Maps templates to outputs and defines backup/deploy paths. Usually doesn't need editing.

---

## 🔒 Security Best Practices for Local XAMPP

### Windows Firewall Protection

The `firewall` command creates Windows Firewall rules to block external network access to XAMPP ports:

```
┌─────────────────────────────────────────┐
│  Before: Ports exposed to network       │
│  After:  Only localhost can connect     │
└─────────────────────────────────────────┘
```

### Best Practices

1. **Never use default passwords** - Configure strong passwords in `.env`
2. **Run firewall security** - Block external access to development ports
3. **Keep `.env` private** - It's gitignored by default
4. **Regular backups** - Use `backup-mysql` before major changes

---

## �️ Troubleshooting

### "MySQL connection failed"
1. Run `services` to ensure MySQL is running
2. Run `setup-mysql` to configure users
3. Check `MYSQL_ROOT_PASSWORD` in `.env`

### "Apache won't start"
1. Check if port 8080 is in use: `netstat -ano | findstr :8080`
2. Verify `httpd.conf` syntax: `C:\xampp\apache\bin\httpd.exe -t`
3. Check Apache error log: `C:\xampp\apache\logs\error.log`

### "Site not loading"
1. Check hosts file has the entry: `C:\Windows\System32\drivers\etc\hosts`
2. Verify folder exists in `XAMPP_DOCUMENT_ROOT`
3. Run `deploy-vhosts` to regenerate

### "Permission denied"
- Run PowerShell as Administrator
- Required for: services, firewall, hosts file deployment

---

## 📝 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

Contributions welcome! Please read the contribution guidelines first.

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

## 🔗 Related Projects & Resources

- [XAMPP Official](https://www.apachefriends.org/) - Apache + MariaDB + PHP + Perl

---

## 📚 Keywords

`xampp` `xampp-tools` `xampp-manager` `apache-virtual-hosts` `mysql-backup` `php-development` `local-development` `windows-development` `powershell-scripts` `laravel-local` `wordpress-local` `web-development` `dev-tools` `httpd-vhosts` `hosts-file-manager`

---

**Made with ☕ by [Joe Hunter](https://github.com/joehunterdev)**
