# ResQMesh — Project Goal and Development Plan

## 1. Project Overview

**ResQMesh** is a multi-user emergency communication and coordination platform designed to help people report emergencies, receive official warnings, and help emergency information reach responders.

The central problem is that during a disaster, information is often:

- fragmented,
- unstructured,
- delayed,
- duplicated,
- uncertain,
- difficult for responders to prioritize.

A person may send a message such as:

> "Please help. We are trapped in an old building near KU. There are around four of us and one person is bleeding badly."

This contains potentially critical information, but an emergency coordinator handling hundreds of reports cannot efficiently read and manually organize every message.

ResQMesh aims to provide a system where:

1. A citizen can quickly create an emergency report.
2. The report reaches a central emergency coordination system when connectivity is available.
3. An AI-assisted workflow extracts useful information from the report.
4. The system identifies uncertainty rather than inventing missing facts.
5. Reports are organized and prioritized for a human emergency coordinator.
6. Official emergency alerts can be distributed to affected users.
7. In a later stage, messages can be stored and forwarded between nearby devices when normal connectivity is unavailable.

The project is **not intended to replace Nepal's official emergency infrastructure**. It is a prototype exploring how emergency communication and coordination could become more resilient and easier to manage.

---

# 2. The Problem We Are Trying to Solve

During an emergency such as:

- an earthquake,
- flood,
- landslide,
- building collapse,
- fire,
- or another large-scale disaster,

many people may need help simultaneously.

Emergency information may arrive in forms such as:

> "My mother cannot walk."

> "Building collapsed near us."

> "We need medical help."

> "Three people are trapped but I'm not sure how badly they are injured."

> "The bridge near the hospital is damaged."

These reports have several problems.

## 2.1 Unstructured information

Different people describe the same type of emergency differently.

One person may write:

> "Someone is bleeding badly."

Another may write:

> "There is a lot of blood and he is not moving."

A human operator must interpret both messages.

---

## 2.2 Missing or uncertain information

A user may not know:

- the exact number of people,
- the exact address,
- the severity of an injury,
- whether another person has already reported the same incident.

The system must not convert uncertainty into false certainty.

For example:

Incorrect:

> "Exactly 4 people are trapped."

Better:

> "Reporter estimates approximately 4 people."

The system should preserve the original information and clearly mark uncertainty.

---

## 2.3 Too many reports

During a major emergency, a coordinator could potentially receive:

```text
Report 1: Need food
Report 2: One person injured
Report 3: Building collapsed
Report 4: Need water
Report 5: Person trapped
Report 6: Severe bleeding
...
```

Reading and organizing these manually can be slow.

The goal is to help transform incoming reports into a structured emergency queue.

---

## 2.4 Connectivity may fail

A disaster can cause:

- internet outages,
- overloaded mobile networks,
- damaged communication infrastructure,
- isolated groups of people.

Therefore, the system should eventually support more than one method of delivering information.

However, we will **not attempt to solve every communication problem in the first version**.

The project will be developed progressively.

---

# 3. Primary Goal

The primary goal of ResQMesh is:

> **To create an easy-to-use emergency reporting and coordination platform that helps people communicate urgent information and helps human emergency coordinators understand, organize, and prioritize incoming reports more efficiently.**

The system must remain **human-controlled**.

AI should assist with:

- extracting information,
- structuring reports,
- identifying uncertainty,
- detecting possible duplicates,
- suggesting priority.

AI must **not autonomously dispatch emergency services or make irreversible decisions**.

A qualified human should remain responsible for consequential actions.

---

# 4. Who Are the Users?

The system has three primary user groups.

## 4.1 Citizens

Citizens use the mobile application to:

- receive official emergency alerts,
- send emergency reports,
- request help,
- view the status of their submitted reports,
- access important emergency information.

The application should assume that the user may be:

- stressed,
- injured,
- in a hurry,
- unfamiliar with technology,
- using the application with limited connectivity.

Therefore, the emergency flow must be extremely simple.

---

## 4.2 Emergency Coordinators

Emergency coordinators use a web dashboard.

Their responsibilities include:

- reviewing incoming reports,
- viewing AI-extracted information,
- reviewing uncertainty,
- approving or modifying priority,
- identifying possible duplicates,
- creating official emergency alerts.

The dashboard should help humans make decisions faster, rather than replacing them.

---

## 4.3 Emergency Authorities / Administrators

Authorized users can:

- create official emergency alerts,
- select affected regions,
- manage alert status,
- review system activity,
- manage authorized coordinator accounts.

Official alerts must be clearly separated from citizen-generated reports.

---

# 5. Core System Architecture

The initial architecture will use Django as the backend because the system needs to support multiple users and different roles.

```text
                    ┌──────────────────────┐
                    │    Flutter App       │
                    │                      │
                    │ Citizen Interface    │
                    └──────────┬───────────┘
                               │
                               │ Internet
                               ▼
                    ┌──────────────────────┐
                    │    Django Backend    │
                    │                      │
                    │ Authentication       │
                    │ Emergency Reports    │
                    │ Official Alerts      │
                    │ User Management      │
                    │ Agent Orchestration  │
                    └──────────┬───────────┘
                               │
                  ┌────────────┼─────────────┐
                  ▼            ▼             ▼
            PostgreSQL      AI Agents    Notification
                                            Service
                               │
                               ▼
                    ┌──────────────────────┐
                    │ Coordinator Dashboard│
                    └──────────────────────┘
```

Later, an offline relay layer can be added:

```text
                         Internet unavailable
                                 │
                                 ▼
                    ┌──────────────────────┐
                    │ Local Message Store  │
                    └──────────┬───────────┘
                               │
                       Nearby connection
                               │
                  ┌────────────┴────────────┐
                  ▼                         ▼
             Bluetooth                 Wi-Fi P2P
                  │                         │
                  └────────────┬────────────┘
                               ▼
                         Nearby Device
```

---

# 6. Emergency Report Flow

A typical emergency report should follow this flow:

```text
Citizen
   │
   ▼
Open "Get Help"
   │
   ▼
Describe Emergency
   │
   ├── Text
   ├── Optional voice input
   └── Quick emergency categories
   │
   ▼
Attach available information
   │
   ├── Location
   ├── Photo (optional)
   └── Number of people, if known
   │
   ▼
Submit Report
   │
   ▼
Django Backend
   │
   ▼
Agent Workflow
   │
   ├── Extract information
   ├── Identify uncertainty
   ├── Suggest category
   ├── Suggest priority
   └── Check possible duplicates
   │
   ▼
Coordinator Dashboard
   │
   ▼
Human Review
```

The original user report must always be preserved.

The AI-generated structured interpretation should never overwrite the original message.

---

# 7. How the App Interacts With AI Agents

AI should not be treated as a chatbot that the user must pay to access.

The user is not subscribing to an AI assistant.

Instead, AI operates as part of the backend workflow.

The user simply submits an emergency report.

For example:

```text
"We are trapped inside a building near KU.
There are around four people.
One person is bleeding badly."
```

The backend sends the report through an agent workflow.

## Agent 1: Information Extraction

The extraction agent attempts to identify:

- incident type,
- people affected,
- injury information,
- location hints,
- requested assistance.

Example:

```json
{
  "incident_type": "TRAPPED_AFTER_BUILDING_DAMAGE",
  "estimated_people": 4,
  "injuries": [
    {
      "description": "bleeding badly",
      "severity": "unknown"
    }
  ],
  "location_hint": "near KU",
  "requested_help": [
    "rescue",
    "medical"
  ]
}
```

The agent must distinguish between:

- facts explicitly stated,
- estimates,
- missing information.

---

## Agent 2: Uncertainty and Consistency Check

This agent checks for:

- missing information,
- contradictions,
- uncertain claims,
- ambiguous locations.

For example:

```json
{
  "uncertainties": [
    "Exact building unknown",
    "Number of affected people is an estimate",
    "Medical severity cannot be confirmed from the report"
  ]
}
```

The goal is to prevent the system from presenting assumptions as facts.

---

## Agent 3: Priority Recommendation

The priority agent can recommend a priority such as:

```text
CRITICAL
HIGH
MEDIUM
LOW
```

The recommendation should be accompanied by reasoning.

Example:

```text
Suggested Priority: CRITICAL

Reasons:
- People reported trapped
- Possible severe bleeding
- Possible building collapse
```

The final priority remains reviewable and editable by a human coordinator.

---

## Agent 4: Possible Duplicate Detection

Later, the system may compare reports.

For example:

```text
Report A:
"Building collapsed near Kathmandu University."

Report B:
"We are trapped in the old building beside KU."

Report C:
"People stuck near the collapsed building close to KU."
```

The system can flag:

```text
Possible related incidents detected.
```

It should not automatically merge or delete reports without human review.

---

# 8. AI Cost and Accessibility

A core requirement of this project is:

> **Citizens should never need to pay a monthly subscription to report an emergency or receive emergency information.**

The AI system belongs to the platform infrastructure, not to individual users.

The architecture should therefore support:

```text
Citizen
   │
   │ Free emergency report
   ▼
Django Backend
   │
   ▼
Shared AI Processing Layer
```

Possible future approaches include:

## Option 1: Server-side API model

The backend processes reports using a hosted model.

Advantages:

- easier implementation,
- high-quality models,
- no AI requirements on the user's phone.

Disadvantages:

- ongoing infrastructure cost.

---

## Option 2: Local or self-hosted model

A future version could use an open-source model hosted by the emergency platform.

Advantages:

- predictable infrastructure ownership,
- no per-user subscription,
- potentially lower cost at scale.

Disadvantages:

- requires more infrastructure,
- requires GPU or efficient inference infrastructure.

---

## Option 3: Hybrid architecture

Use AI only where it provides significant value.

For example:

```text
Simple structured report
        │
        ▼
No AI needed


Complex free-text report
        │
        ▼
AI-assisted extraction
```

This can reduce cost.

---

## Important principle

AI must never become a requirement for basic emergency communication.

If the AI service is unavailable:

```text
Emergency Report
       │
       ▼
Store and send normally
       │
       ▼
Coordinator can still read original report
```

The system should degrade gracefully.

---

# 9. Official Emergency Alert Distribution

Official alerts are different from citizen reports.

A citizen might send:

```text
🆘 HELP REQUEST
```

An authorized authority might create:

```text
🚨 OFFICIAL EMERGENCY ALERT

Flood warning.

Move to higher ground immediately.
Avoid the river area.
```

The distribution flow is:

```text
Authorized Coordinator
         │
         ▼
Create Official Alert
         │
         ▼
Django Backend
         │
         ├── Save Alert
         ├── Select Target Region
         ├── Record Audit Information
         └── Trigger Notification
                    │
                    ▼
              Mobile Users
```

Initially, alerts can be delivered using:

- push notifications,
- in-app notifications,
- WebSocket updates where appropriate.

The application should clearly distinguish:

```text
🚨 OFFICIAL ALERT
```

from:

```text
🆘 CITIZEN REPORT
```

A citizen report must never visually appear to be an official government warning.

---

# 10. Forward Relay Concept

The future offline communication system will use a concept called:

> **Store-Carry-Forward**

The basic idea is simple.

Suppose Person A creates an emergency report:

```text
Phone A

Message:
"We are trapped and need help."

Status:
Waiting for delivery
```

Phone A currently has no internet.

Later, Phone B comes nearby.

```text
Phone A  ←──────→  Phone B
```

Phone B receives and stores the message.

Later, Phone B encounters Phone C.

```text
Phone B  ←──────→  Phone C
```

Phone C receives the message.

Eventually, one device may regain connectivity:

```text
Phone C
   │
   │ Internet available
   ▼
Django Server
```

The message can then reach the emergency system.

The flow is:

```text
Person A
   │
   ▼
Phone A
   │
   ▼
Phone B
   │
   ▼
Phone C
   │
   ▼
Internet
   │
   ▼
Emergency Server
```

This does not guarantee instant delivery.

Instead, it provides an additional communication path when conventional connectivity is unavailable.

---

# 11. Future Bluetooth / Local Relay Architecture

Bluetooth and local peer-to-peer communication will be added later.

Each device should maintain a local emergency message store.

Example:

```text
Local Emergency Messages

Message ID
Original Sender
Created At
Priority
Expiry Time
Delivery Status
Already Relayed
```

When two devices encounter each other, they should not blindly exchange every message.

Instead:

```text
Phone A:
I have messages:
A1, A2, A3

Phone B:
I have messages:
A2, A4
```

The devices determine what is missing:

```text
Phone B needs:
A1, A3

Phone A needs:
A4
```

Then exchange only missing messages.

This helps reduce unnecessary traffic and duplicate transfers.

Future improvements may include:

- message expiration,
- duplicate detection,
- hop limits,
- priority-based propagation,
- battery-aware behavior,
- Wi-Fi peer-to-peer transport,
- cryptographic message signatures.

---

# 12. App Permissions

The application should request only permissions that are necessary.

Permissions should also be requested contextually where possible, instead of overwhelming the user with many permissions immediately.

## 12.1 Notifications

The app should ask for notification permission.

Purpose:

- receive official emergency alerts,
- receive updates about submitted reports,
- receive critical warnings.

The explanation should be clear:

> "Allow notifications so ResQMesh can show you important emergency alerts and updates."

---

## 12.2 Location

Location should be optional but strongly encouraged during an emergency report.

Purpose:

- attach the user's approximate or precise location to an emergency report,
- help coordinators understand where help may be needed,
- support future geographic alert targeting.

The app should explain:

> "Your location can help emergency responders find you. You can still submit a report without sharing your location."

The user should retain control where possible.

---

## 12.3 Bluetooth / Nearby Devices

This permission should initially be requested only when the offline relay feature is introduced.

Purpose:

- discover nearby participating devices,
- exchange emergency messages when conventional connectivity is unavailable.

The explanation should be:

> "Allow nearby device communication so emergency messages may be relayed when internet connectivity is unavailable."

---

## 12.4 Camera

Camera permission should not be requested immediately.

It should only be requested when the user chooses:

```text
Attach Photo
```

Purpose:

- attach visual information to an emergency report.

---

## 12.5 Microphone

Microphone permission should only be requested if the user chooses voice input.

Purpose:

- allow a user to describe an emergency using speech when typing may be difficult.

---

# 13. UI/UX Philosophy

This is an emergency application.

The design should not feel like a complex social media application or enterprise dashboard.

The main principles are:

- clarity,
- speed,
- large touch targets,
- readable typography,
- minimal cognitive load,
- obvious actions,
- strong visual hierarchy,
- accessibility,
- useful instructions.

The interface can still be attractive and modern, but beauty must never interfere with usability.

---

# 14. Citizen App UI

The main screen should immediately answer:

> What can I do right now?

A possible home screen:

```text
┌──────────────────────────────────┐
│ ResQMesh                         │
│ Emergency communication          │
│                                  │
│ ┌──────────────────────────────┐ │
│ │ 🚨 ACTIVE EMERGENCY ALERT    │ │
│ │ Check official information   │ │
│ └──────────────────────────────┘ │
│                                  │
│                                  │
│      ┌──────────────────┐        │
│      │                  │        │
│      │   🆘 GET HELP     │        │
│      │                  │        │
│      └──────────────────┘        │
│                                  │
│   📢 Official Alerts             │
│                                  │
│   📋 My Emergency Reports        │
│                                  │
│   🏥 Emergency Information       │
│                                  │
└──────────────────────────────────┘
```

The primary emergency action should be visually obvious.

The user should not need to navigate through several menus before reporting an emergency.

---

# 15. Emergency Report UI

The emergency reporting screen should support both:

## Quick structured input

```text
What happened?

[ Building Collapse ]
[ Medical Emergency ]
[ Fire ]
[ Flood ]
[ Landslide ]
[ Other ]
```

and:

## Free-text description

```text
Describe what happened:

┌─────────────────────────────────┐
│ We are trapped inside...        │
│                                 │
└─────────────────────────────────┘
```

Optional fields can include:

```text
📍 Add Location

👥 Number of People

📷 Add Photo

🎤 Describe by Voice
```

The user should not be forced to complete a long form during an emergency.

A possible confirmation screen:

```text
┌─────────────────────────────────┐
│ Review Emergency Report         │
│                                 │
│ Incident: Building Collapse     │
│ Location: Attached ✓            │
│ People: Approximately 4         │
│                                 │
│ [ SEND EMERGENCY REPORT ]       │
└─────────────────────────────────┘
```

---

# 16. Report Status UI

After submitting a report, the user should understand what happened.

Example:

```text
🆘 Emergency Report

Status:
✓ Submitted

Report ID:
RQ-23914

Last Update:
Just now

Location:
Attached

If connectivity is unavailable:
Your report will remain stored and
will be sent when a connection becomes available.
```

In the future, this can also show:

```text
Status:
Waiting for connection

or

Relayed to nearby device

or

Delivered to emergency server
```

This transparency is important.

---

# 17. Coordinator Dashboard

The coordinator dashboard should prioritize clarity over decoration.

Example:

```text
┌────────────────────────────────────────────────────┐
│ ResQMesh Emergency Dashboard                       │
├────────────────────────────────────────────────────┤
│                                                    │
│ 🚨 CRITICAL: 12     ⚠ HIGH: 28     🟡 MEDIUM: 41  │
│                                                    │
├────────────────────────────────────────────────────┤
│                                                    │
│ 🚨 CRITICAL                                         │
│                                                    │
│ People trapped in damaged building                  │
│ Estimated: 4 people                                 │
│ Location: Near Kathmandu University                 │
│                                                     │
│ AI Notes:                                           │
│ - Severe bleeding mentioned                         │
│ - Exact building uncertain                          │
│                                                     │
│ [ REVIEW ] [ CHANGE PRIORITY ] [ MARK DUPLICATE ] │
│                                                    │
└────────────────────────────────────────────────────┘
```

The original user message must remain visible.

The AI interpretation should be visually separate.

---

# 18. Three Development Stages

The project will be divided into three stages.

This prevents the project from becoming too large too early.

---

# STAGE 1 — Core Emergency Reporting Platform

## Goal

Build a fully functional multi-user emergency reporting system.

## Features

### Citizen

- account creation and authentication,
- emergency report creation,
- quick emergency categories,
- free-text emergency description,
- optional location,
- report status,
- official alerts screen.

### Backend

- Django,
- Django REST Framework,
- PostgreSQL,
- user roles,
- emergency report model,
- official alert model,
- notification-ready architecture.

### Coordinator

- dashboard,
- view incoming reports,
- filter by status,
- manually assign priority,
- create official alerts.

## App After Stage 1

```text
Citizen
   │
   ▼
Create Emergency Report
   │
   ▼
Django API
   │
   ▼
PostgreSQL
   │
   ▼
Coordinator Dashboard
```

No AI dependency is required for the core emergency reporting functionality.

## Tests

### Functional Tests

- User can register.
- User can log in.
- User can submit an emergency report.
- Report is stored correctly.
- User can view their own reports.
- One user cannot view another user's private report unless authorized.
- Coordinator can view incoming reports.
- Coordinator can change report priority.
- Authorized user can create an official alert.
- Official alert appears for target users.

### API Tests

- authentication tests,
- permission tests,
- serializer validation,
- invalid report handling,
- role-based access tests.

### Manual Tests

Test with multiple accounts:

```text
Citizen A
Citizen B
Coordinator
Administrator
```

Verify that each role sees only the actions it is supposed to perform.

---

# STAGE 2 — AI-Assisted Emergency Coordination

## Goal

Add an agent workflow that helps coordinators process incoming reports.

## Features

### Extraction Agent

Extract:

- incident type,
- people affected,
- injuries,
- location hints,
- requested assistance.

### Uncertainty Agent

Identify:

- missing information,
- uncertain information,
- contradictions,
- ambiguous locations.

### Priority Agent

Recommend:

```text
CRITICAL
HIGH
MEDIUM
LOW
```

### Human Review

The coordinator can:

- accept the suggestion,
- modify the priority,
- reject the AI interpretation.

## App After Stage 2

```text
Citizen
   │
   ▼
Emergency Report
   │
   ▼
Django Backend
   │
   ▼
Agent Workflow
   │
   ├── Extraction
   ├── Uncertainty Check
   ├── Priority Recommendation
   └── Duplicate Suggestion
   │
   ▼
Coordinator Dashboard
   │
   ▼
Human Review
```

The system must preserve:

```text
Original Report
+
AI Interpretation
+
Human Decision
```

## Tests

Create at least 10–20 synthetic emergency reports.

Examples should include:

- clear medical emergency,
- building collapse,
- vague report,
- contradictory report,
- duplicate-like reports,
- missing location,
- uncertain number of victims,
- low-priority resource request,
- potentially critical emergency.

Compare:

### Baseline

A simple single-prompt approach.

### Final Agent Workflow

Structured extraction + uncertainty detection + prioritization.

Possible evaluation metrics:

- correct incident extraction,
- correct priority recommendation,
- uncertainty correctly preserved,
- possible duplicate detection,
- human review time.

All evaluation cases must be identical for the baseline and final workflow.

Do not invent evaluation results.

Run the tests and record the actual outcome.

---

# STAGE 3 — Offline Forward Relay

## Goal

Allow emergency reports to move between nearby devices when conventional internet connectivity is unavailable.

## Initial Scope

Do not attempt to build a nationwide Bluetooth mesh.

Start with:

```text
Phone A → Phone B → Phone C
```

The requirement:

Phone C should be able to eventually receive a message originally created by Phone A, even if A and C never directly meet.

## Features

- local message storage,
- unique message IDs,
- duplicate detection,
- message expiry,
- delivery status,
- store-carry-forward,
- Bluetooth or nearby-device communication,
- future Wi-Fi peer-to-peer support.

## App After Stage 3

```text
                    Internet
                       │
                       ▼
                  Django Server
                       ▲
                       │
Phone A → Phone B → Phone C
                       │
                       ▼
                 Internet restored
```

## Tests

### Test 1: Basic Local Transfer

```text
Phone A → Phone B
```

Verify:

- message transfers,
- duplicate is not created.

### Test 2: Multi-hop Transfer

```text
Phone A → Phone B → Phone C
```

Verify:

- A and C never directly connect,
- C receives the message.

### Test 3: Duplicate Suppression

```text
A → B
A → B again
```

Verify that B stores only one copy.

### Test 4: Expired Message

Create a message with a short expiry time.

Verify:

- expired messages are not relayed.

### Test 5: Internet Recovery

```text
A → B → C

C gains internet
```

Verify that the message reaches the Django backend.

---

# 19. Security and Trust

Because this is an emergency application, security cannot be treated as an afterthought.

Important future areas include:

## Authentication

- secure user authentication,
- role-based permissions,
- authorized coordinator accounts.

## Official Alerts

Only authorized users should be able to create official alerts.

Every official alert should have:

- creator,
- creation time,
- target area,
- status,
- audit history.

## Citizen Reports

Citizen reports must remain distinct from official alerts.

The UI should never allow a user-generated message to look like an official government warning.

## Privacy

The system should minimize sensitive data collection.

Location should be collected only when needed and according to user permissions.

Sensitive emergency data should have appropriate access controls.

## Future Cryptographic Verification

For offline relay, future versions should investigate:

- digital signatures for official alerts,
- message integrity verification,
- trusted public keys,
- replay protection.

---

# 20. Offline-First Principle

The application should gradually move toward an offline-first architecture.

Even if the network fails, the application should still be useful.

Future offline capabilities:

- locally stored emergency reports,
- cached official alerts,
- emergency contact information,
- emergency shelter information,
- hospitals,
- evacuation guidance,
- offline maps where practical.

A user should not see a completely useless application simply because:

```text
Internet = OFF
```

Instead:

```text
Internet unavailable.

Your emergency report has been safely stored.
It will be sent when connectivity or a supported
relay path becomes available.
```

---

# 21. Accessibility

Emergency situations can affect anyone.

The application should consider:

- large buttons,
- high contrast,
- readable text,
- clear icons with text labels,
- minimal typing requirements,
- voice input,
- multilingual support.

A future Nepal-focused version should support at minimum:

- Nepali,
- English.

Language selection should not make emergency actions difficult to find.

---

# 22. Future Improvements

Possible future features include:

## Offline Maps

Cache:

- hospitals,
- shelters,
- police stations,
- fire stations,
- evacuation routes.

---

## Voice-Based Reporting

Allow:

```text
🎤 Hold and describe emergency
```

Speech can then be transcribed and processed through the same report workflow.

---

## Photo and Media Analysis

Future versions could allow optional photos.

However:

- media uploads may consume bandwidth,
- emergency communication should still work without photos,
- AI analysis of images should never replace human verification for high-consequence decisions.

---

## Smarter Duplicate Detection

Combine:

- time,
- location,
- incident type,
- text similarity.

The system should suggest:

```text
Possible duplicate or related incident.
```

A human decides whether reports refer to the same event.

---

## Adaptive Message Priority

Future relay logic could prioritize:

```text
CRITICAL → highest propagation priority

HIGH → normal priority

MEDIUM → lower priority

LOW → opportunistic delivery
```

This must be carefully designed to avoid network flooding.

---

## Multi-Transport Communication

Future communication layers may include:

```text
Internet
    │
    ├── Push Notifications
    ├── API
    └── WebSocket

No Internet
    │
    ├── Wi-Fi Peer-to-Peer
    └── Bluetooth

No Connection
    │
    └── Store and retry
```

The goal is not to assume one technology will always work.

---

# 23. Non-Goals for the Initial Project

To avoid unrealistic scope, the initial project will NOT attempt to:

- replace national emergency infrastructure,
- guarantee message delivery,
- autonomously dispatch police, ambulances, or rescue teams,
- silently bypass mobile operating system security restrictions,
- guarantee nationwide Bluetooth coverage,
- require users to pay for AI access,
- make medical diagnoses,
- determine whether a report is true without human verification.

The project is an emergency communication and coordination prototype.

---

# 24. Definition of Success

The project will be considered successful if we can demonstrate the following end-to-end scenario:

```text
1. Citizen opens the ResQMesh app.

2. Citizen submits:

   "We are trapped in a damaged building.
    One person is bleeding."

3. The report reaches the Django backend.

4. The original report is stored.

5. The AI workflow extracts useful structured information.

6. The system identifies uncertainty where appropriate.

7. The system recommends a priority.

8. The coordinator sees both:

   - Original report
   - AI interpretation

9. A human reviews or modifies the recommendation.

10. The system records the final decision.
```

The Stage 3 extension adds:

```text
11. Internet becomes unavailable.

12. An emergency message is stored locally.

13. The message moves:

    Phone A → Phone B → Phone C

14. One device regains connectivity.

15. The message reaches the Django backend.
```

---

# 25. Final Vision

ResQMesh is not just a chatbot and not just a Bluetooth mesh experiment.

The long-term vision is:

> **A resilient emergency communication system where citizens can quickly report emergencies, information can survive temporary connectivity failures, AI can help organize large volumes of incoming information, and humans remain responsible for consequential decisions.**

The architecture should grow in layers:

```text
STAGE 1
Emergency Reporting
        +
Multi-user Django Backend
        ↓

STAGE 2
AI-Assisted Extraction
        +
Prioritization
        +
Human Review
        ↓

STAGE 3
Offline Storage
        +
Store-Carry-Forward
        +
Bluetooth / Nearby Relay
```

The guiding principle throughout development is:

> **Make the emergency action simple for the person who needs help, make the information useful for the person coordinating the response, and ensure the system remains useful even when some parts of the infrastructure fail.**