Nice—this is a clean direction. PowerShell + Docker + no “magic workspaces” is actually a really solid philosophy.

Let’s define **clear instructions you can reuse (for yourself + Claude + future you)** 👇

---

# 🧠 Dev Philosophy (your stack)

```text id="p6k2zr"
This project uses a Windows-first development environment.

Core principles:
- PowerShell is the primary interface
- Docker is the runtime for all services
- No GUI tools (no XAMPP, no workspace managers)
- No hidden environments or abstractions
- Everything is explicit, scriptable, and reproducible

The goal is to:
- Run all services via Docker
- Control everything through a single PowerShell CLI script (dev.ps1)
- Keep setup minimal and transparent
```

---

# ⚙️ Environment Assumptions

```text id="z0j4o1"
Environment:
- OS: Windows 10/11
- Shell: PowerShell (not bash unless explicitly stated)
- Docker Desktop is installed and running
- Project runs entirely via docker-compose

Rules:
- Always provide PowerShell-compatible commands
- Avoid Linux/macOS-specific instructions unless asked
- Do not rely on WSL
- Do not suggest XAMPP, WAMP, or similar tools
```

---

# 🔧 CLI Tooling Rules

```text id="9kt3bn"
All environment actions must go through dev.ps1

Valid commands:
- dev up        → start containers
- dev down      → stop containers
- dev restart   → restart containers
- dev shell     → open shell in app container
- dev logs      → view logs
- dev php       → run PHP commands inside container
- dev composer  → run composer inside container

Rules:
- Do not call docker or docker-compose directly unless necessary
- Always wrap commands via dev.ps1
- Keep commands simple and predictable
```

---

# 🐳 Docker Rules

```text id="u4c2hf"
Docker usage:
- Use docker-compose.yml as the single source of truth
- Services should include:
  - app (PHP or runtime)
  - web (nginx or apache)
  - db (MySQL or MariaDB)

Rules:
- No global installs on host machine
- All dependencies must live inside containers
- Use .env for configuration (ports, credentials, etc.)
```

---

# 📁 Project Structure

```text id="x7q3rm"
Project structure:

/docker
/docker-compose.yml
/dev.ps1
/.env
/src (application code)

Rules:
- Keep Docker config separate from app code
- Keep scripts in root or /scripts
- Avoid deeply nested or “magic” structures
```

---

# 🚫 Explicit Anti-Patterns (you hate these)

```text id="q8m1vy"
Do NOT:
- Suggest XAMPP, WAMP, or bundled stacks
- Suggest GUI-based dev environments
- Suggest “workspace” abstractions or hidden environments
- Hide commands behind tools that obscure Docker
- Assume Linux paths or tools
```

---

# ⚡ Example Usage (how everything should feel)

```powershell id="x9d2pw"
dev up
dev php artisan migrate
dev composer install
dev logs
dev down
```

👉 That’s your entire dev experience. Clean.

---

# 💡 Optional: Add personality constraints (makes Claude better)

```text id="c2f7az"
When suggesting solutions:
- Prefer simple over clever
- Prefer explicit over abstract
- Avoid unnecessary tools or layers
- Explain what each command actually does
```

---

# 🧭 Big Picture (this is the important part)

What you’re building is:

> a **transparent, script-first dev environment**

Not:

* a framework
* a platform
* a “workspace system”

That’s why it’ll stay maintainable.

---

# 💬 Honest take

Your approach is basically:

* Docker (industry standard)
* PowerShell (native control)
* No abstraction layers (clarity)

👉 That combo is underrated but extremely effective

---

If you want next step, I can:

* turn this into a proper `README.md`
* build a production-ready `dev.ps1`
* or design your docker-compose stack (PHP 8.3 + MySQL + nginx)

Just tell me 👍
