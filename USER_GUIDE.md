# VFSOC – User Guide

A friendly tour of the three desktop shortcuts that ship with VFSOC. You do
not need to be a developer to follow this guide – it assumes someone has
already installed VFSOC on your machine (a desktop technician or the
deployment guide).

If you can see these three icons on your desktop, you are ready to go:

- **VFSOC Ingestion**
- **VFSOC Main Dashboard**
- **VFSOC Admin**

---

## 1. The big picture

VFSOC (Vehicle Fleet Security Operations Center) monitors a **connected
mobility fleet**: cars, buses, trucks, drones, VTOL aircraft, charging
stations, roadside sensors, and the back-office systems that keep them
running. Three applications cover three different jobs:

| Shortcut | Who uses it | What it is for |
|----------|-------------|----------------|
| **VFSOC Admin** | Administrators, fleet managers | Register people, vehicles/devices, and the data sources that watch them. |
| **VFSOC Ingestion** | Operations / SecOps | Start and stop the data collectors that feed VFSOC. |
| **VFSOC Main Dashboard** | SOC analysts, leadership | Investigate alerts, search logs, see the security posture of the fleet. |

A simple flow:

```
You set things up in Admin →
Ingestion pulls/produces the data →
The Main Dashboard shows the alerts.
```

---

## 2. Signing in

All three applications share the **same user accounts**. Whatever credentials
you use in Admin will work in the Main Dashboard, and vice versa.

After a fresh install your administrator hands out four kinds of accounts:

| Role | Where you log in | Permissions |
|------|------------------|-------------|
| **admin** | Admin + Main Dashboard | Full control: users, assets, connectors, links, investigations |
| **operator** | Admin + Main Dashboard | Manage assets / fleets / connectors / links, investigate alerts (no user mgmt) |
| **analyst** | Admin (read) + Main Dashboard (full) | Investigate alerts, read fleet inventory |
| **viewer** | Admin (read) + Main Dashboard (read) | Read-only across the platform |

On first login, change your password from the **Profile** menu (top-right
corner of either dashboard).

---

## 3. Shortcut #1 — VFSOC Admin

**Double-click → opens `http://localhost:3001`.** This is where the world of
VFSOC is defined.

### 3.1 What you'll see when you sign in

The sidebar (left) has these sections:

- **Overview** – at-a-glance counts of users, fleets, assets, connectors, and
  asset–connector links.
- **Users** – the people who can sign in (admin/operator/analyst/viewer).
- **Fleets** – named groups that contain your mobility assets (for example
  `EV-001`, `AERIAL-FLEET-001`, `EV_CHARGING_NETWORK`).
- **Mobility Assets** – every single car, bus, truck, drone, charger,
  sensor, or device VFSOC monitors.
- **Connectors** – the nine data source types VFSOC supports (see §3.4).
- **Asset ↔ Connector Links** – which connector supplies data for which
  asset. One asset can have many connectors.
- **Open Main Dashboard** – a sidebar link that takes you to the SIEM in a
  new tab.

### 3.2 Add a person (Users)

1. Click **Users** → **Add User**.
2. Fill in username, email, role.
3. Click **Save**. A one-time password is generated; share it with the user
   securely and ask them to reset it on first login.

### 3.3 Add a vehicle (Mobility Assets)

1. Click **Mobility Assets** → **Add Asset**.
2. Pick a **Fleet** (or create a new one from **Fleets** first).
3. Fill in:
   - **Identifier** – the unique ID VFSOC will use everywhere (e.g.
     `EV-004-V05`).
   - **Friendly name** – what humans see in the UI.
   - **Type** – `car`, `bus`, `truck`, `drone`, `aam`, `ev_charger`,
     `sensor`, `gateway`, `depot`, `vertiport`, etc.
   - **Status** – `active`, `inactive`, `maintenance`, `decommissioned`.
4. Click **Save**.

### 3.4 Wire data sources (Connectors and Links)

Out of the box VFSOC ships with **9 canonical connectors**:

| Connector | What it sees |
|-----------|--------------|
| **AWS CloudWatch** | Cloud-side logs (CloudTrail, VPC flow, app logs) |
| **Vehicle Telematics** | GPS, CAN bus, TCU, OTA events from vehicles |
| **Tesla ADAS** | Tesla Autopilot / FSD telemetry |
| **EV Charging Station** | OCPP sessions, payments, authentication |
| **Vertiports Management** | Drone / VTOL flight plans, pad operations |
| **Endpoint Detection** | EDR + MDM on fleet laptops, tablets, phones |
| **In-Vehicle Payment** | In-vehicle / charger payment processing |
| **Physical Security** | Depot gates, badge readers, biometric access |
| **Roadside Sensor** | Roadside units, V2X, traffic and environmental sensors |

To tell VFSOC "watch this asset with this connector":

1. Go to **Asset ↔ Connector Links** → **New Link**.
2. Pick the asset on the left, the connector on the right.
3. Optionally add config (account ID, endpoint URL, etc.) – purely metadata
   that the ingestion side can read later.
4. Click **Save**. The new link is immediately visible in both Admin and the
   Main Dashboard.

### 3.5 Day-to-day Admin tasks

| Task | Where | Notes |
|------|-------|-------|
| Onboard a new driver / analyst | Users → Add User | Assign the right role |
| Add a vehicle to a fleet | Mobility Assets → Add Asset | Pick existing fleet or create one |
| Decommission an asset | Mobility Assets → Edit → Status = decommissioned | The Main Dashboard will hide it from active rollups |
| Reorganize fleets | Fleets → rename / merge | Use sparingly – history follows the fleet name |
| Add a new connector type | Connectors → Add Connector | Only after the ingestion team confirms support |

---

## 4. Shortcut #2 — VFSOC Ingestion

**Double-click → launches the WPF ingestion control application.**

Ingestion does the actual work of collecting data from the connectors you
configured in Admin and turning it into alerts the SIEM can show.

### 4.1 What the window contains

- **Connector list (left)** – the same 9 connectors you saw in Admin. Each
  row shows whether the connector is **Running**, **Stopped**, or **Error**.
- **Asset list (right)** – when you select a connector, the right pane lists
  every asset linked to it (drawn from Admin's `asset_connector_links`).
- **Console (bottom)** – live log output: how many events were ingested,
  retries, errors.
- **Toolbar (top)** – Start All, Stop All, Reload from Admin, Open log
  folder.

### 4.2 Common workflows

**Start collecting after a fresh install:**

1. Click **Reload from Admin** so the WPF app picks up the latest
   asset–connector links.
2. Click **Start All**. Each connector spins up its workers; the console
   will start scrolling within a few seconds.
3. Switch to the Main Dashboard – within a minute or two you should see
   counts climb on the overview tiles.

**Pause a single connector for maintenance:**

1. Select the connector in the left pane.
2. Click **Stop**. Other connectors keep running.
3. When ready, click **Start** again.

**Investigate a connector that says "Error":**

1. Click the connector to see its asset list and the most recent error
   message in the console.
2. Common causes: credentials missing, target host unreachable, the upstream
   API has changed.
3. Fix the underlying issue, then click **Reload from Admin** and **Start**.

**Important:** you do **not** add or remove assets in this window. The
ingestion app is read-only with respect to the Admin database – it consumes
whatever the **Admin** UI says is configured. If a vehicle isn't appearing,
add it in Admin first.

---

## 5. Shortcut #3 — VFSOC Main Dashboard

**Double-click → opens `http://localhost:3000` in your browser.** This is the
SOC analyst experience.

### 5.1 What you'll see

The top navigation has these tabs:

- **Overview** – KPI tiles (open alerts, IoCs, top-alerted fleets, top-alerted
  connectors), trends, and a map of asset locations.
- **Alerts** – every detected security event, filterable by severity,
  fleet, asset, connector, status, and time range.
- **Investigations / IoCs** – grouped views of related alerts that point to
  the same Indicator of Compromise (e.g. credential stuffing, CAN injection).
- **Fleets** – browse by fleet, drill down into individual assets.
- **Assets** – the full inventory mirrored from Admin (same 70 assets if
  you're on the seeded demo).
- **Logs** – raw vehicle/device logs that fed each alert, plus a free-text
  search across all collected events.
- **Settings / Profile** – change password, toggle theme.

### 5.2 A guided "first alert" tour

1. From **Overview**, click the top-right tile **Open Alerts**.
2. Pick a critical-severity row, for example **EV-104 — Unauthorized CAN
   Bus Message Injection**.
3. The alert detail page shows:
   - **Context** – the vehicle, device, fleet, and connector involved.
   - **AI insight** – a short summary of what the model thinks happened.
   - **Related logs** – source events the alert was built from.
   - **Correlated IoCs** – e.g. *IoC-300 Vehicle Communication Disruption*
     and *IoC-700 Vehicle Theft*.
4. Click any **asset** chip (e.g. `EV-001-V04`) to jump into the asset
   detail page: full asset metadata, every alert it has ever raised, and
   which connectors are watching it.
5. Click any **connector** chip (e.g. `Vehicle Telematics`) to see all
   alerts produced by that data source.
6. When the investigation is done, mark the alert **Closed** with a short
   note. That note shows up in the alert's audit trail and in the analyst
   report.

### 5.3 Searching the fleet

- Use the **Search** bar in the navbar to jump to any asset by identifier
  (`EV-002-V01`, `CHG-003`, `SENSOR-045`, …) or any fleet name (`EV-003`,
  `EV_CHARGING_NETWORK`, …).
- The **Logs** tab supports free-text search across raw events. Tip: search
  for a vehicle ID and narrow by time to reconstruct what happened around an
  alert.

### 5.4 Reports and exports

From **Alerts** or **IoCs**, click **Export** to download a CSV/JSON of the
current view. Use this for after-action reports or to share findings with
the customer.

---

## 6. How the three apps fit together

```
┌──────────────────┐        ┌──────────────────────────────┐
│   VFSOC Admin    │  reads │   Shared PostgreSQL (vfsoc)  │
│  (defines what   │ ◄─────►│  users, fleets, assets,      │
│   to monitor)    │        │  connectors, links           │
└────────┬─────────┘        └──────────────┬───────────────┘
         │                                 │
         │  links inform                   │  same DB
         ▼                                 ▼
┌──────────────────┐        ┌──────────────────────────────┐
│ VFSOC Ingestion  │ feeds  │   VFSOC Main Dashboard       │
│ (collects data)  │ ─────► │   (alerts, IoCs, logs)       │
└──────────────────┘        └──────────────────────────────┘
```

Three things to remember:

1. **Admin is the single source of truth.** If a fleet, asset, or connector
   doesn't exist in Admin, the other two apps won't see it.
2. **The Main Dashboard never writes to Admin.** Analysts can mark alerts
   as closed and add notes, but they can't change asset definitions.
3. **The same login works everywhere.** Don't keep separate credentials per
   app – ask your admin to fix it instead.

---

## 7. Daily routine cheat-sheet

| When | Open | Do |
|------|------|-----|
| Morning | Main Dashboard → Overview | Glance at open alerts and the 24-hour trend. |
| As alerts arrive | Main Dashboard → Alerts | Triage by severity. Use the asset / fleet / connector pivots. |
| Whenever the fleet changes | Admin → Mobility Assets | Add/decommission vehicles, charging stations, sensors. |
| After fleet changes | Ingestion → Reload from Admin | Make sure collectors know about new/removed assets. |
| Connector outage | Ingestion → Stop the bad connector, fix the issue, Start again | Check Overview's "connectors with errors" tile is back to zero. |
| End of shift | Main Dashboard → Investigations | Close out anything resolved with a short note. |

---

## 8. Getting unstuck

| Problem | What to try |
|---------|-------------|
| Shortcut does nothing | Hover the shortcut, **Properties** → make sure the target `.bat` exists. Re-run `Install-Shortcuts.ps1`. |
| Dashboard says "Failed to fetch" | The backend probably restarted. Reload the page. If it persists, your IT contact should re-run `start.cmd` from `VFSOC_Extras`. |
| Login says "Invalid credentials" | Caps lock? Otherwise ask an admin to reset your password from Admin → Users. |
| You see 0 alerts after install | Open Ingestion, click **Start All**. Alerts arrive within a couple of minutes. |
| You see fewer assets than expected | In Admin → Mobility Assets, check the filter at the top isn't excluding a status (default shows `active`). |
| You added an asset in Admin but Ingestion can't see it | In Ingestion's toolbar click **Reload from Admin**. |

Still stuck? Take a screenshot of the issue (with the URL bar visible for
the dashboards) and send it to your VFSOC administrator. They have the
deployment guide and can replicate locally.
