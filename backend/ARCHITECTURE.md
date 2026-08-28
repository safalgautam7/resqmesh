# ResQMesh Backend — Structure & Data Flow

Explains what each directory/file in `backend/` does and how data currently
flows through the system (Phase 1 + 2: auth, emergency reports, official alerts,
and the AI agent pipeline).

---

## Overview

```
Request → config/urls.py → app/urls.py → app/views.py → serializer (validate)
        → services.py (business logic) → models.py (DB)
        → response back through serializer
                 │
                 └─ signals/services trigger side effects (agent analysis, notifications)
```

Django + Django REST Framework + PostgreSQL. Auth via JWT (djangorestframework-simplejwt).
Each "app" owns one domain and follows the same pattern: `models` → `serializers` →
`views` → `urls`, with `services.py` holding business logic and `tests.py` holding tests.

---

## Directory map

### `config/` — project bootstrap
| File | Purpose |
|------|---------|
| `settings.py` | Env-driven config (django-environ): DB (Postgres/`DATABASE_URL`, SQLite fallback), JWT, CORS, allowed hosts, installed apps, and the `AI_PROVIDER`/`AI_MODEL`/`OLLAMA_URL` settings. |
| `urls.py` | Top-level router: `/admin/`, and mounts the three app URL configs under `/api/v1/`. |
| `asgi.py` / `wsgi.py` | ASGI/WSGI entrypoints for running the server. |

`manage.py` — Django’s CLI entrypoint (migrate, shell, runserver, custom commands…).

### `apps/` — applications package
Each sub-folder is a Django app whose `apps.py` `name = 'apps.<app>'`.

#### `apps/accounts/` — users, roles, auth
| File | Purpose |
|------|---------|
| `models.py` | Custom `User` with `role` (CITIZEN/COORDINATOR/ADMIN) + `is_coordinator`/`is_admin` helpers. |
| `serializers.py` | `UserSerializer` (profile) + `RegisterSerializer` (creates a CITIZEN; `role` is stripped from input). |
| `views.py` | `RegisterView` (public), `MeView` (current user), and JWT login/refresh (`TokenObtainPairView`/`TokenRefreshView`). |
| `permissions.py` | `IsCoordinatorOrAdmin` guard used by other apps. |
| `urls.py` | `/auth/register|login|refresh|me`. |
| `tests.py` | 8 auth tests (register/login/refresh/role rules). |

#### `apps/emergencies/` — citizen reports + coordinator ops
| File | Purpose |
|------|---------|
| `models.py` | `EmergencyReport` (description, `incident_type`, lat/lng, `people_affected`, `status`, `priority`). Original description is never overwritten. |
| `serializers.py` | `EmergencyReportSerializer` (citizen; `status`/`priority` read-only), `CoordinatorReportSerializer` (mutable), `AgentAnalysisSerializer` + `EmergencyReportDetailSerializer` (detail exposes the `analysis`). |
| `views.py` | `EmergencyReportViewSet`: create/list/retrieve/update; citizens see own, coordinators see all, detail uses the analysis serializer. |
| `permissions.py` | `IsReporterOrCoordinator`. |
| `services.py` | `create_emergency_report(...)` (reporter from auth only) + `post_save` **signal** that triggers the AI agent pipeline; `update_report_operational(...)`. |
| `urls.py` | `/emergencies/` (DRF router → `POST/GET` `/`, `GET/PATCH` `/{id}`). |
| `tests.py` | 14 report tests (ownership, roles, validations). |

#### `apps/alerts/` — official alerts
| File | Purpose |
|------|---------|
| `models.py` | `OfficialAlert` (title, message, `severity`, `target_area`, `status`, `expires_at`) + `effective_status()`/`is_active` (ACTIVE unless expired/cancelled). |
| `serializers.py` | `OfficialAlertSerializer` (`created_by` read-only, exposes `effective_status`). |
| `views.py` | `OfficialAlertViewSet`: create/update are coordinator-only; **citizens only see active, non-expired** alerts; `perform_create` fires notification. |
| `services.py` | `notify_alert_created(...)` (goes through the notification provider). |
| `urls.py` | `/alerts/`. |
| `tests.py` | 10 alert tests (permissions, expiry, ordering). |

#### `apps/agents/` — AI agent pipeline (Phase 2)
| File | Purpose |
|------|---------|
| `models.py` | `AgentAnalysis` — OneToOne with a report; stores `extraction`, `uncertainty`, `priority`, `duplicate` JSON + `provider`/`model`/`is_available`/`error`. Never mutates the report. |
| `providers/base.py` | `AnalysisProvider` abstraction (shared helpers, error-safe result shape). |
| `providers/ollama.py` | `OllamaProvider` — calls local Ollama with `format:"json"`, tolerant JSON parsing, failure fallback. |
| `providers/mock.py` | `MockProvider` — deterministic rule/keyword analysis (offline/reproducible). |
| `providers/__init__.py` | `get_provider()` factory (resolves `AI_PROVIDER` setting). |
| `prompts.py` | Prompt builders for the extraction/uncertainty/priority/duplicate agents. |
| `schemas.py` | Normalization/validation of raw provider output into canonical safe shapes (glitch-proof). |
| `services.py` | `analyze_report(...)` — orchestrates extraction → uncertainty → priority → duplicate, applies the **safety floor** (never under-triage), persists `AgentAnalysis`. |
| `evaluation.py` | Evaluation harness: ground-truth cases, no-AI baseline vs agent pipeline, aggregate metrics. |
| `management/commands/analyze_reports.py` | Re-run/backfill analysis on reports. |
| `management/commands/evaluate_agents.py` | Print the baseline-vs-pipeline evaluation report. |
| `tests.py` | 19 tests (providers, schemas, workflow, failing-provider resilience, safety floor, evaluation). |

#### `apps/notifications/` — notification abstraction
| File | Purpose |
|------|---------|
| `services.py` | `NotificationProvider` abstraction (currently a console provider) — the seam where real push/SMS providers plug in later. |
| `models.py`/`views.py`/`tests.py` | Mostly placeholders/extensions of the abstraction. |

---

## How data flows through the system

### A. Citizen registers & authenticates
1. `POST /api/v1/auth/register/` → `RegisterSerializer` → `User.objects.create_user`
   → returns profile (`role = CITIZEN`).
2. `POST /api/v1/auth/login/` → JWT pair (`access`, `refresh`).
3. Every later request carries `Authorization: Bearer <access>`.

### B. Citizen submits an emergency report
1. `POST /api/v1/emergencies/` (citizen token) → `EmergencyReportSerializer`
   validates (coordinates together, valid incident type) → `ReportViewSet.perform_create`
   sets `reporter` from **auth** → `services.create_emergency_report(...)`.
2. Report saved with `status=SUBMITTED`, `priority=UNASSIGNED` (original preserved).
3. A **`post_save` signal** then runs `agents.services.analyze_report(report)`:
   - provider resolves (mock by default),
   - **Extraction** → incident type, people, injuries, location, assistance;
   - **Uncertainty** → score/level/flags;
   - **Priority** → suggested priority + rationale, then the **safety floor** raises it if life-threatening;
   - **Duplicate** → compares against other open reports;
   - normalized via `schemas`, stored into an `AgentAnalysis` row linked to the report.
   - Failures are caught — the report exists and returns **regardless**.
4. `201` → serialized report returned to the citizen.

### C. Coordinator reviews & takes action
1. `GET /api/v1/emergencies/` (coordinator) → **all** reports.
2. `GET /api/v1/emergencies/{id}/` → `EmergencyReportDetailSerializer` returns the
   report **plus** its `analysis` (suggested priority, uncertainty, rationale, provider).
3. Coordinator **accepts** the AI suggestion or sets values via
   `PATCH /api/v1/emergencies/{id}/` (`priority`, `status`) → `update_report_operational`.
   Citizens cannot change these (read-only for them; original value preserved).

### D. Coordinate official alerts
1. `POST /api/v1/alerts/` (coordinator) → creates alert, `created_by` from auth, then
   `notify_alert_created` → `NotificationProvider`.
2. `GET /api/v1/alerts/`:
   - coordinator → all alerts;
   - citizen → only `ACTIVE` + not expired.
3. Citizens get `403` when trying to create/update alerts.

### E. AI evaluation (dev tooling, not at request time)
`manage.py evaluate_agents --provider mock|ollama` runs the scripted ground-truth
cases through the same providers used in production and prints baseline-vs-pipeline
metrics (incident accuracy, priority accuracy, people accuracy, deltas).

---

## Security rules (enforced in code)
- Role is **never** read from the request body — it comes from the authenticated `User`.
- `reporter` / `created_by` always come from `request.user`, never the client.
- Citizens can only read their own reports; only coordinators mutate status/priority.
- Only coordinators/admin create alerts; citizens see active ones only.
- The AI never overwrites the citizen’s original description — suggestions live in `AgentAnalysis`.

---

## Where things go next (Phase 3)
The `notifications/` provider and the plan’s M10–M13 (offline outbox, store-carry-forward
relay, dedup/TTL/hop rules) will add a transport/messaging layer. The
`NotificationProvider` abstraction in `apps/notifications/services.py` is the seam
where that plugs in.
