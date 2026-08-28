"""Evaluation harness: baseline (no AI) vs the multi-agent pipeline.

We measure how well each approach classifies a scripted set of emergency
descriptions against ground truth, and quantify what the agents add (pre-filled
priority, uncertainty flags, duplicate detection, availability robustness).

Usage (management command):
    uv run python manage.py evaluate_agents --provider mock|ollama

The harness is fully deterministic with the mock provider; when run against a
model provider it shows real-model behavior with the same schema/scoring.
"""

from __future__ import annotations

import logging

from .providers.mock import MockProvider
from . import schemas, services
from .prompts import extraction_prompt, priority_prompt

logger = logging.getLogger(__name__)

# Ground-truth evaluation cases (deterministic; the same set runs for any
# provider so scores are comparable across mock/ollama).
EVAL_CASES = [
    {
        "id": "c1",
        "description": "A family is trapped in a collapsed building on the east side after the quake, four people, one has a broken leg.",
        "incident_type": "BUILDING_COLLAPSE",
        "priority": "CRITICAL",
        "people": 4,
    },
    {
        "id": "c2",
        "description": "Kitchen fire spreading to the living room in a flat on the second floor; two people inside, smoke everywhere.",
        "incident_type": "FIRE",
        "priority": "CRITICAL",
        "people": 2,
    },
    {
        "id": "c3",
        "description": "The river is flooding the low-lying streets near the bus stop; water is rising fast, many families may need to evacuate.",
        "incident_type": "FLOOD",
        "priority": "HIGH",
        "people": None,
    },
    {
        "id": "c4",
        "description": "My grandfather is having chest pain and trouble breathing; we need an ambulance at the pharmacy on Main Road.",
        "incident_type": "MEDICAL",
        "priority": "CRITICAL",
        "people": 1,
    },
    {
        "id": "c5",
        "description": "A mudslide has blocked the mountain road near the school; there is nobody injured but travel is impossible.",
        "incident_type": "LANDSLIDE",
        "priority": "HIGH",
        "people": 0,
    },
    {
        "id": "c6",
        "description": "I think maybe five or six people might be stuck under a collapsed roof along Ring Road, but I am not sure.",
        "incident_type": "TRAPPED",
        "priority": "CRITICAL",
        "people": 5,
    },
]

# Simple keyword baseline approximating the pre-AI system: no LLM, no structure.
_BASELINE_KEYWORDS = {
    "BUILDING_COLLAPSE": ["collapse", "collapsed", "debris"],
    "FIRE": ["fire", "smoke", "flame"],
    "FLOOD": ["flood", "water", "drown"],
    "LANDSLIDE": ["landslide", "mudslide", "rockfall"],
    "MEDICAL": ["medical", "bleed", "chest pain", "breath", "ambulance"],
    "TRAPPED": ["trap", "stuck", "buried"],
}


def baseline_classify(description: str) -> dict:
    """Non-AI baseline: keyword classifier, no structure extraction."""
    low = description.lower()
    best, best_hits = "OTHER", 0
    for itype, words in _BASELINE_KEYWORDS.items():
        hits = sum(1 for w in words if w in low)
        if hits > best_hits:
            best, best_hits = itype, hits
    priority = "CRITICAL" if any(
        w in low for w in ["trapped", "bleed", "chest pain", "breath", "unconscious", "fire"]
    ) else "MEDIUM"
    return {"incident_type": best if best_hits else "OTHER", "suggested_priority": priority}


def _incident_correct(pred: str, ground: str) -> bool:
    return pred == ground


def _priority_ok(pred: str, ground: str) -> bool:
    # Exact match, or an over-triage is acceptable (never under-triage).
    order = {"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}
    if pred == ground:
        return True
    if pred not in order or ground not in order:
        return False
    return order[pred] >= order[ground]


def evaluate_cases(provider) -> dict:
    """Run the full agent pipeline over EVAL_CASES and aggregate metrics."""
    rows = []
    n_incident = n_priority = n_people = n_measurable = 0.0
    for case in EVAL_CASES:
        text = case["description"]
        extraction = schemas.normalize_extraction(_extract_raw(provider, text))
        priority_norm = schemas.normalize_priority(_priority_raw(provider, text))
        priority_norm = services._apply_safety_floor(priority_norm, extraction)
        pred_incident = extraction["incident_type"]
        pred_priority = priority_norm["suggested_priority"]
        pred_people = extraction["people_affected"]

        ok_incident = _incident_correct(pred_incident, case["incident_type"])
        ok_priority = _priority_ok(pred_priority, case["priority"])
        ok_people = case["people"] is not None and pred_people == (case["people"] or None)

        n_incident += int(ok_incident)
        n_priority += int(ok_priority)
        if case["people"] is not None:
            n_people += int(ok_people)
            n_measurable += 1

        rows.append({
            "id": case["id"],
            "expected_incident": case["incident_type"],
            "expected_priority": case["priority"],
            "pred_incident": pred_incident,
            "pred_priority": pred_priority,
            "pred_people": pred_people,
            "ok_incident": ok_incident,
            "ok_priority": ok_priority,
            "ok_people": ok_people,
        })

    total = len(EVAL_CASES)
    return {
        "provider": provider.name,
        "total": total,
        "incident_accuracy": round(n_incident / total, 3),
        "priority_accuracy_or_accept": round(n_priority / total, 3),
        "people_accuracy": round(n_people / n_measurable, 3) if n_measurable else None,
        "rows": rows,
    }


def analyze_pipeline_value(provider) -> dict:
    """Quantity what the agents add beyond the baseline classifier."""
    base_incident = sum(
        1 for c in EVAL_CASES
        if baseline_classify(c["description"])["incident_type"] == c["incident_type"]
    )
    base_priority = sum(
        1 for c in EVAL_CASES
        if _priority_ok(baseline_classify(c["description"])["suggested_priority"], c["priority"])
    )
    agent = evaluate_cases(provider)
    return {
        "baseline_incident_accuracy": round(base_incident / len(EVAL_CASES), 3),
        "baseline_priority_ok": round(base_priority / len(EVAL_CASES), 3),
        "agent_incident_accuracy": agent["incident_accuracy"],
        "agent_priority_ok": agent["priority_accuracy_or_accept"],
        "delta_incident": round(agent["incident_accuracy"] - base_incident / len(EVAL_CASES), 3),
        "delta_priority": round(agent["priority_accuracy_or_accept"] - base_priority / len(EVAL_CASES), 3),
    }


_SYSTEM = (
    "You are ResQMesh, an emergency triage AI. Always answer only with the "
    "single JSON object requested, no extra text."
)


def _extract_raw(provider, text):
    return provider.generate_json(
        extraction_prompt(text, incident_choice=None),
        system=_SYSTEM,
        fallback={"incident_type": "OTHER", "confidence": 0.0},
        seed=case_seed(text),
    )


def _priority_raw(provider, text):
    return provider.generate_json(
        priority_prompt(text),
        system=_SYSTEM,
        fallback={"suggested_priority": "MEDIUM", "confidence": 0.0, "rationale": ""},
        seed=case_seed(text),
    )


def case_seed(text: str) -> int:
    return abs(hash(text)) % (10**8)
