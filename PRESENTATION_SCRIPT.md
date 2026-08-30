# ResQMesh — Live Presentation Script (code + running app)

A spoken, table-driven script that walks through **every layer of the code** while
**running the real program** at the same time. Each row tells you *what to say*,
*what to run/click*, and *what appears on screen*, so you can move straight from
explaining a file to demonstrating its behavior live.

> **Before presenting** run the full setup once (boot both emulators, install
> APK, grants, seed users) — see `test.md §2` and `BLUETOOTH_DEMO.md §2`.
> Two terminals are recommended: one for the backend, one for `adb`/curl.
> Total runtime ~12 minutes.

---

## Act 0 — The pitch (0:00–1:00)

> **Say:** "ResQMesh is a multi-user disaster-response platform with one core
> promise: *when the network dies, life-saving reports still get through.*
> Three layers — **Django backend**, **Flutter app**, **AI triage agents** — plus
> an **offline Bluetooth mesh** so a report authored with no signal still reaches
> the coordinator."

| Action | On screen |
|--------|-----------|
| Show both emulators + a Chrome tab with Django admin. | 5554 (citizen), 5556 (coordinator/mesh peer), `http://localhost:8000/admin/` |
| Open `README.md`'s stage table in the repo window. | The ✅ stages: 1 auth+reports+alerts, 2 AI, 3 relay, 3.5 BLE |

---

## Act 1 — The data model (1:00–2:30)

> **Say:** "Everything is a **REST resource** behind JWT auth. Let's show the
> two most important models and the real rows in the database."

| Start | Run | On screen |
|-------|-----|-----------|
| Open `backend/apps/emergencies/models.py`. | — | Show `EmergencyReport`: `reporter`, `description`, `incident_type`, `latitude`/`longitude`, `people_affected`, `status`, `priority`. |
| Open `backend/apps/accounts/models.py`. | — | Custom `User` with `role` = `CITIZEN`/`COORDINATOR`/`ADMIN`. |
| Login to Django admin inbound (either user). | `curl -s .../api/v1/emergencies/ -H "Authorization: Bearer $TOKEN"` | The actual rows rendered. |
| Open `backend/config/settings.py`. | — | Note `simplejwt`, DRF, the `apps.*` list, CORS, `AI_PROVIDER`. |

```bash
# show real data
T=$(curl -s -X POST localhost:8000/api/v1/auth/login/ -H 'Content-Type: application/json' \
   -d '{"username":"coorddemo","password":"strongpass123"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['access'])")
curl -s localhost:8000/api/v1/emergencies/ -H "Authorization: Bearer $T" | python3 -m json.tool | head -40
```

---

## Act 2 — Authentication (2:30–4:00)

> **Say:** "Rooms-based roles: citizens submit, coordinators triage, admins govern.
> Login issues a short-lived JWT access token — and it's **persisted on device**
> (`shared_preferences`), so reloading the app keeps you logged in."

| Start | Run | On screen |
|-------|-----|-----------|
| Open `backend/apps/accounts/views.py` + `serializers.py`. | — | `register`, `login` (JWT), `me`; role enforcement. |
| Open `frontend/mobile/lib/services/auth_state.dart`. | — | `restoreSession()` loads the token, validates via `/me`, sets `ready`; the splash gate in `main.dart`. |
| **Live:** On 5554/5556 are already logged in. | Pull-to-reload / restart an app on an emulator. | Reopens straight to the home screen — **no re-login** (token persisted). |
| register a brand-new citizen. | `curl -X POST .../register/ -d '{"username":"d","password":"x","role":"CITIZEN"}'` | 201 + token. |

```bash
curl -s -X POST localhost:8000/api/v1/auth/login/ -H 'Content-Type: application/json' \
  -d '{"username":"smokecit","password":"strongpass123"}'   # -> { "access": "...", "role": "CITIZEN" }
```

---

## Act 3 — Citizen report form + **automatic GPS location** (4:00–6:00)

> **Say:** "The Get Help form captures the reporter's **current GPS position
> automatically** — nobody in an emergency can calmly type a 9-decimal lat/long,
> so we read it from the device with `geolocator` the moment the form opens, and
> it rides along with the report whether it's sent online or buffered offline."

| Start | Run | On screen |
|-------|-----|-----------|
| Open `frontend/mobile/lib/screens/citizen/report_form_screen.dart`. | — | `_captureLocation()` (permission flow) runs in `initState`; the **location card** shows `lat, lng · GPS (±<n> m) — sent automatically`; **no** lat/lng TextFields. |
| Open AndroidManifest. | — | `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` declared. |
| **Live:** On 5554. | Tap **GET HELP**. | Form appears with the location card already filled by GPS (mock `27.717198, 85.323998`). |
| Type a description + pick **FIRE**. | Tap **SEND EMERGENCY REPORT**. | Snackbar "Report submitted … RQ-" |
| Open the report you just made. | `curl .../emergencies/` (or check 5554 My Reports / coordinator). | `latitude`/`longitude` populated from GPS. |

> **Fake GPS on an emulator** for a stable demo coordinate:
> ```bash
> adb -s emulator-5554 shell appops set com.resqmesh.resqmesh android:mock_location allow
> adb -s emulator-5554 shell settings put secure mock_location 1
> adb -s emulator-5554 emu geo fix 85.3240 27.7172     # <lon> <lat>
> ```

---

## Act 4 — Coordinator dashboard + **AI triage** (6:00–8:00)

> **Say:** "Every report is auto-analysed by an AI pipeline — extraction,
> uncertainty, and a priority recommendation with a **safety floor** that never
> under-triages life-threatening signals. The coordinator reviews and applies it."

| Start | Run | On screen |
|-------|-----|-----------|
| Open `backend/apps/agents/*` (providers, services, schemas, prompts). | — | Provider abstraction: `mock`/`ollama` interchangeable behind one interface; `post_save` triggers analysis; `_floor_priority` guardrail. |
| Open `frontend/mobile/lib/screens/coordinator/report_detail_screen.dart`. | — | AI suggestion panel + **status/priority chips** that stage changes, **SAVE CHANGES** button applies them. **DELETE REPORT** appears only for **admins** (a normal coordinator never sees it — the backend also rejects it with 403). |
| **Live:** On 5556 (coordinator app) or Chrome. | Open the report you just created. | AI SUGGESTION pane shows suggested priority/incident/uncertainty/rationale. |
| On 5556. | Tap **Accept suggested priority** (or chip + **SAVE CHANGES**). | Chips set pending values, snackbar "Saved RQ-n: status · priority"; API `PATCH` persisted. |
| Delete policy beat. | As `smokecit` on 5554 open **My Reports** → tap the red trash icon. | Only the **sender** can delete their own; `coorddemo` gets **403**; admins can delete anything. |

```bash
# prove the safety floor: a collapse would never be triaged below HIGH
uv run python manage.py shell -c \
 "from apps.agents.services import run_analysis; r=run_analysis('Two people trapped in a collapsed building','BUILDING_COLLAPSE'); print(r['priority_suggestion'], r['rationale'])"
```

---

## Act 5 — Official alerts (8:00–9:00)

> **Say:** "Coordinators broadcast official alerts; citizens see only **active** ones."

| Start | Run | On screen |
|-------|-----|-----------|
| Open `backend/apps/alerts/models.py` (expiry/`effective_status`) + `views.py`. | — | Coordinator-only create/update; citizens read. |
| **Live:** 5556 → **Create official alert** ("Flood warning", HIGH). | 5554 → **Alerts** tab. | The active alert appears on the citizen's screen. |

---

## Act 6 — The offline BLE mesh (9:00–11:30) — **the highlight**

> **Say:** "Now the kill-shot: we **stop the server**, submit a report anyway,
> and the app hands it **phone-to-phone over Bluetooth** — a self-contained
> envelope (origin, payload, TTL, hop count) carried store-and-forward until any
> node reaches the server. And it's **bondless**: we patched the BLE plugin so no
> OS 'Pair with…' dialog ever blocks an unconscious sender."

| Start | Run | On screen |
|-------|-----|-----------|
| Open `frontend/mobile/lib/services/relay/relay_envelope.dart` + `relay_manager.dart` + `ble_transport.dart`. | — | Envelope framing (`R1|<id>|<off>|<tot>|<b64>`), outbox/inbox, broadcast `received` stream, hop/TTL. |
| Open `frontend/mobile/plugins/ble_peripheral/.../BlePeripheralPlugin.kt`. | — | The vendored `createBond()` removal (bondless). |
| **Live — stop the server.** | `pgrep -af runserver` → `kill <pids>`; verify `curl` dead. | Backend terminal. |
| **Live:** 5554 submit a second report offline. | **GET HELP** → type → **SEND**. | Snackbar "No connection — report saved offline"; card → **`1 queued`**. |
| Wait for the hop. | `adb -s emulator-5556 logcat -d | grep '\[relay'` | `inbox + <id> origin=smokecit`; 5556 card → **`1 carried`**. |
| **The "message received" popup** | watch 5556 | Floating snackbar: **"Message received — From smokecit: <summary>"**. |
| Restart the server. | `nohup uv run python manage.py runserver 0.0.0.0:8000 --noreload &` | Backend terminal. |
| Carrier delivers. | 5556 logcat / tap **Sync now**. | `delivered 1 to server`; `curl .../relay/messages/` shows `DELIVERED` + `report_id`; cards settle to `0·0`. |

```bash
pgrep -af runserver                       # find PIDs
kill <pids>                               # take backend down
adb -s emulator-5554 logcat -d | grep '\[relay'   # -> outbox +
adb -s emulator-5556 logcat -d | grep '\[relay'   # -> inbox + ... origin=smokecit
# restart backend, then:
adb -s emulator-5556 logcat -d | grep '\[relay'   # -> delivered 1 to server
curl -s localhost:8000/api/v1/relay/messages/ -H "Authorization: Bearer $T" | python3 -m json.tool
```

> **The relayed GPS coordinates carry through the mesh too** — the payload in the
> envelope includes lat/long, and `backend/apps/relay/services.py` `_materialize_report`
> persists them into the real `EmergencyReport` on the server.

---

## Act 7 — Wrap-up + Q&A (11:30–12:00)

| # | Say |
|---|-----|
| 1 | "The same recovery path is behind **Sync now** — manual flush on demand; it's the mesh made visible." |
| 2 | "Extensible to **multi-hop** (max 8 hops, 24 h TTL, dedup by `message_id`), and the AI is a **swappable provider** (mock for deterministic demos, Ollama for a real local model)." |
| 3 | "And because the mesh is **bondless**, a report handed off over BLE works even if the sender is unconscious and can tap nothing." |

---

## App–code map (quick reference for Q&A)

| What you see | Where it lives |
|--------------|----------------|
| Login/session persistence | `frontend/mobile/lib/services/auth_state.dart`, `api_service.dart` (`shared_preferences`) |
| Report form + auto-GPS | `frontend/mobile/lib/screens/citizen/report_form_screen.dart`, `geolocator` |
| Coordinator review + AI panel + SAVE CHANGES | `frontend/mobile/lib/screens/coordinator/report_detail_screen.dart` |
| "Message received" popup | `frontend/mobile/lib/widgets/mesh_notification_listener.dart` |
| Offline outbox/inbox, envelope, framing, relay | `frontend/mobile/lib/services/relay/*` |
| Offline-safe Sync now + friendly offline screens | `relay_manager.dart` `flush()` (never throws), `isNetworkError` in `api_service.dart` |
| Delete (sender's own / admin-only) | `backend/apps/emergencies/permissions.py` (`MayDeleteReport`); citizen `my_reports_screen.dart`; coordinator `report_detail_screen.dart` |
| Bondless BLE patch (no pairing dialog) | `frontend/mobile/plugins/ble_peripheral/.../BlePeripheralPlugin.kt` |
| Backend models/endpoints | `backend/apps/{accounts,emergencies,alerts,agents,relay,notifications}/` |
| AI provider abstraction + safety floor | `backend/apps/agents/{providers,services,prompts}.py` |
| Relay delivery + coord materialization | `backend/apps/relay/{services,connectivity,views}.py` |
| Config (JWT, CORS, apps, AI) | `backend/config/settings.py` |
| Manual test guide / BLE demo | `test.md`, `BLUETOOTH_DEMO.md` |
