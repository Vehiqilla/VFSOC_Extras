# VFSOC – Local Deployment Guide for Developers

This guide walks a developer from a clean Windows machine through cloning the
VFSOC repositories, configuring a local environment, and ending with three
working desktop shortcuts:

- **VFSOC Ingestion** – the WPF ingestion control app
- **VFSOC Main Dashboard** – the Next.js SIEM at `http://localhost:3000`
- **VFSOC Admin** – the Next.js admin app at `http://localhost:3001`

Everything below has been validated against the current `main` branch of every
VFSOC repo. When something doesn't behave the way the guide describes, that is
a bug in the guide or in setup – please file an issue.

---

## 1. Prerequisites

Install the following tools first (sizes are approximate). Versions in
parentheses are the minimums known to work; newer versions are fine.

| Tool | Version | Notes |
|------|---------|-------|
| Windows 10 / 11 (64-bit) | – | All scripts are PowerShell-based |
| **Git for Windows** | 2.40+ | Provides `git` and Git Bash |
| **Node.js (LTS)** | 18.17+ or 20.x | `node -v` and `npm -v` must work in PowerShell |
| **.NET SDK** | 8.0+ | Required to build the WPF ingestion app |
| **Docker Desktop** | 4.20+ | Used for PostgreSQL and OpenSearch infra |
| **Python** | 3.10+ | Only needed if you want to run the log generator |
| **PowerShell** | 7+ recommended | Windows PowerShell 5.1 also works |

> Open a fresh PowerShell window after installing so the new tools land on
> `PATH`. Verify with: `git --version; node -v; dotnet --version; docker --version`.

### 1.1 GitHub access

The repositories live under the `Vehiqilla` organization. Confirm SSH access:

```powershell
ssh -T git@github.com
```

If you prefer HTTPS, configure a [GitHub Personal Access Token (PAT)](https://github.com/settings/tokens)
and let `git credential-manager` cache it the first time you `git push`.

---

## 2. Clone the repositories

VFSOC is a **split-repo** project. `VFSOC_Extras` is the orchestrator and is a
**sibling** of the application repos, not a parent. All five repos must live
under the same folder:

```
C:\Users\<you>\Desktop\VFSOC\
├── VFSOC_Extras\           # orchestration scripts, shortcuts, infra compose
├── VFSOC_Admin\            # Next.js admin app (port 3001)
├── VFSOC-SIEM\             # Next.js main dashboard (port 3000)
├── VFSOC-Ingestion\        # WPF .NET ingestion control app
└── VFSOC-log_generation\   # optional Python connector log generator
```

Clone them all in one shot:

```powershell
mkdir C:\Users\$env:USERNAME\Desktop\VFSOC
cd    C:\Users\$env:USERNAME\Desktop\VFSOC

git clone git@github.com:Vehiqilla/VFSOC_Extras.git
git clone git@github.com:Vehiqilla/VFSOC_Admin.git
git clone git@github.com:Vehiqilla/VFSOC-SIEM.git
git clone git@github.com:Vehiqilla/VFSOC-Ingestion.git
git clone git@github.com:Vehiqilla/VFSOC-log_generation.git   # optional
```

> If you cloned `VFSOC_Extras` somewhere different, edit
> `VFSOC_Extras\vfsoc.config.json` and set `"projects_root"` to the absolute
> path of the folder containing the four app repos.

---

## 3. Start infrastructure (PostgreSQL + OpenSearch)

VFSOC needs a shared PostgreSQL 16 database (used by Admin and SIEM) and an
OpenSearch cluster (used by SIEM for log search). Both are provided by a
single Docker Compose file:

```powershell
cd C:\Users\$env:USERNAME\Desktop\VFSOC\VFSOC_Extras
docker compose -f scripts\lib\docker-compose.infra.yml up -d
```

You should end up with these containers running:

```text
vfsoc_postgres          5432  – PostgreSQL (database: vfsoc, user: postgres)
opensearch-node1        9200  – OpenSearch single node
opensearch-dashboards   5601  – OpenSearch Dashboards UI
vfsoc_adminer           8080  – Adminer for inspecting the DB
```

> The Postgres password is `postgres` for local dev. **Never** reuse this in
> production – set strong credentials via your environment / secrets manager.

---

## 4. One-shot setup with `VFSOC_Extras`

`VFSOC_Extras` includes a setup script that:

1. Creates `.env.local` files for `VFSOC_Admin` and `VFSOC-SIEM`.
2. Runs `npm install` in both Next.js apps.
3. Builds the WPF ingestion app in Release mode (if .NET SDK is present).
4. Applies the unified database schema and seeds the canonical demo dataset
   (9 connectors, 16 fleets, 70 mobility assets, 85 asset–connector links).
5. Optionally creates desktop shortcuts.

Run it once:

```powershell
cd C:\Users\$env:USERNAME\Desktop\VFSOC\VFSOC_Extras
powershell -ExecutionPolicy Bypass -File .\setup.cmd
```

Or the underlying scripts directly:

```powershell
.\scripts\setup-vfsoc.ps1         # env files, npm install, build
.\scripts\apply-schema.ps1        # schema + canonical seed data
.\scripts\Build-Icons.ps1         # branded Vehiqilla .ico files (auto-run by next step)
.\scripts\Install-Shortcuts.ps1   # the three desktop shortcuts
```

> `Install-Shortcuts.ps1` automatically calls `Build-Icons.ps1` the first
> time so the shortcuts ship with branded icons (Vehiqilla logo on a
> color-tinted background per app). Re-run `Build-Icons.ps1` any time
> `VFSOC-SIEM/public/logo.png` changes to refresh them.

### 4.1 What the `.env.local` files contain

Both apps share the same secrets so a JWT issued by one verifies in the other
and password hashes are interchangeable.

`VFSOC_Admin\.env.local` and `VFSOC-SIEM\.env.local`:

```env
DB_USER=postgres
DB_HOST=localhost
DB_NAME=vfsoc
DB_PASSWORD=postgres
DB_PORT=5432

JWT_SECRET=vfsoc-jwt-secret-2024-ultra-secure-key-change-in-production
PEPPER_KEY=vfsoc-pepper-2024-super-secret-pepper-key-change-in-production

NEXT_PUBLIC_MAIN_DASHBOARD_URL=http://localhost:3000   # Admin only
NODE_ENV=development
```

> Change `JWT_SECRET` and `PEPPER_KEY` for any non-local deployment. They must
> remain **identical** across Admin and SIEM.

### 4.2 What the schema/seed script applies

The seed lives at `VFSOC_Extras\scripts\lib\db-schema.sql` (structure + the 9
canonical connectors) and `VFSOC_Extras\scripts\lib\vfsoc-demo-seed.sql`
(fleets, assets, asset–connector links). After it runs you can verify counts
from either Admin or SIEM:

```powershell
docker exec -e PGPASSWORD=postgres vfsoc_postgres `
  psql -U postgres -d vfsoc -c "SELECT COUNT(*) FROM connectors;" `
                            -c "SELECT COUNT(*) FROM fleets;" `
                            -c "SELECT COUNT(*) FROM mobility_assets;" `
                            -c "SELECT COUNT(*) FROM asset_connector_links;"
```

Expected: **9 connectors, 16 fleets, 70 assets, 85 links**.

### 4.3 Default sign-in roles

The schema seeds four user accounts in the `vfsoc` org. All four work in
**both** Admin and SIEM:

| Username | Role | What they can do |
|----------|------|------------------|
| `admin` | admin | Full read/write – users, assets, fleets, connectors, links |
| `operator` | operator | Read everything, write assets/fleets/connectors/links |
| `analyst` | analyst | Primary SIEM role: read assets/fleets/connectors, full SIEM use |
| `viewer` | viewer | Read-only access to admin data |

Initial passwords are provisioned by the schema and are documented privately
for your team – they are intentionally **not** committed to git. Reset them via
the Admin app's user management page on first login.

---

## 5. Run the apps for the first time

You don't need to run anything by hand if you used the desktop shortcuts in
step 4. To launch from the command line:

```powershell
# Terminal 1 – Admin
cd C:\Users\$env:USERNAME\Desktop\VFSOC\VFSOC_Admin
npm run dev          # http://localhost:3001

# Terminal 2 – SIEM (main dashboard)
cd C:\Users\$env:USERNAME\Desktop\VFSOC\VFSOC-SIEM
npm run dev          # http://localhost:3000

# Terminal 3 – Ingestion (WPF)
cd C:\Users\$env:USERNAME\Desktop\VFSOC\VFSOC-Ingestion
dotnet run --project src\VFSOC.Ingestion.WPF -c Release
```

Or, with everything already installed, the orchestrator can launch all three:

```powershell
cd C:\Users\$env:USERNAME\Desktop\VFSOC\VFSOC_Extras
.\start.cmd
```

`stop.cmd` in the same folder shuts down the dev servers and stops the
Docker infra cleanly.

---

## 6. Install the three desktop shortcuts

The HLD calls for exactly three shortcuts. `Install-Shortcuts.ps1` creates
them in **`%USERPROFILE%\Desktop`**:

```powershell
cd C:\Users\$env:USERNAME\Desktop\VFSOC\VFSOC_Extras
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Shortcuts.ps1
```

| Shortcut name | Icon | Target | What happens when you double-click |
|---------------|------|--------|-------------------------------------|
| **VFSOC Ingestion** | Vehiqilla on amber/orange | `scripts\launchers\open-ingestion.bat` → `VFSOC.Ingestion.Client.exe` | Launches the WPF ingestion control app. Builds Release first if the binary is missing. |
| **VFSOC Main Dashboard** | Vehiqilla on teal/cyan | `scripts\launchers\open-main-dashboard.bat` | Starts SIEM (`npm run dev`) if not running, polls `http://localhost:3000` until it returns HTTP 200 (up to 120s), then opens it in the default browser. |
| **VFSOC Admin** | Vehiqilla on deep navy | `scripts\launchers\open-admin-dashboard.bat` | Starts Admin (`npm run dev`) if not running, polls `http://localhost:3001` until it returns HTTP 200 (up to 120s), then opens it in the default browser. |

> The first launch of either dashboard takes ~20 seconds (Next.js compiles on
> demand). Subsequent launches are immediate because the dev server stays
> warm in the background.

### 6.1 Troubleshooting shortcuts

| Symptom | Fix |
|---------|-----|
| "VFSOC.Ingestion.WPF.exe not found" | Run `dotnet build VFSOC-Ingestion\src\VFSOC.Ingestion.WPF -c Release` once, then re-launch. |
| Shortcut opens a black window that vanishes | Right-click → **Properties** → **Run: Minimized**, or open the `.bat` directly to read the error. |
| "Port 3000/3001 already in use" | Another `node` or `next` process is bound. Use Task Manager to kill it, or run `.\stop.cmd` from `VFSOC_Extras`. |
| Login fails immediately | The DB container probably stopped. `docker ps` should show `vfsoc_postgres` healthy; restart with `docker compose -f scripts\lib\docker-compose.infra.yml up -d`. |

---

## 7. Verify the install end-to-end

A 5-minute smoke test that proves everything is wired correctly:

1. Double-click **VFSOC Admin**, sign in as `admin`, open **Users**. You
   should see four seeded accounts (`admin`, `operator`, `analyst`, `viewer`).
2. Open **Fleets** in Admin – you should see **16 fleets**.
3. Open **Mobility Assets** – you should see **70 assets**, each tied to a
   fleet, several with linked connectors.
4. Open **Connectors** – exactly **9** entries: AWS CloudWatch, Vehicle
   Telematics, Tesla ADAS, EV Charging Station, Vertiports Management,
   Endpoint Detection, In-Vehicle Payment, Physical Security, Roadside Sensor.
5. Double-click **VFSOC Main Dashboard**, sign in with the same credentials.
   The fleet roll-ups, asset breakdowns, and connector pills should reference
   the same 16 fleets / 70 assets / 9 connectors as Admin.
6. Open `http://localhost:3000/api/admin/assets` while logged into SIEM – it
   should return the same 70 assets as Admin's `/api/assets`. This proves the
   cross-app DB proxy is live.
7. Double-click **VFSOC Ingestion**. The WPF window should list the same 9
   connector types and let you start/stop simulators per asset.

If any of those steps doesn't match, re-run `apply-schema.ps1` to bring the DB
back to the canonical state.

---

## 8. Updating to the latest `main`

```powershell
cd C:\Users\$env:USERNAME\Desktop\VFSOC

foreach ($repo in 'VFSOC_Extras','VFSOC_Admin','VFSOC-SIEM','VFSOC-Ingestion','VFSOC-log_generation') {
    Push-Location $repo
    git fetch origin
    git checkout main
    git pull --ff-only
    Pop-Location
}

# Re-run setup to pick up new dependencies, schema changes, etc.
cd .\VFSOC_Extras
.\setup.cmd
```

---

## 9. Optional extras

- **Log generator** – `cd VFSOC-log_generation; pip install -r requirements.txt; python main.py` feeds synthetic connector events into the local environment. Useful for demo videos.
- **Adminer** – browse `http://localhost:8080` to inspect the `vfsoc` Postgres database directly.
- **OpenSearch Dashboards** – `http://localhost:5601` for raw log search.
- **ML models** – `VFSOC-ML-Models` (cloned separately) ships inference workers that consume the same 9 connector types; only required if you're working on detection models.

---

## 10. Where to ask for help

- File issues in the repo that owns the failing code (Admin issues in `VFSOC_Admin`, SIEM issues in `VFSOC-SIEM`, orchestration/shortcut issues in `VFSOC_Extras`).
- Cross-app data inconsistencies are almost always a `db-schema.sql` /
  `vfsoc-demo-seed.sql` issue – open them against `VFSOC_Extras`.

Welcome to VFSOC. Happy hunting.
