# ResQMesh

Multi-user emergency communication and coordination platform (3-day build, all
3 stages complete).

- **Citizens** report emergencies and receive official alerts.
- **Coordinators** review, prioritize, manage reports, and publish official alerts
  (with an AI triage assistant).
- **Offline-resilient**: reports can move device-to-device (store-carry-forward)
  and reach the backend when a node returns online.

| Stage | Scope | Status |
|-------|-------|--------|
| 1 | Auth + Emergency Reports + Official Alerts + Flutter apps | ✅ |
| 2 | AI provider abstraction + extraction/uncertainty/priority agents + evaluation + coordinator review UI | ✅ |
| 3 | Offline relay / store-carry-forward | ✅ |
| 3.5 | Offline **BLE** device-to-device transport (GATT outbox/inbox, on-device relay + manual flush) | ✅ |

> **Stage 3.5 (the highlight):** the relay moves over **real Bluetooth Low
> Energy** between two Android emulators. A report submitted while the backend
> is down is buffered on-device, handed phone-to-phone over a GATT link, and
> delivered to the server by whichever node regains connectivity — full
> walkthrough incl. a 5-minute demo script in **`test.md`**.
>
> **Location is automatic.** The Get Help form captures the reporter's **current
> GPS position** on open via `geolocator` — there are no manual lat/long fields.
> The coordinates travel with the report whether submitted online or buffered
> through the offline BLE mesh, and are preserved by the backend when a relayed
> envelope is materialized.

Backend: **Django + DRF + PostgreSQL** (managed via `uv`). Frontend: **Flutter**
(Android app for citizens, web for coordinators, one codebase). AI: swappable
**mock / Ollama (local model)** providers.

See `ResQMesh — Project Goal and Development Plan.md`, `architecture.md`,
`phase.md` for the full design; `PROGRESS.md` is the living progress tracker.
**`test.md`** is the complete manual testing guide (API + frontend + Android emulator).

---

## Prerequisites

- Python 3.13 + [uv](https://docs.astral.sh/uv/)
- Docker + Docker Compose (PostgreSQL)
- Flutter 3.x with Android SDK + an emulator + AVD (`resqmesh_avd`) and/or Chrome
- Ollama (optional — only if you want the real local model for AI)

---

## Backend setup & run (uv)

```bash
# 1. Start PostgreSQL
docker compose up -d db

# 2. Install dependencies and create the venv
cd backend
uv sync

# 3. Configure environment
cp .env.example .env          # then adjust secret key / DB / AI provider as needed
export AI_PROVIDER=mock       # mock | ollama

# 4. Migrate
uv run python manage.py migrate

# 5. Run the dev server (10.0.2.2 lets the Android emulator reach the host)
uv run python manage.py runserver 0.0.0.0:8000 --noreload
```

### Tests
```bash
cd backend
uv run python manage.py test          # 62 tests (auth / reports / alerts / agents / relay)
uv run python manage.py check
```

### Demo users (already in the DB)
| username | password | role |
|----------|----------|------|
| `coorddemo` | `strongpass123` | COORDINATOR |
| `smokecit` | `strongpass123` | CITIZEN |

Register a fresh citizen through the app/API instead if you prefer.

### Supervisor / operational commands
```bash
# Run the whole store-carry-forward recovery demo: A -> B -> C -> Django
uv run python manage.py relay_demo

# Show the AI baseline-vs-pipeline evaluation report
uv run python manage.py evaluate_agents --provider mock     # or ollama
```

---

## Frontend setup & run (Flutter)

```bash 
cd frontend/mobile
flutter pub get

# Android emulator (citizen app)  -- on the resqmesh_avd image
flutter emulators --launch resqmesh_avd
flutter run -d <emulator-id>

# Web (coordinator dashboard)
flutter run -d chrome
```

> **After you edit app code**, a device/emulator running an already-built APK
> will **not** pick up your changes until you rebuild and reinstall it. To
> rebuild the debug APK and push it to a running emulator:

```bash
cd frontend/mobile
flutter build apk --debug

# install to an emulator (replace <emulator-id> with e.g. emulator-5554)
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.resqmesh.resqmesh -c android.intent.category.LAUNCHER 1

# re-grant BLE permissions after a reinstall (grants reset on reinstall)
adb shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_SCAN
adb shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_ADVERTISE
adb shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_CONNECT
```

> Alternative during active development: `flutter run -d <emulator-id>` attaches
> the toolchain and gives you instant **hot reload** (`r` in the terminal) — no
> rebuild/reinstall needed. Use the APK route (above) or **`test.md` §2.4** for a
> finished build installed on both emulators prepackaged with permissions.

> The Phase 3 BLE relay demo runs on **two** Android emulators
> (`resqmesh_avd` + `resqmesh_avd_b` → `emulator-5554` / `emulator-5556`) —
> exact launch/install/grant steps in **`test.md` §2.4**, and the
> rebuild/reinstall-after-changes flow in **`test.md` §2.6**.

### Tests
```bash
cd frontend/mobile
flutter analyze      # expects: No issues found!
flutter test         # 7 tests (1 widget + 6 relay envelope/framing)
flutter build apk --debug
```

Base URL is platform-aware (`lib/core/api_config.dart`): Android emulator →
`http://10.0.2.2:8000/api/v1`, web → `http://localhost:8000/api/v1`.

---

## Testing

Full step-by-step manual testing (setup, every endpoint with `curl` payloads,
frontend flows, and a dedicated **Android emulator** walkthrough) is in
**`test.md`**.

For a narrated walkthrough that explains **every layer of the code while the
app runs live**, see **`PRESENTATION_SCRIPT.md`**.

---

## API endpoints (v1) — prefix `http://localhost:8000/api/v1`

| Method | Path | Who | Purpose |
|--------|------|-----|---------|
| POST | `/auth/register/` | anyone | Citizen self-registration |
| POST | `/auth/login/` | anyone | JWT access + refresh |
| POST | `/auth/refresh/` | authed | Refresh access token |
| GET | `/auth/me/` | authed | Current user |
| POST | `/emergencies/` | citizen | Create report |
| GET | `/emergencies/` | citizen/coord | List (own / all) |
| GET | `/emergencies/{id}/` | citizen/coord | Detail incl. AI analysis (coord) |
| PATCH | `/emergencies/{id}/` | coordinator | Update status / priority |
| DELETE | `/emergencies/{id}/` | sender or admin | Delete a report (sender's own messages; admins/superusers any). Normal coordinators cannot delete |
| GET | `/alerts/` | citizen/coord | Active official alerts |
| POST | `/alerts/` | coordinator only | Create alert |
| PATCH | `/alerts/{id}/` | coordinator only | Update / cancel alert |
| GET | `/relay/messages/` | anyone | Monitor carried relay envelopes |
| POST | `/relay/messages/` | mesh node | Deliver a carried envelope (dedup by `message_id`) |

Layered on top: the **relay/offline** subsystem (`apps/relay`) is exercised via
`manage.py relay_demo`, its test suite, **and live on two Android emulators**
(real BLE device-to-device — see `test.md`).

---

## Project layout (high level)

```
backend/config/            Django project settings + urls
backend/apps/accounts/     users, roles, JWT auth
backend/apps/emergencies/  emergency reports + coordinator ops
backend/apps/alerts/       official alerts + notification trigger
backend/apps/agents/       AI provider abstraction + agent pipeline + evaluation
backend/apps/relay/        offline store-carry-forward relay
backend/apps/notifications/ notification provider abstraction
frontend/mobile/           Flutter app (citizen Android + coordinator web)
PROGRESS.md                milestone tracker (M0-M13)
test.md                    manual testing guide
```

See `backend/ARCHITECTURE.md` for a detailed per-file breakdown and data flow.
