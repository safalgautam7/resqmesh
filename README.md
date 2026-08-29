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
uv run python manage.py test          # 59 tests (auth / reports / alerts / agents / relay)
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

### Tests
```bash
cd frontend/mobile
flutter analyze      # expects: No issues found!
flutter test         # widget smoke test
flutter build apk --debug
```

Base URL is platform-aware (`lib/core/api_config.dart`): Android emulator →
`http://10.0.2.2:8000/api/v1`, web → `http://localhost:8000/api/v1`.

---

## Testing

Full step-by-step manual testing (setup, every endpoint with `curl` payloads,
frontend flows, and a dedicated **Android emulator** walkthrough) is in
**`test.md`**.

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
| GET | `/alerts/` | citizen/coord | Active official alerts |
| POST | `/alerts/` | coordinator only | Create alert |
| PATCH | `/alerts/{id}/` | coordinator only | Update / cancel alert |

Layered on top: the **relay/offline** subsystem (`apps/relay`) is exercised via
`manage.py relay_demo` and the `apps/relay` test suite rather than HTTP.

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
