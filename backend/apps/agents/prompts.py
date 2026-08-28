"""Prompt builders for the ResQMesh analysis agents.

Each prompt asks the model to return a JSON object with a fixed schema, and the
provider layer enforces ``format: json`` so output is structured. Instruction
tags like "EXTRACTION" let the mock provider dispatch deterministically.
"""

from __future__ import annotations

from ..emergencies.models import IncidentType


def extraction_prompt(report_text: str, incident_choice: str | None = None) -> str:
    choices = ", ".join(f'"{c}"' for c in IncidentType.values)
    choice_note = (
        f'\nThe user already chose incident type "{incident_choice}". Validate it '
        "or adjust it if it clearly does not fit the description."
        if incident_choice
        else ""
    )
    return f"""EXTRACTION AGENT.

You are an emergency triage assistant. From the emergency report below, extract
the structured facts:

- incident_type: one of {choices}
- people_affected: integer estimate, or null if not stated
- injuries: list of {"{"}"type": string, "location"?: string{"}"} objects, or []
- location_hint: nearest recognizable place/landmark, or null
- requested_assistance: list of strings
- confidence: 0.0 to 1.0 representing how confident you are in the extraction

Report:
"{report_text}"

Respond ONLY with a JSON object. Use the schema keys exactly.{choice_note}"""


def uncertainty_prompt(report_text: str) -> str:
    return f"""UNCERTAINTY AGENT.

You are an emergency triage assistant. Evaluate how uncertain this report is.

A report is HIGH uncertainty when: the reporter uses hedged/unknown language
("maybe", "I think", "not sure", "roughly", "could be"), no coordinates are
provided, or the people count / location / severity is vague.

Respond ONLY with a JSON object with keys:
- uncertainty_score: 0.0 to 1.0
- level: one of "LOW", "MEDIUM", "HIGH"
- flags: list of short strings naming what caused uncertainty

Report:
"{report_text}" """


def priority_prompt(report_text: str) -> str:
    return f"""PRIORITY AGENT.

You are an emergency triage assistant. Recommend an operational priority for a
response team. Use this rubric:

- CRITICAL: life-threatening, trapped/buried, uncontrolled fire, severe
  bleeding, unconscious, building collapse, or children/elderly at risk.
- HIGH: structural damage, flooding/landslide, unsafe to wait, needs support
  soon.
- MEDIUM: medical help needed, no immediate risk to life.
- LOW: minor or routine.

Respond ONLY with a JSON object with keys:
- suggested_priority: one of "LOW", "MEDIUM", "HIGH", "CRITICAL"
- confidence: 0.0 to 1.0
- rationale: one short sentence explaining the decision

Report/corpus:
"{report_text}" """


def duplicate_prompt(candidate: str, previous_summaries: list) -> str:
    corpus = "\n".join(
        f"- {i+1}. {s}" for i, s in enumerate(previous_summaries)
    ) or "(no comparable reports)"
    return f"""DUPLICATE AGENT.

You are an emergency triage assistant. Decide whether the candidate report is a
duplicate of any report already in the queue. Consider proximity, incident
type, and description similarity.

Respond ONLY with a JSON object with keys:
- duplicate_of: the index (1-based int) of the previous report it duplicates,
  or null
- similarity: 0.0 to 1.0
- suggested_merge: true/false

Candidate report:
"{candidate}"

Previous reports:
{corpus} """
