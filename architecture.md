# ResQMesh — Architecture

## 1. Purpose

ResQMesh is a multi-user emergency communication and coordination platform.

The system has two main goals:

1. Let citizens quickly report emergencies and receive official alerts.
2. Help emergency coordinators process, organize, and prioritize large numbers of reports.

The first implementation uses **Django + Django REST Framework + PostgreSQL** as the backend and a **Flutter** mobile application for citizens.

AI is an assisting layer. It must never become a hard dependency for basic emergency communication.

Future phases add offline storage and Bluetooth/local peer-to-peer forwarding.

---

# 2. High-Level Architecture

```text
                           ┌───────────────────────┐
                           │ Emergency Coordinator │
                           │      Web Dashboard    │
                           └───────────┬───────────┘
                                       │
                                       │ HTTPS / REST
                                       ▼
┌─────────────────┐          ┌───────────────────────┐
│  Flutter Mobile │ HTTPS    │       Django API      │
│      Client     │◄────────►│                       │
└────────┬────────┘          │ Auth                  │
         │                   │ Reports               │
         │                   │ Official Alerts       │
         │                   │ Users / Roles         │
         │                   │ Agent Orchestration   │
         │                   └──────┬───────┬────────┘
         │                          │       │
         │                          │       │
         │                          ▼       ▼
         │                   ┌──────────┐ ┌──────────┐
         │                   │PostgreSQL│ │Agent     │
         │                   │          │ │Workflow  │
         │                   └──────────┘ └────┬─────┘
         │                                     │
         │                                     ▼
         │                              Structured Analysis
         │
         │ Future Stage 3
         ▼
┌──────────────────────────────────────────────────────────┐
│               Local / Offline Communication               │
│                                                          │
│  Local Message Store → Bluetooth / Wi-Fi P2P → Peer App │
└──────────────────────────────────────────────────────────┘
```

---

# 3. Repository Structure

The recommended monorepo is:

```text
resqmesh/
│
├── README.md
├── goal.md
├── architecture.md
├── phase.md
├── .env.example
├── .gitignore
├── docker-compose.yml
│
├── backend/
│   ├── manage.py
│   ├── requirements.txt
│   │
│   ├── config/
│   │   ├── __init__.py
│   │   ├── settings.py
│   │   ├── urls.py
│   │   ├── asgi.py
│   │   └── wsgi.py
│   │
│   ├── apps/
│   │   ├── accounts/
│   │   ├── emergencies/
│   │   ├── alerts/
│   │   ├── agents/
│   │   └── notifications/
│   │
│   └── tests/
│
├── frontend/
│   └── mobile/
│       ├── pubspec.yaml
│       ├── lib/
│       │   ├── main.dart
│       │   ├── core/
│       │   ├── models/
│       │   ├── services/
│       │   ├── features/
│       │   └── widgets/
│       └── test/
│
├── evaluation/
│   ├── cases/
│   ├── baseline/
│   ├── agent/
│   └── results/
│
└── docs/
    └── decisions/
```

The exact structure may be adjusted during implementation, but responsibilities must remain separated.

---

# 4. Backend Architecture

## 4.1 `backend/config/`

This is the Django project configuration.

### `settings.py`

Responsible for:

- Django settings
- installed apps
- database configuration
- REST Framework configuration
- authentication configuration
- CORS configuration
- environment variables
- logging

Secrets must come from environment variables.

Never commit:

- API keys
- database passwords
- private signing keys
- production credentials

### `urls.py`

Top-level API routing.

Example:

```text
/api/v1/auth/
/api/v1/emergencies/
/api/v1/alerts/
/api/v1/users/
```

### `asgi.py`

ASGI entry point for:

- async deployment
- future WebSocket support

### `wsgi.py`

WSGI entry point for conventional Django deployment.

---

# 5. Accounts App

```text
backend/apps/accounts/
├── models.py
├── serializers.py
├── views.py
├── urls.py
├── permissions.py
├── admin.py
└── tests/
```

## Responsibility

Everything related to users and roles.

Initial roles:

```text
CITIZEN
COORDINATOR
ADMIN
```

### `models.py`

Contains the custom user model and, if required later, profile information.

### `serializers.py`

Converts user data between Python objects and API representations.

### `views.py`

Authentication/user endpoints.

### `permissions.py`

Central place for role-based access rules.

Example:

```text
Citizen:
    Can create reports
    Can view own reports
    Can receive alerts

Coordinator:
    Can view reports
    Can review reports
    Can manage operational status
    Can create alerts if authorized

Admin:
    Can manage users and system configuration
```

### `tests/`

Authentication and permission tests.

---

# 6. Emergencies App

```text
backend/apps/emergencies/
├── models.py
├── serializers.py
├── views.py
├── urls.py
├── services.py
├── permissions.py
├── admin.py
└── tests/
```

This is the core citizen-reporting module.

## `models.py`

The central model is `EmergencyReport`.

Suggested fields:

```text
id
reporter
description
incident_type
latitude
longitude
location_accuracy
people_affected
status
priority
created_at
updated_at
```

Possible status values:

```text
SUBMITTED
REVIEWING
VERIFIED
IN_PROGRESS
RESOLVED
CLOSED
```

Possible priority values:

```text
CRITICAL
HIGH
MEDIUM
LOW
UNASSIGNED
```

The exact model should evolve with implementation.

## `serializers.py`

Responsible for:

- request validation
- response formatting
- ensuring invalid data cannot enter the system

## `views.py`

Responsible for HTTP/API behavior.

Example:

```text
POST /api/v1/emergencies/
GET  /api/v1/emergencies/
GET  /api/v1/emergencies/{id}/
```

Citizens should only access their own reports.

Coordinators can access operational reports.

## `services.py`

Business logic that should not be embedded directly inside views.

Examples:

```text
create_emergency_report()
update_report_status()
assign_report()
request_agent_analysis()
```

This keeps views thin.

---

# 7. Alerts App

```text
backend/apps/alerts/
├── models.py
├── serializers.py
├── views.py
├── urls.py
├── services.py
├── permissions.py
├── admin.py
└── tests/
```

This represents **official emergency alerts**.

An alert is not the same thing as a citizen report.

Example:

```text
Citizen report:
"I see water rising near the river."

Official alert:
"Flood warning: residents in Zone A should move
to designated safe areas."
```

## Suggested model

```text
OfficialAlert
    id
    title
    message
    severity
    target_area
    status
    created_by
    created_at
    expires_at
```

Future fields may include:

```text
signature
version
source_authority
geographic_polygon
```

---

# 8. Agents App

```text
backend/apps/agents/
├── services.py
├── schemas.py
├── prompts/
│   ├── extraction.txt
│   ├── uncertainty.txt
│   ├── priority.txt
│   └── duplicate.txt
├── providers/
│   ├── base.py
│   ├── hosted.py
│   └── local.py
└── tests/
```

This module isolates AI from the rest of the application.

The rest of Django should not know whether the system uses:

- OpenAI
- another hosted API
- Ollama
- a self-hosted model
- a future local model

The application should communicate through an internal interface.

Example:

```python
result = emergency_analyzer.analyze(report)
```

rather than:

```python
openai_client.some_specific_call(...)
```

inside views.

This makes it possible to change the AI provider without rewriting the emergency system.

---

# 9. Agent Workflow

The initial workflow:

```text
Emergency Report
       │
       ▼
┌────────────────────┐
│ Extraction Agent   │
└─────────┬──────────┘
          ▼
Structured Information
          │
          ▼
┌────────────────────┐
│ Uncertainty Agent  │
└─────────┬──────────┘
          ▼
Uncertainty / Missing Data
          │
          ▼
┌────────────────────┐
│ Priority Agent     │
└─────────┬──────────┘
          ▼
Priority Recommendation
          │
          ▼
┌────────────────────┐
│ Duplicate Agent    │
└─────────┬──────────┘
          ▼
Possible Related Reports
          │
          ▼
Coordinator
```

Every agent result should contain enough information for a human to understand what the system concluded.

---

# 10. Agent Output

AI should return structured data, not arbitrary prose.

Example:

```json
{
  "incident_type": "BUILDING_COLLAPSE",
  "people_affected": {
    "value": 4,
    "confidence": "LOW",
    "source": "reporter_estimate"
  },
  "injuries": [
    {
      "description": "severe bleeding",
      "severity": "UNKNOWN"
    }
  ],
  "location_hint": "near Kathmandu University",
  "requested_assistance": [
    "RESCUE",
    "MEDICAL"
  ],
  "uncertainties": [
    "Exact building unknown",
    "Number of people is an estimate"
  ],
  "priority": "CRITICAL",
  "priority_reasons": [
    "People report being trapped",
    "Serious injury is reported"
  ]
}
```

The AI must not silently invent fields.

Unknown information should remain unknown.

---

# 11. Notifications App

```text
backend/apps/notifications/
├── services.py
├── providers/
│   ├── base.py
│   └── push.py
└── tests/
```

Responsible for notification delivery.

Example:

```text
Official Alert
     │
     ▼
Notification Service
     │
     ▼
Push Provider
     │
     ▼
Citizen Devices
```

The notification system should be decoupled from alert creation.

Creating an alert should create an alert record first, then trigger delivery.

---

# 12. Database

Use PostgreSQL.

Initial relationships:

```text
User
 │
 ├──────────────< EmergencyReport
 │
 └──────────────< OfficialAlert (for authorized creators)
```

Future relationship:

```text
EmergencyReport
       │
       ├── AgentAnalysis
       │
       ├── ReportEvent
       │
       └── RelayRecord
```

Keep audit/history data where decisions are important.

A future `ReportEvent` model can record:

```text
REPORT_CREATED
AI_ANALYZED
PRIORITY_CHANGED
ASSIGNED
VERIFIED
RESOLVED
```

---

# 13. Mobile Frontend Structure

```text
frontend/mobile/lib/
├── main.dart
│
├── core/
│   ├── constants/
│   ├── theme/
│   ├── routing/
│   ├── errors/
│   └── utils/
│
├── models/
│   ├── emergency_report.dart
│   ├── official_alert.dart
│   └── user.dart
│
├── services/
│   ├── api_service.dart
│   ├── auth_service.dart
│   ├── notification_service.dart
│   ├── location_service.dart
│   └── local_storage_service.dart
│
├── features/
│   ├── auth/
│   ├── home/
│   ├── emergencies/
│   ├── alerts/
│   └── profile/
│
└── widgets/
    ├── emergency_button.dart
    ├── alert_card.dart
    ├── report_status_card.dart
    └── loading_view.dart
```

---

# 14. Mobile Responsibility

The mobile application should primarily handle:

- authentication,
- presentation,
- collecting emergency information,
- local state,
- API communication,
- permissions,
- notifications.

It should NOT contain:

- database credentials,
- secret AI provider keys,
- authority private keys,
- business logic that must be trusted by the server.

The backend remains authoritative for security-sensitive operations.

---

# 15. Main Data Flow — Citizen Report

```text
1. Citizen opens app
        │
        ▼
2. Taps "Get Help"
        │
        ▼
3. Enters emergency description
        │
        ├── optional location
        ├── optional people count
        └── optional photo/voice in future
        │
        ▼
4. Flutter validates input
        │
        ▼
5. POST /api/v1/emergencies/
        │
        ▼
6. Django authenticates user
        │
        ▼
7. Serializer validates data
        │
        ▼
8. EmergencyReport saved
        │
        ▼
9. Agent workflow triggered
        │
        ▼
10. AgentAnalysis saved
        │
        ▼
11. Coordinator dashboard receives/loads report
        │
        ▼
12. Human reviews
```

---

# 16. Main Data Flow — Official Emergency Alert

```text
Coordinator / Authorized Authority
                │
                ▼
        Create Official Alert
                │
                ▼
          Django API
                │
         Validate permission
                │
                ▼
        Save OfficialAlert
                │
                ▼
         Notification Service
                │
                ▼
       Targeted mobile users
                │
                ▼
          Citizen sees:
          🚨 OFFICIAL ALERT
```

Future systems can additionally route the alert through government/telecom infrastructure such as cell broadcast, but that is outside the initial student implementation.

---

# 17. Main Data Flow — AI

```text
EmergencyReport
      │
      ▼
Agent Service
      │
      ├── Extraction
      │
      ├── Uncertainty
      │
      ├── Priority
      │
      └── Duplicate detection
      │
      ▼
AgentAnalysis
      │
      ▼
Coordinator UI
```

The original report is never replaced.

Store both:

```text
Original user report
+
Machine-generated analysis
+
Human decision
```

---

# 18. Future Offline Data Flow

Stage 3 introduces a local outbox.

```text
Citizen creates report
        │
        ▼
Local database
        │
        ├── Internet available ──→ Django
        │
        └── Internet unavailable
                    │
                    ▼
             Local Outbox
                    │
                    ▼
          Nearby Device Discovery
                    │
                    ▼
              Peer Device
                    │
                    ▼
             Peer Local Store
                    │
              ...forward...
                    │
                    ▼
             Device with Internet
                    │
                    ▼
                 Django
```

This uses **store-carry-forward**.

The message should contain:

```text
message_id
origin_id
created_at
expires_at
hop_count
payload
```

Future implementations should add integrity/authentication mechanisms.

---

# 19. API Versioning

Use versioned URLs:

```text
/api/v1/
```

Example:

```text
POST /api/v1/auth/login/
/api/v1/emergencies/
/api/v1/emergencies/{id}/
/api/v1/alerts/
/api/v1/alerts/{id}/
```

Do not mix unrelated API behavior into one large endpoint.

---

# 20. Error Handling

Emergency communication must fail gracefully.

Example:

```text
Internet unavailable
        │
        ▼
Mobile app
        │
        ▼
Save locally
        │
        ▼
"Your report is stored and will be
sent when connectivity is available."
```

AI failure:

```text
Agent unavailable
      │
      ▼
Report still exists
      │
      ▼
Coordinator can read original report
```

Notification failure:

```text
Push failed
      │
      ▼
Official alert remains stored
      │
      ▼
App can retrieve alert on next connection
```

AI, push notifications, and future relay mechanisms should therefore be treated as **supporting systems**, not the only copy of critical data.

---

# 21. Security Boundaries

The system has three important trust boundaries.

## Citizen

Can create reports.

Cannot:

- create official alerts,
- modify another user's report,
- change system priority without permission.

## Coordinator

Can:

- view operational reports,
- review AI analysis,
- change operational status,
- make human decisions.

## Administrator

Can:

- manage users,
- manage roles,
- configure the system.

Never trust the client to enforce these rules.

The Django backend must enforce permissions.

---

# 22. Testing Architecture

Testing should exist at multiple levels.

```text
Unit Tests
    │
    ▼
API Tests
    │
    ▼
Permission Tests
    │
    ▼
Integration Tests
    │
    ▼
Agent Evaluation
    │
    ▼
End-to-End Tests
```

Critical paths should have tests before adding complex features.

Examples:

```text
Citizen cannot access another user's report.

Citizen cannot create an official alert.

Coordinator can review reports.

Expired alerts are not shown as active.

AI failure does not delete or prevent storing a report.

Duplicate requests do not create unintended duplicate records.
```

---

# 23. Architecture Principles

## Principle 1 — Emergency communication first

Basic reporting must work without AI.

## Principle 2 — Human-in-the-loop

AI recommends; humans remain responsible for consequential decisions.

## Principle 3 — Preserve original information

Never overwrite the citizen's original report with an AI interpretation.

## Principle 4 — Least privilege

Every role gets only the permissions it needs.

## Principle 5 — Fail gracefully

A failed AI service must not break emergency reporting.

## Principle 6 — Provider independence

AI-specific code stays behind an interface so providers can be changed.

## Principle 7 — Offline-ready

Even before Bluetooth exists, data models and services should be designed so a local outbox can be introduced later.

## Principle 8 — Reproducibility

Environment variables, versions, migrations, commands, and tests should be documented.

---

# 24. Future Components

Possible future modules:

```text
backend/apps/
├── relay/
├── geo/
├── audit/
├── media/
├── shelters/
└── analytics/
```

### `relay`

Offline peer-to-peer message exchange.

### `geo`

Geographic targeting and geospatial queries.

### `audit`

Immutable or append-only operational history.

### `media`

Photos/audio and storage lifecycle.

### `shelters`

Emergency shelters, hospitals, stations, evacuation information.

### `analytics`

Post-event reporting and system performance metrics.

These should not be implemented unless the current stage requires them.

---

# 25. Architecture Definition of Done

A stage is complete only when:

- the feature works,
- automated tests cover the important path,
- permissions are enforced,
- failure behavior is defined,
- the README/phase documentation describes how to run it,
- another developer can reproduce the result.

This keeps implementation aligned with the hackathon's reproducibility and evidence requirements.
