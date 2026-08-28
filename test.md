# ResQMesh — Manual Testing & Setup Guide

Everything you need to set up the project locally, run every API endpoint by
hand (browser or `curl`), and exercise the same flows through the Flutter
frontend. Covers **Phase 1 + 2** (auth, emergency reports, official alerts, and
the AI agent pipeline).

> Fast reference for a known-good run:
> `docker compose up -d db` → `cd backend && uv sync && cp .env.example .env`
> → `uv run python manage.py migrate` → `uv run python manage.py runserver 0.0.0.0:8000`
> → then follow the tests below.

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

### 2.3 Frontend (Flutter)

```bash
cd frontend/mobile
flutter pub get

# Android emulator (citizen app)
flutter emulators --launch resqmesh_avd          # or open your AVD
flutter run -d <emulator_id>

# Web (coordinator dashboard)
flutter run -d chrome
```

Base URL is platform-aware (`lib/core/api_config.dart`):
- **Android emulator** → `http://10.0.2.2:8000/api/v1`
- **Web / iOS simulator** → `http://localhost:8000/api/v1`

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
- **Citizen app** → Android emulator.
- **Coordinator dashboard** → Chrome (web).

### 5.1 Citizen app (Android emulator)

1. Launch the app (Section 2.3). You land on the **Login** screen.
2. **Login** as `smokecit / strongpass123`, or tap **Register** to create a new citizen.
3. **Get Help / report form** — fill description, pick an incident type, optionally
   add people count, and submit. A new report is created (you'll see it on **My Reports**).
4. **My Reports** — your submitted reports list.
5. **Alerts** — see current **active** official alerts published by coordinators.

### 5.2 Coordinator dashboard (Chrome web)

1. `flutter run -d chrome`, **Login** as `coorddemo / strongpass123`.
2. **Dashboard** — summary + full list of **all** reports with filters.
3. **Open a report** → the **AI SUGGESTION** panel shows the agent’s suggested
   priority / incident / uncertainty / rationale. Tap **Accept suggested priority**
   to apply it, or use the **Change Status** / **Change Priority** chips.
4. **Create Alert** — publish an official alert (citizens will see it if active).

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
uv run python manage.py test            # 51 tests (auth, reports, alerts, agents, evaluation)
uv run python manage.py check           # system checks

cd frontend/mobile
flutter analyze                         # static analysis (expect no issues)
flutter test                            # widget smoke test
flutter build apk --debug               # build the installable app
```

---

## 8. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `OperationalError` / DB connection refused | Ensure `docker compose up -d db` is running and healthy. |
| `ModuleNotFoundError: requests` | Run `cd backend && uv sync` (adds `requests`). |
| App can’t reach server on Android | Server must bind `0.0.0.0`; emulator uses `10.0.2.2:8000`. Restart runserver. |
| Changes not visible in API | Dev server runs `--noreload`; restart it after backend edits. |
| Ollama calls time out / unparseable | Ensure Ollama is running (`ollama serve`) and the model is pulled (`ollama list`). |
| Citizens creating alerts | That’s the expected **403** — coordinators only. |
