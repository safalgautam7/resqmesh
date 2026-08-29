# ResQMesh — Manual Testing & Setup Guide

Everything you need to set up the project locally, run every API endpoint by
hand (browser or `curl`), and exercise the same flows through the Flutter
frontend. Covers **Phases 1 + 2** (auth, emergency reports, official alerts,
and the AI agent pipeline) and **Phase 3** (offline relay — reports move
device-to-device over real Bluetooth Low Energy GATT and reach the backend
when any node is back online).

> Fast reference for a known-good run:
> `docker compose up -d db` → `cd backend && uv sync && cp .env.example .env`
> → `uv run python manage.py migrate` → `uv run python manage.py runserver 0.0.0.0:8000`
> → then follow the tests below.
>
> The Phase 3 BLE relay demo needs **two** Android emulators — see **§2.4**.

---

## 1. Prerequisites

| Tool | Notes |
|------|-------|
| Python **3.13** + [uv](https://docs.astral.sh/uv/) | Backend env/runner |
| Docker + Docker Compose | PostgreSQL 16 |
| Flutter 3.x + Dart | Frontend (Android SDK + emulator, or Chrome) |
| Ollama (optional) | Local AI provider for the agent pipeline |

Test users already created in the DB:

| Username | Password | Role |
|----------|----------|------|
| `coorddemo` | `strongpass123` | COORDINATOR |
| `smokecit` | `strongpass123` | CITIZEN |

(You can register a fresh citizen through the API/app instead.)

For the two-emulator presentation, log in as **`smokecit` on `emulator-5554`**
(citizen app) and **`coorddemo` on `emulator-5556`** (coordinator app + mesh
peer). Both AVDs run on the same host, so they share the emulator's BLE radio
(RootCanal) — device-to-device delivery works with no extra configuration.

---

## 2. Setup

### 2.1 Start PostgreSQL (Docker)

```bash
docker compose up -d db          # creates container resqmesh_db
docker compose ps                # should show "running" + "healthy"
```

Credentials (from `docker-compose.yml`): `resqmesh:resqmesh@localhost:5432/resqmesh`.

### 2.2 Backend

```bash
cd backend
uv sync                          # create venv + install deps (django, drf, requests, ...)
cp .env.example .env             # first time only
# edit .env to taste (secret key, DB URL, AI_PROVIDER)
uv run python manage.py migrate  # apply all migrations
uv run python manage.py runserver 0.0.0.0:8000 --noreload
```

- `--noreload` avoids spawning extra re-loader processes.
- `0.0.0.0` lets the **Android emulator** reach the host via `10.0.2.2`.
- Health check: open `http://localhost:8000/admin/` or hit any endpoint below.

### 2.3 Frontend (Flutter) + Android emulator

```bash
cd frontend/mobile
flutter pub get
```

Base URL is platform-aware (`lib/core/api_config.dart`):
- **Android emulator** → `http://10.0.2.2:8000/api/v1` (reaches the host machine)
- **Web / iOS simulator** → `http://localhost:8000/api/v1`

#### Start the emulator (Android system image)
This project uses the `resqmesh_avd` AVD (Android 15 / API 35). To create it the
first time (only if it doesn’t exist):

```bash
# list your AVDs
$ANDROID_HOME/emulator/emulator -list-avds
# create one if missing (SDK 35 system image must be installed)
flutter emulators --create --name resqmesh_avd
```

Launch the AVD directly (more robust than `flutter emulators --launch`):

```bash
$ANDROID_HOME/emulator/emulator -avd resqmesh_avd -no-snapshot-save -no-boot-anim &
```

Wait until Android has fully booted (the launcher is responsive):

```bash
$ANDROID_HOME/platform-tools/adb wait-for-device
# then poll until this prints "1":
$ANDROID_HOME/platform-tools/adb shell getprop sys.boot_completed
# list devices — you should see e.g. "emulator-5554   device"
$ANDROID_HOME/platform-tools/adb devices
```

Now run the app in debug mode (hot-reloadable) on the emulator:

```bash
flutter devices                 # get the emulator id (e.g. emulator-5554)
flutter run -d emulator-5554
```

Or, if you prefer the pre-built APK without the Flutter toolchain attached:

```bash
flutter build apk --debug
$ANDROID_HOME/platform-tools/adb install -r build/app/outputs/flutter-apk/app-debug.apk
$ANDROID_HOME/platform-tools/adb shell monkey -p com.resqmesh.resqmesh \
    -c android.intent.category.LAUNCHER 1
```

> **Before you test on device, make sure the backend is running** on the host:
> `uv run python manage.py runserver 0.0.0.0:8000 --noreload` (from `backend/`).
> The emulator reaches it via `10.0.2.2`.

#### Web (coordinator dashboard)
```bash
flutter run -d chrome
```

### 2.4 Launch TWO emulators (full-app presentation / Phase 3 relay demo)

Two AVDs exist for this project:

| AVD | Port | Role |
|-----|------|------|
| `resqmesh_avd` | `emulator-5554` | Citizen app (`smokecit`) |
| `resqmesh_avd_b` | `emulator-5556` | Coordinator app + mesh peer (`coorddemo`) |

Launch both (one per terminal, or background them with `&`):

```bash
EMU=$ANDROID_HOME/emulator/emulator
$EMU -avd resqmesh_avd   -no-snapshot-save -no-boot-anim > /tmp/emu_a.log 2>&1 &
$EMU -avd resqmesh_avd_b -no-snapshot-save -no-boot-anim > /tmp/emu_b.log 2>&1 &
```

Wait for **both** to fully boot (~40-60 s each). `adb devices` lists them in
port order (usually `emulator-5554`, then `emulator-5556`):

```bash
ADB=$ANDROID_HOME/platform-tools/adb
for d in emulator-5554 emulator-5556; do
  $ADB -s $d wait-for-device
  until [ "$($ADB -s $d shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
  echo "$d booted"
done
```

Install the same debug APK on both and grant the BLE permissions (the app
never shows a runtime permission dialog — grants are pre-provisioned with
`pm grant`):

```bash
APK=frontend/mobile/build/app/outputs/flutter-apk/app-debug.apk
ADB=$ANDROID_HOME/platform-tools/adb
for d in emulator-5554 emulator-5556; do
  $ADB -s $d install -r "$APK"
  $ADB -s $d shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_SCAN
  $ADB -s $d shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_ADVERTISE
  $ADB -s $d shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_CONNECT
  $ADB -s $d shell monkey -p com.resqmesh.resqmesh -c android.intent.category.LAUNCHER 1
done
```

> **Pairing prompt:** when the devices first connect over BLE, a system dialog
> "Pair with `AA:BB:…`? / Bluetooth pairing code …" appears. Tap **Pair** (keep
> "Also allow access to contacts and call history" **unchecked**). Because each
> BLE connection uses a fresh random address, the dialog may re-appear for new
> connections — it never blocks the background relay.

---

## 3. API end-to-end map

All endpoints are under the prefix **`http://localhost:8000/api/v1`**.

| Method | Path | Who | Purpose |
|--------|------|-----|---------|
| POST | `/auth/register/` | anyone | Citizen self-registration (always CITIZEN) |
| POST | `/auth/login/` | anyone | Obtain JWT access + refresh |
| POST | `/auth/refresh/` | authed | Refresh access token |
| GET | `/auth/me/` | authed | Current user profile |
| POST | `/emergencies/` | citizen | Create an emergency report |
| GET | `/emergencies/` | citizen/coordinator | List reports (own / all) |
| GET | `/emergencies/{id}/` | citizen/coordinator | Detail incl. **AI analysis** (coordinator) |
| PATCH | `/emergencies/{id}/` | coordinator | Update **status** / **priority** |
| GET | `/alerts/` | citizen/coordinator | Active official alerts (citizens: active only) |
| POST | `/alerts/` | coordinator only | Create an official alert |
| GET | `/alerts/{id}/` | authed | Alert detail |
| PATCH | `/alerts/{id}/` | coordinator only | Update/cancel an alert |
| GET | `/relay/messages/` | anyone | Monitor carried envelopes (+ `delivery_status`) |
| POST | `/relay/messages/` | mesh node | Push a carried envelope (dedup by `message_id`: **201** new / **200** duplicate) |

Role rules to remember:
- Registration **always** creates a CITIZEN (role never taken from the payload).
- Citizens see **only their own** reports; coordinators see **all**.
- Only coordinators can set `status`/`priority` (citizen writes to these are silently ignored — the original value is preserved).
- Only coordinators can create/update alerts. Citizens see only **active, non-expired** alerts.
- Coordinate pairs must be provided together (`latitude` + `longitude`).

---

## 4. Testing via `curl`

Store a token helper (adjust host as needed):

```bash
BASE=http://localhost:8000/api/v1
J='Content-Type: application/json'

# login helper
login() { curl -s -X POST $BASE/auth/login/ -H "$J" -d "{\"username\":\"$1\",\"password\":\"$2\"}"; }
```

### 4.1 Authentication

**Register a citizen** (201 → user object, no token returned):

```bash
curl -s -X POST $BASE/auth/register/ -H "$J" \
  -d '{"username":"alice","email":"a@x.com","password":"strongpass123"}'
```

**Login** (200 → `{"access":"...","refresh":"..."}`):

```bash
CIT=$(login smokecit strongpass123 | python3 -c "import sys,json;print(json.load(sys.stdin)['access'])")
COORD=$(login coorddemo strongpass123 | python3 -c "import sys,json;print(json.load(sys.stdin)['access'])")
```

**Me** (200 → your profile incl. `role`):

```bash
curl -s $BASE/auth/me/ -H "Authorization: Bearer $CIT"
```

**Refresh** (200 → new access token):

```bash
REFRESH=$(login smokecit strongpass123 | python3 -c "import sys,json;print(json.load(sys.stdin)['refresh'])")
curl -s -X POST $BASE/auth/refresh/ -H "$J" -d "{\"refresh\":\"$REFRESH\"}"
```

### 4.2 Emergency reports

**Citizen creates a report** (201). Note: the AI agent pipeline runs automatically
after creation (post_save) and stores `analysis`.

```bash
curl -s -X POST $BASE/emergencies/ -H "Authorization: Bearer $CIT" -H "$J" \
  -d '{"description":"Two people trapped under a collapsed roof near the park, one bleeding badly","incident_type":"OTHER"}'
```

**Citizen lists OWN reports** (200, only theirs):

```bash
curl -s $BASE/emergencies/ -H "Authorization: Bearer $CIT"
```

**Coordinator lists ALL reports** (200, all):

```bash
curl -s $BASE/emergencies/ -H "Authorization: Bearer $COORD"
```

**Coordinator fetches detail + AI analysis** (200). Replace `{id}` with a real id
(e.g. `3`). The `analysis` block returns `extraction`, `uncertainty`, `priority`
(with `suggested_priority` and `rationale`), and `is_available`.

```bash
curl -s $BASE/emergencies/3/ -H "Authorization: Bearer $COORD"
```

**Coordinator accepts the AI suggestion / updates priority + status** (200):

```bash
curl -s -X PATCH $BASE/emergencies/3/ -H "Authorization: Bearer $COORD" -H "$J" \
  -d '{"priority":"CRITICAL","status":"REVIEWING"}'
```

**Verify a citizen CANNOT change priority/status** (returns 200 but the value is
unchanged — read-only for citizens):

```bash
curl -s -X PATCH $BASE/emergencies/3/ -H "Authorization: Bearer $CIT" -H "$J" \
  -d '{"priority":"LOW"}'
# then re-GET and confirm priority is still CRITICAL
curl -s $BASE/emergencies/3/ -H "Authorization: Bearer $COORD" | python3 -m json.tool
```

### 4.3 Official alerts

**Coordinator creates an alert** (201):

```bash
curl -s -X POST $BASE/alerts/ -H "Authorization: Bearer $COORD" -H "$J" \
  -d '{"title":"Flood warning","message":"Low-lying areas near the river may flood.","severity":"HIGH","target_area":"Riverside colony"}'
```

**Citizen lists active alerts** (200 — only ACTIVE, non-expired):

```bash
curl -s $BASE/alerts/ -H "Authorization: Bearer $CIT"
```

**Citizen tries to create an alert** (403 — forbidden):

```bash
curl -s -o /dev/null -w "status: %{http_code}\n" -X POST $BASE/alerts/ \
  -H "Authorization: Bearer $CIT" -H "$J" \
  -d '{"title":"hacked","message":"x"}'
```

**Coordinator cancels/updates an alert** (200):

```bash
curl -s -X PATCH $BASE/alerts/1/ -H "Authorization: Bearer $COORD" -H "$J" \
  -d '{"status":"CANCELLED"}'
```

---

## 5. Testing via the Flutter frontend

The app has two role-gated fronts from one codebase:
- **Citizen app** → runs on the **Android emulator** (`resqmesh_avd`).
- **Coordinator dashboard** → best on **Chrome (web)**; it also runs on the
  emulator but the web build is quicker for the coordinator role.

For **both** targets the backend must be running on the host:
`uv run python manage.py runserver 0.0.0.0:8000 --noreload` (from `backend/`).

### 5.1 Citizen app (Android emulator)

This is the end-to-end mobile flow on the emulator:

1. **Boot & install** (Section 2.3). The app should already be installed and
   launched on `emulator-5554`. If not:
   ```bash
   $ANDROID_HOME/platform-tools/adb install -r \
       frontend/mobile/build/app/outputs/flutter-apk/app-debug.apk
   $ANDROID_HOME/platform-tools/adb shell monkey -p com.resqmesh.resqmesh \
       -c android.intent.category.LAUNCHER 1
   ```
   Verify the app is alive and in the foreground:
   ```bash
   $ANDROID_HOME/platform-tools/adb shell pidof com.resqmesh.resqmesh   # prints a PID
   $ANDROID_HOME/platform-tools/adb shell dumpsys activity activities \
       | grep -i resqmesh                                             # shows .MainActivity visible=true
   ```
2. You land on the **Login** screen.
3. **Login** as `smokecit / strongpass123`, **or tap Register** to create a new citizen.
4. **Get Help** (report form) — enter a description, pick an incident type, add a
   people count, submit. The report is created on the backend (see it on **My Reports**).
5. **My Reports** — your submitted reports.
6. **Alerts** — see the **active** official alerts that a coordinator published.

To see the **AI side effect** of a citizen report, log in as the coordinator in
another window (Section 5.2) and open the report you just created — the AI
SUGGESTION panel will show the agent analysis for it.

### 5.2 Coordinator dashboard (Chrome web)

1. `flutter run -d chrome`, **Login** as `coorddemo / strongpass123`.
2. **Dashboard** — summary + full list of **all** reports with filters.
3. **Open a report** → the **AI SUGGESTION** panel shows the agent’s suggested
   priority / incident / uncertainty / rationale. Tap **Accept suggested priority**
   to apply it, or use the **Change Status** / **Change Priority** chips.
4. **Create Alert** — publish an official alert (citizens on the emulator will see
   it in the **Alerts** screen when it is active).

> Tip: to watch the whole multi-user flow live, run the **citizen app on the
> emulator** and the **coordinator on Chrome** at the same time, side by side:
> citizen submits → coordinator sees it with AI analysis → coordinator accepts
> priority → citizen can verify the alert appeared.

### 5.3 Offline-mesh (BLE) live demo — Phase 3 highlight

Flagship demo: a report is submitted while the backend is **down**; it travels
**device-to-device over BLE** from the citizen phone to a nearby phone, which
delivers it once it (or the network) is back online.

Prerequisites: both emulators from **§2.4** booted + BLE grants applied, both
users logged in (`smokecit` on 5554, `coorddemo` on 5556). Each home screen
shows the **Offline mesh** card: `mesh active · 0 queued · 0 carried`, with a
**Sync now** button.

1. **Take the backend down** (the app must see a live host fail in order to
   take the offline path):
   ```bash
   pgrep -af runserver              # find the exact PIDs
   kill <backend-pids>              # kill by PID, never `pkill -f runserver`
   curl -s -o /dev/null -m 2 http://localhost:8000/api/v1/relay/messages/ \
     && echo "still up" || echo "backend down"
   ```
2. **5554 (citizen):** tap **GET HELP** → type a description (e.g. *"Trapped
   under debris near KU"*) → pick an incident type → **SEND EMERGENCY REPORT**.
   A snackbar reads *"No connection — report saved offline…"* and the card
   flips to **`1 queued · 0 carried`**.
3. **Watch the BLE hop** (happens automatically within ~10-60 s):
   - A (5554) logcat: `[relay-ble] … peer …: sent 1 envelope(s)`
   - B (5556) logcat: `[relay] inbox + <message_id> origin=smokecit`
   - B's card flips to **`0 queued · 1 carried`**
   ```bash
   $ANDROID_HOME/platform-tools/adb -s emulator-5556 logcat -d | grep -E '\[relay'
   ```
4. **Bring the backend back** (from `backend/`):
   ```bash
   nohup uv run python manage.py runserver 0.0.0.0:8000 --noreload \
     > /tmp/resq_backend.log 2>&1 &
   ```
5. **Within ~20 s** B's periodic recovery push delivers the carried report:
   its card reads **`delivered 1 to server`**, then both cards settle at
   `0 queued · 0 carried`.
6. **Prove it reached the server**:
   ```bash
   curl -s http://localhost:8000/api/v1/relay/messages/ | python3 -m json.tool
   # look for delivery_status:"DELIVERED", synced_to_server:true, a report_id,
   # source_node:"smokecit", and the description text
   ```
   Refresh the coordinator screen on 5556 → the report is in the list.
7. **Manual flush:** the **Sync now** button on any card runs the same delivery
   path on demand — a good closing beat ("…and you can always force a sync").

**Under the hood:** every device runs BOTH a BLE GATT server (advertises the
shared service UUID `6e400001-b5a3-…`) and client (scans + connects + writes).
A report is framed into ≤470-byte chunks (`R1|<id>|<byteOffset>|<total>|<b64>`),
reassembled on the peer into an inbox (Hive `relay_inbox`), and deduplicated by
`message_id` so double-delivery is harmless (it lands once, `201` then `200`).
Envelopes carry `max_hops=8` and a 24 h TTL; expired entries are dropped on
read.

### 5.4 Coordinator on Chrome (web) — variant

Prefer a device + web mix?

```bash
flutter run -d chrome    # login as coorddemo / strongpass123
```

Everything shown on emulator-5556 (dashboard, filters, AI panel, create alert)
works identically on Chrome. For the Phase 3 device-to-device hop you still
need **two** BLE-capable emulators — the web coordinator is a second pair of
eyes, not a mesh node.

---

## 6. Testing the AI agent pipeline (optional)

Backend has a scripted evaluation harness and a re-analysis command.

```bash
cd backend
# Deterministic rule-based pipeline (no model needed)
uv run python manage.py evaluate_agents --provider mock

# Real local model (requires Ollama running with a model, e.g. qwen2.5-coder:1.5b)
uv run python manage.py evaluate_agents --provider ollama

# Re-run / backfill analysis on reports already in the DB
uv run python manage.py analyze_reports --all
```

Set the provider in `backend/.env`:

```ini
AI_PROVIDER=mock        # mock | ollama
AI_MODEL=qwen2.5-coder:1.5b
OLLAMA_URL=http://localhost:11434
```

---

## 7. Automated tests

```bash
cd backend
uv run python manage.py test            # 62 tests (auth, reports, alerts, agents, relay)
uv run python manage.py check           # system checks

cd frontend/mobile
flutter analyze                         # static analysis (expect no issues)
flutter test                            # 7 tests (1 widget + 6 relay envelope/framing)
flutter build apk --debug               # build the installable app
```

### Offline / relay testing (Stage 3)

```bash
cd backend
uv run python manage.py test apps.relay            # the 11 relay tests (scenarios + inbound HTTP)

# Run the store-carry-forward demo:  A(offline) -> B -> C -> Django
uv run python manage.py relay_demo
```

Expected `relay_demo` output (roughly):

```text
Device A (OFFLINE) creates a report -> held in local outbox.
  message_id=141b305f... synced_to_server=False
A meets B -> exchange           -> B now has 1
B meets C -> exchange           -> C now has 1
C regains connectivity -> delivers to Django backend
  relay message synced_to_server=True status=DELIVERED
  Django now holds EmergencyReport #N (...)
```

---

## 8. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `OperationalError` / DB connection refused | Ensure `docker compose up -d db` is running and healthy. |
| `ModuleNotFoundError: requests` | Run `cd backend && uv sync` (adds `requests`). |
| App can’t reach server on Android | Server must bind `0.0.0.0`; emulator uses `10.0.2.2:8000`. Restart runserver. |
| Emulator not booting / frozen | Relaunch with `-no-snapshot-save -no-boot-anim`; disk can be slow on first boot. |
| `adb: no devices` / offline | Start the emulator first, then run `adb wait-for-device`; `adb devices` should list `emulator-5554`. |
| AVD missing | `flutter emulators --create --name resqmesh_avd` (needs the API 35 system image installed). |
| APK install says `INSTALL_FAILED` | Use `adb install -r` (replace). |
| Changes not visible in API | Dev server runs `--noreload`; restart it after backend edits. |
| Ollama calls time out / unparseable | Ensure Ollama is running (`ollama serve`) and the model is pulled (`ollama list`). |
| Citizens creating alerts | That’s the expected **403** — coordinators only. |
| BLE scan finds nothing / mesh card idle | Both AVDs must be running on the **same host**, Bluetooth ON, and the user logged in (the relay starts only after login). Re-grant all three `BLUETOOTH_*` perms if the APK was reinstalled. |
| "Pair with …" dialog repeats | Normal — each BLE connection uses a fresh random address. Tap **Pair**; it doesn’t block the relay. |
| Backend edits not visible | Dev server uses `--noreload`; find exact PIDs (`pgrep -af runserver`) and kill those, then restart. Never `pkill -f runserver`. |
| Card still "0 queued" after an offline report | Read `adb logcat -d | grep -E '\[relay'` for `outbox + <id>`; confirm the backend was actually down (otherwise the report goes straight to the server and never enters the outbox). |

---

## Appendix — 5-minute live presentation script

Paced walkthrough of the whole app for a demo. **Setup (done beforehand):** two
emulators booted (**§2.4**), APK installed, BLE grants applied, backend
running, DB seeded (`smokecit`, `coorddemo`).

| # | Time | Presenter action | Screen shows |
|---|------|------------------|--------------|
| 1 | 0:00 | "ResQMesh is a multi-user emergency comms platform. Citizens report; coordinators triage; and when the network dies, reports still get through — device to device." | Both emulators side by side, login screens |
| 2 | 0:20 | Log in `smokecit` (5554) and `coorddemo` (5556). | Home screens; point out the **Offline mesh** card (`mesh active · 0 queued · 0 carried`) |
| 3 | 0:45 | On 5554: **GET HELP** → describe an incident → **SEND EMERGENCY REPORT**. | Report form → snackbar "Report submitted … RQ-…" |
| 4 | 1:05 | "The same event, from the coordinator’s side." On 5556 open the report → **AI suggestion** panel (extraction + uncertainty + suggested priority + rationale) → **Accept suggested priority** / set status. | Coordinator list → report detail with AI pane |
| 5 | 1:45 | On 5556: **Create official alert** (e.g. "Flood warning" / HIGH / riverside). On 5554: **Alerts** tab → active alert appears. | Alert creation → citizen Alerts screen |
| 6 | 2:15 | "Now the headline: what happens when there is NO network?" Stop the backend (`pgrep -af runserver` → `kill <pids>`). | Backend terminal |
| 7 | 2:35 | On 5554 submit a second report (while offline). | Snackbar "No connection — report saved offline"; card → **`1 queued`** |
| 8 | 3:00 | "The phone hands it to a nearby device over Bluetooth." Wait for the hop. | 5556 card → **`1 carried`**; `logcat -d | grep '\[relay'` shows `inbox + <id> origin=smokecit` |
| 9 | 3:30 | Restart the backend (`nohup uv run … &`). | Backend terminal |
| 10 | 3:50 | "And that peer pushes it to the server the moment it’s online." | 5556 card → **`delivered 1 to server`**; `curl …/relay/messages/` shows `DELIVERED` + a `report_id` |
| 11 | 4:15 | Wrap up: "The same recovery path is behind the **Sync now** button — manual flush on demand. Extendable to multi-hop (max 8)." | Tap **Sync now** |
| 12 | 4:40 | Q&A. | — |

> If a pairing dialog pops during step 8, tap **Pair** — the relay keeps working
> behind it.
