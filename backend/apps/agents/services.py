"""Agent workflow orchestration.

analyze_report() runs the multi-agent pipeline over a report (and its sibling
open reports for duplicate detection), then persists an AgentAnalysis row.

The pipeline is resilient by design:
  - Each agent degrades to ``schemas``-level defaults if the provider returns
    unusable output.
  - A provider/AI failure never raises; it records ``is_available=False`` and
    the report stays usable.
"""

from __future__ import annotations

import logging
import time

from django.db import transaction

from apps.emergencies.models import EmergencyReport, ReportStatus

from . import schemas
from .models import AgentAnalysis
from .prompts import (
    duplicate_prompt,
    extraction_prompt,
    priority_prompt,
    uncertainty_prompt,
)
from .providers import get_provider

logger = logging.getLogger(__name__)

_MOCK_TIMEOUT_SECONDS = 20.0


def analyze_report(report, *, force: bool = False) -> AgentAnalysis:
    """Run the four-agent pipeline over ``report`` and persist the result.

    Returns the AgentAnalysis row. Safe to call repeatedly; by default it skips
    if an analysis already exists (pass ``force=True`` to re-run).
    """
    analysis, created = AgentAnalysis.objects.get_or_create(report=report)
    if not created and not force:
        return analysis
    if force:
        analysis.error = ""
        analysis.is_available = False

    provider = get_provider()
    system = (
        "You are ResQMesh, an emergency triage AI. Always answer only with the "
        "single JSON object requested, no extra text."
    )

    text = report.description

    extraction = _run_agent(
        provider, system, extraction_prompt(text, report.incident_type),
        normalize=schemas.normalize_extraction,
        default={"incident_type": "OTHER", "confidence": 0.0},
    )

    uncertainty = _run_agent(
        provider, system, uncertainty_prompt(text),
        normalize=schemas.normalize_uncertainty,
        default={"uncertainty_score": 0.5, "level": "MEDIUM", "flags": []},
    )

    priority = _run_agent(
        provider, system, priority_prompt(text),
        normalize=schemas.normalize_priority,
        default={"suggested_priority": "MEDIUM", "confidence": 0.0, "rationale": "default"},
    )
    priority = _apply_safety_floor(priority, extraction)

    duplicate = _run_agent(
        provider, system, duplicate_prompt(text, _sibling_summaries(report)),
        normalize=schemas.normalize_duplicate,
        default={"duplicate_of": None, "similarity": 0.0, "suggested_merge": False},
    )

    errors = [p.get("error") for p in (extraction, uncertainty, priority, duplicate) if p.get("error")]
    analysis.extraction = extraction
    analysis.uncertainty = uncertainty
    analysis.priority = priority
    analysis.duplicate = duplicate
    analysis.provider = provider.name
    analysis.model = getattr(provider, "model", "")
    analysis.is_available = provider.available() and not errors
    analysis.error = " | ".join(errors)[:1000]

    with transaction.atomic():
        analysis.save(update_fields=[
            "extraction", "uncertainty", "priority", "duplicate",
            "provider", "model", "is_available", "error", "updated_at",
        ])
    return analysis


def _sibling_summaries(report, limit: int = 8) -> list[str]:
    """Condensed summaries of other open reports for duplicate detection."""
    open_statuses = [ReportStatus.SUBMITTED, ReportStatus.REVIEWING, ReportStatus.VERIFIED]
    siblings = (
        EmergencyReport.objects
        .filter(status__in=open_statuses)
        .exclude(pk=report.pk)
        .order_by("-created_at")[:limit]
    )
    out = []
    for r in siblings:
        loc = f" @ {r.latitude:.4f},{r.longitude:.4f}" if r.latitude else ""
        out.append(f"{r.incident_type}: {r.description[:140]}{loc}")
    return out


def _run_agent(provider, system, prompt, *, normalize, default: dict) -> dict:
    """Run one agent, normalizing + degrading safely."""
    deadline = time.monotonic()
    try:
        raw = provider.generate_json(prompt, system=system, fallback=default)
    except Exception as exc:  # never let a provider blow up report ingestion
        logger.warning("agent failed: %s", exc)
        raw = {"error": f"{type(exc).__name__}: {exc}"}
    error = raw.get("error") if isinstance(raw, dict) else True
    result = normalize(raw)
    if error:
        result["error"] = str(error)
        result["is_available"] = False
    return result


_PRIORITY_RANK = {"UNASSIGNED": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4}
_CRITICAL_INJURIES = {"bleeding", "unconscious", "burns", "fracture"}
_CRITICAL_INCIDENTS = {"BUILDING_COLLAPSE", "FIRE", "EXPLOSION"}


def _apply_safety_floor(priority: dict, extraction: dict) -> dict:
    """Never let the model dangerously under-triage.

    If extraction found life-threatening signals, raise the suggested priority
    to a safe floor. This is the key guardrail for small/imperfect models: the
    coordinator can always escalate, but the system never tells a responder a
    collapsing building or uncontrolled fire is merely "MEDIUM".
    """
    suggested = priority.get("suggested_priority")
    floor = None

    injuries = {str(i.get("type", "")).lower() for i in extraction.get("injuries", [])}
    if injuries & _CRITICAL_INJURIES:
        floor = "CRITICAL"
    elif extraction.get("incident_type") in _CRITICAL_INCIDENTS:
        floor = "HIGH"
    elif extraction.get("incident_type") == "TRAPPED":
        floor = "HIGH"

    if floor and _PRIORITY_RANK.get(suggested, 0) < _PRIORITY_RANK[floor]:
        priority["suggested_priority"] = floor
        priority["rationale"] = (priority.get("rationale") or "") + (
            " [safety floor raised to %s]" % floor
        )
        priority["confidence"] = min(priority.get("confidence", 0.0), 0.9)
    return priority
