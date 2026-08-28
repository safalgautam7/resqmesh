# ResQMesh — PROGRESS.md

> **Living progress tracker.** Every agent MUST update this file after each bounded task,
> append its report (see phase.md §7 format), and mark the corresponding milestone `[x]`.
> Commit and tag the milestone (e.g. `M0`, `M1`, ...) when it reaches definition-of-done.

- Start: Aug 2026 · 3-day hackathon (Day 1 = Phase 1, Day 2 = Phase 2, Day 3 = Phase 3)
- Source of truth for features/tests: `ResQMesh — Project Goal and Development Plan.md`, `architecture.md`, `phase.md`

## Definitions of done
- `manage.py check` passes, `manage.py test` passes, `flutter test` passes at each Stage-0 gate.
- Backend permissions enforced server-side (never trust client).
- Original citizen report is never overwritten by AI.
- AI provider is replaceable behind one interface; mock fallback keeps tests deterministic.
- Every agent ends with a report in the phase.md format appended under its milestone.

---

## Milestones

### M0 — Bootstrap
- [x] Root git repo + PROGRESS.md created
- [x] Android SDK env vars set (ANDROID_HOME, ANDROID_SDK_ROOT)
- [x] Android emulator package + system image installed, AVD created
- [x] docker-compose Postgres running
- [x] Django project scaffolded (`backend/config`) with apps skeleton
- [x] Deps added (psycopg, cors, simplejwt, environ)
- [x] `.env` / `.env.example` created
- [x] Custom user model added
- [x] Flutter project scaffolded
- [x] Gates pass: `manage.py check`, `manage.py test`, `flutter test`

### M1 — Authentication
- [x] register/login/logout/me endpoints (JWT)
- [x] Roles CITIZEN / COORDINATOR / ADMIN
- [x] Permission enforcement (coordinator/admin not self-created)
- [x] Tests (10+)

### M2 — Emergency Reports
- [x] `EmergencyReport` model
- [x] API (create/list/detail/patch)
- [x] Ownership + role rules
- [x] Priority/status updates
- [x] Tests (10+)

### M3 — Official Alerts
- [x] `OfficialAlert` model
- [x] API (read for citizens; create/update gated)
- [x] Expiry handling
- [x] `NotificationProvider` abstraction
- [x] Tests (8+)

### M4/M5 — Flutter UI (citizen + coordinator)
- [x] Get Help form (categories, optional location, people)
- [x] My Reports screen
- [x] Alerts screen
- [x] Coordinator dashboard (role-gated, web)
- [x] Coordinator report detail + status/priority actions
- [x] E2E manual exit test

### M6 — Agent abstraction + Extraction
- [ ] Provider interface (base/ollama/mock)
- [ ] Extraction agent (incident type, people, injuries, location hints, assistance)

### M7 — Uncertainty + Priority agents
- [ ] Uncertainty detection (known/unknown/uncertain/contradiction)
- [ ] Priority recommendation (CRITICAL/HIGH/MEDIUM/LOW) + reasons

### M8 — AI Evaluation
- [ ] 10–20 synthetic cases in `evaluation/cases/`
- [ ] Baseline (single prompt) run
- [ ] Final workflow run
- [ ] Real metrics recorded in `evaluation/results/`

### M9 — Human review + AI failure handling
- [ ] Coordinator Accept/Modify UI
- [ ] AI failure does not break reporting
- [ ] Original report preserved test

### M10 — Local outbox
- [ ] Outbox model + connectivity detection

### M11 — Store-carry-forward
- [ ] Inventory exchange + missing-message sync service

### M12 — Relay rules
- [ ] Dedup, TTL/expiry, hop limits

### M13 — Stage 3 E2E + tests
- [ ] 7 relay tests (offline save, recovery, direct relay, multi-hop, duplicate, expiration, full recovery)

---

## Agent reports (append below, newest last)

## Phase 1 (Day 1) — M0..M5 complete
## Implemented
- M0: root git repo, PROGRESS.md, Android SDK env vars, emulator+AVD (resqmesh_avd), docker-compose Postgres, Django project (`backend/config`) with apps pkg, deps (psycopg, cors, simplejwt, environ), `.env`, custom User, Flutter scaffold.
- M1: JWT auth (register/login/me) with roles, permission helpers.
- M2: EmergencyReport model+API (ownership + role rules, priority/status).
- M3: OfficialAlert model+API (expiry via effective_status, NotificationProvider abstraction).
- M4/M5: Flutter citizen app (Get Help form, My Reports, Alerts) + coordinator dashboard (list/filter, report detail status/priority, create alert), role-gated; runs on Android emulator and web.
## Files Changed
- backend/config/*, backend/apps/{accounts,emergencies,alerts,notifications}/*, backend/pyproject.toml, backend/.env(.example), docker-compose.yml, frontend/mobile/{lib,test,pubspec.yaml}, PROGRESS.md, .gitignore
## Tests Added
- accounts: 8 · emergencies: 14 · alerts: 10 · flutter widget smoke test: 1
## Tests Run
- `manage.py test` -> 32 passed · `flutter test` -> 1 passed · `flutter analyze` -> clean · `flutter build apk --debug` -> OK · app launches on emulator
## Result
PASS
## Notes
- Backend HTTP flow verified: citizen register/login/report; coordinator login/view/patch/create alert; citizen sees alert, denied alert create + priority change.
- Emulator + backend run detached. Backend dev server: `manage.py runserver 0.0.0.0:8000`.

<!-- Format:
## M<x> — <short task>
## Implemented
- ...
## Files Changed
- ...
## Tests Added
- ...
## Tests Run
- ...
## Result
PASS / FAIL
## Notes
- ...
-->
