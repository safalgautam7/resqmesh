# ResQMesh

Multi-user emergency communication and coordination platform.

- Citizens report emergencies and receive official alerts.
- Coordinators review, prioritize, and manage reports, and publish official alerts.
- Backend: Django + DRF + PostgreSQL (managed via `uv`).
- Frontend: Flutter (Android app + web dashboard).

See `ResQMesh — Project Goal and Development Plan.md`, `architecture.md`, and
`phase.md` for full design. `PROGRESS.md` is the living progress tracker.

---

## Prerequisites

- Python 3.13 + [uv](https://docs.astral.sh/uv/)
- Docker + Docker Compose (for PostgreSQL)
- Flutter 3.x (Android SDK + emulator for the mobile app)

---

## Backend setup & run (uv)

```bash
# 1. Start PostgreSQL
docker compose up -d db

# 2. Install dependencies and create the venv
cd backend
uv sync

# 3. Configure environment
cp .env.example .env          # then adjust as needed
export AI_PROVIDER=mock       # mock | ollama | hosted

# 4. Migrate
uv run python manage.py migrate

# 5. Run the dev server (10.0.2.2 lets the Android emulator reach the host)
uv run python manage.py runserver 0.0.0.0:8000
```

### Tests
```bash
cd backend
uv run python manage.py test          # all 32 tests (auth/reports/alerts)
uv run python manage.py check
```

### Create a coordinator (for dashboard access)
```bash
cd backend
uv run python manage.py shell -c "
from apps.accounts.models import User
u, _ = User.objects.get_or_create(username='coord', defaults={'role':'COORDINATOR'})
u.set_password('strongpass123'); u.save()"
```

---

## Frontend setup & run (Flutter)

```bash
cd frontend/mobile
flutter pub get

# Android emulator (citizen app)
flutter emulators --launch resqmesh_avd      # create once: flutter emulators --create --name resqmesh_avd
flutter run -d <emulator-id>

# Web (coordinator dashboard)
flutter run -d chrome
```

### Tests
```bash
cd frontend/mobile
flutter test
flutter analyze
```

---

## API endpoints (v1)

- `POST /api/v1/auth/register/` — citizen self-registration
- `POST /api/v1/auth/login/` — JWT obtain
- `GET  /api/v1/auth/me/` — current user
- `POST/GET /api/v1/emergencies/` — create / list reports
- `GET/PATCH /api/v1/emergencies/{id}/` — detail / coordinator update
- `GET /api/v1/alerts/` — active alerts (citizens)
- `POST/PATCH /api/v1/alerts/` — create/update (coordinators only)
