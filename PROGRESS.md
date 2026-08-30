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
- [x] Provider interface (base/ollama/mock)
- [x] Extraction agent (incident type, people, injuries, location hints, assistance)

### M7 — Uncertainty + Priority agents
- [x] Uncertainty detection (known/unknown/uncertain/contradiction)
- [x] Priority recommendation (CRITICAL/HIGH/MEDIUM/LOW) + reasons
- [x] Safety floor guardrail (never under-triage life-threatening signals)

### M8 — AI Evaluation
- [x] Synthetic cases (+ baseline + workflow) in `apps/agents/evaluation.py`
- [x] Baseline (no-AI keyword classifier) run
- [x] Final workflow run (mock and real ollama provider)
- [x] Metrics recorded via `evaluate_agents` command + agent report

### M9 — Human review + AI failure handling
- [x] Coordinator Accept/Modify UI (AI suggestion panel + Accept on report detail)
- [x] AI failure does not break reporting
- [x] Original report preserved test

### M10 — Local outbox
- [x] Outbox model + connectivity detection (`RelayMessage` delivery_state, `RelayDevice` online, `connectivity.NodeState`)

### M11 — Store-carry-forward
- [x] Inventory exchange + missing-message sync service (`DeviceStore`, `exchange`, `recover_to_backend`)

### M12 — Relay rules
- [x] Dedup (global unique `message_id`), TTL/expiry, hop limits (`is_expired`/`max_hops`)

### M13 — Stage 3 E2E + tests
- [x] 7 relay tests (offline save, single-device recovery, direct relay, multi-hop, duplicate, expiration, full recovery)
- [x] `relay_demo` command (A -> B -> C -> Django recovery demonstration)

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

## Phase 2 (Day 2) — M6..M8 complete
## Implemented
- M6: Provider abstraction (`agents/providers/{base,ollama,mock}.py` + factory `get_provider`). Ollama uses native `format:"json"`; mock is deterministic keyword-based. `AgentAnalysis` model + `analyze_reports` management command. Extraction agent (incident/people/injuries/location/assistance).
- M7: Uncertainty + Priority agents with `schemas.py` normalization/validation (glitch-safe) + **safety floor** guardrail that never under-triages life-threatening signals (bleeding/unconscious/burns→CRITICAL floor; collapse/fire/trapped→HIGH floor).
- Analysis auto-triggered on report creation via `post_save` receiver (wrapped so AI failure never breaks ingestion). Exposed to coordinator via `EmergencyReportDetailSerializer` (`analysis` field, includes `suggested_priority`).
- M8: Evaluation harness `apps/agents/evaluation.py` + `evaluate_agents` management command: 6 scripted ground-truth cases, baseline (no-AI keyword) vs pipeline, per-case + aggregate metrics, pipeline-value delta.
## Files Changed
- backend/apps/agents/* (providers/, prompts.py, schemas.py, services.py, models.py, admin.py, evaluation.py, management/commands/, migration 0001), backend/apps/emergencies/{services,serializers,views}.py, backend/pyproject.toml (+requests), backend/.env(.example) AI_MODEL.
## Tests Added
- agents: 19 (providers, schemas, workflow, API exposure, failing-provider resilience, safety floor, evaluation harness). Total backend 51.
## Tests Run
- `manage.py test` -> 51 passed · `evaluate_agents --provider mock` -> incident 0.833, priority 1.0, people 0.6 · `--provider ollama` (qwen2.5-coder:1.5b) -> incident 0.667-0.833, people 0.6-0.8, priority noisy.
## Result
PASS
## Notes
- Real model pull target `qwen2.5:1b` failed in this environment (registry "file does not exist"); used local `qwen2.5-coder:1.5b` instead (configurable via AI_MODEL).
- EVALUATION FINDING: local 1.5B model matches mock on extraction/people but is noisy + under-triages priority (non-deterministic run-to-run). Safety floor bounds the worst under-triage. Conclusion: mock is the reliable safe default for triage in this env; LLM adds free-text extraction value, needs a stronger model for nuanced priority. Mock pipeline beats baseline by +0.5 priority accuracy at 0 risk.

## Phase 2 (Day 2) — M9 complete
## Implemented
- Coordinator report-detail screen now loads the full report via `GET /emergencies/{id}/` and renders an "AI SUGGESTION" panel: suggested priority (colored), incident type, uncertainty score/level, rationale, provider. "Accept suggested priority" button applies it via the existing PATCH (modify remains via status/priority chips).
- Added `getReportDetail` to ApiService, `AgentAnalysis` Flutter model, `EmergencyReport.fromJsonDetail`.
## Files Changed
- frontend/mobile/lib/models/{agent_analysis,emergency_report}.dart, lib/services/api_service.dart, lib/screens/coordinator/report_detail_screen.dart
## Tests Added
- N/A (UI). Backend detail/serializer covered in agents tests.
## Tests Run
- `flutter analyze` -> clean · `flutter test` -> 1 passed · E2E API: report create -> detail has analysis (extraction/uncertainty/priority, suggested CRITICAL, provider mock) -> coordinator PATCH applies CRITICAL -> citizen PATCH denied (stays CRITICAL) -> original report preserved (priority UNASSIGNED until accept).
## Result
PASS
## Notes
- Backend dev server restarted (--noreload) to pick up Stage 2 code; post_save agent analysis runs on each new report.

## Phase 3 (Day 3) — M10..M13 complete
## Implemented
- M10: `apps/relay` app. `RelayMessage` (global unique `message_id`, payload, `expires_at` TTL, `hop_count`/`max_hops`, `delivery_status`, `synced_to_server`) + `RelayDevice` (online flag, carried_messages M2M) models; `connectivity.py` (NodeState online/offline + `should_buffer_message`).
- M11: `DeviceStore` (per-device virtual node) with `exchange()` two-way inventory sync + `recover_to_backend()`; a relayed payload is materialized as a real `EmergencyReport` on delivery.
- M12: relay rules — dedup (unique `message_id`, set-based presence), TTL (`is_expired` -> not relayed), hop limit (`hop_count >= max_hops` -> stop).
- M13: `apps/relay/tests.py` (7+ scenario tests) + `manage.py relay_demo` printing the full recovery loop.
- **Post-M13 — Automatic GPS location:** Get Help form captures the reporter's **current GPS position** on form-open via `geolocator` (no manual lat/long fields); coordinates flow into the online report AND the offline relay envelope, and `_materialize_report` now persists `latitude`/`longitude` for relayed reports. Android manifest declares `ACCESS_FINE/COARSE_LOCATION`. Docs updated (`README`, `test.md`, `BLUETOOTH_DEMO.md`, new `PRESENTATION_SCRIPT.md`). `flutter test` 7 pass, `manage.py test apps.relay` 11 pass, `flutter analyze` clean.
## Files Changed
- backend/apps/relay/* (models, services, connectivity, admin, migration 0001, management/commands/relay_demo), backend/config/settings.py (+apps.relay)
- frontend/mobile/pubspec.yaml (+`geolocator`), android/app/src/main/AndroidManifest.xml (+location perms), lib/screens/citizen/report_form_screen.dart (auto-GPS), backend/apps/relay/services.py (persist coords), PRESENTATION_SCRIPT.md (new), README.md, test.md, BLUETOOTH_DEMO.md
## Tests Added
- relay: 8 (offline save, single-device recovery, direct relay, multi-hop, duplicate, expiration, full recovery, hop-limit). Total backend 59.
## Tests Run
- `manage.py test` -> 59 passed · `manage.py relay_demo` -> A(offline) create -> A->B -> B->C -> C online -> Django receives EmergencyReport #4.
## Result
PASS
## Notes
- Stage 3 modelled with in-process virtual relay nodes (per plan) + persistent `carried_by` M2M; physical Bluetooth transport is a later swap-in behind the same services. DB container was restarted during this phase (docker compose up -d db).
- GPS verified live on emulator-5554: form shows mock Kathmandu coordinate `27.717198, 85.323998 · GPS location (±5 m) — sent automatically`.

## Phase 3 (Day 3) — Post-M13 hardening
## Implemented
- **Offline-safe `flush()` / Sync now**: `RelayManager.flush()` no longer throws when the backend is down (previously an unhandled exception fired from Sync now and the 20 s timer). Envelopes stay buffered and the mesh card reads "server unreachable — will retry automatically".
- **Friendly offline screens**: report list/detail and alerts UI render a "No connection to the server" state via `isNetworkError(...)` instead of a raw `SocketException`/`ClientException`.
- **Report deletion (owner-or-admin)**: `DELETE /emergencies/{id}/` added (`DestroyModelMixin`). Policy in `MayDeleteReport`: the **sender** may delete their own report; **admins/superusers** may delete anything; a **normal coordinator cannot** (403). Foreign citizens get 404 (queryset-filtered).
## Files Changed
- frontend/mobile/lib/services/{api_service,relay/relay_manager}.dart, lib/screens/citizen/{my_reports_screen,alerts_screen}.dart, lib/screens/coordinator/{coordinator_home_screen,report_detail_screen}.dart
- backend/apps/emergencies/{permissions,views,tests}.py
- README.md, test.md, PRESENTATION_SCRIPT.md
## Tests
- backend total 67 (19 emergencies incl. 5 new delete-policy tests) · `flutter test` 7 pass · `flutter analyze` clean · debug APK rebuilt & reinstalled on both emulators.
## Result
PASS

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
