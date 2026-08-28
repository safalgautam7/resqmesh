"""Normalization + validation for raw provider outputs.

Providers may return imperfect JSON (extra keys, wrong types, missing fields).
These helpers coerce output into the canonical shape the rest of the system
relies on, so a quirky model response can never break report ingestion.
"""

from __future__ import annotations

from ..emergencies.models import IncidentType, Priority

_PRIORITIES = set(Priority.values)
_INCIDENTS = set(IncidentType.values)


def coerce_bool(value, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        return value.strip().lower() in {"true", "yes", "1", "y"}
    return default


def coerce_int(value, min_v=None, max_v=None, default=None):
    try:
        v = int(float(value))
    except (TypeError, ValueError):
        return default
    if min_v is not None and v < min_v:
        return default
    if max_v is not None and v > max_v:
        return default
    return v


def coerce_float(value, min_v=0.0, max_v=1.0, default=0.5):
    try:
        v = float(value)
    except (TypeError, ValueError):
        return default
    return min(max_v, max(min_v, v))


def normalize_extraction(raw) -> dict:
    if not isinstance(raw, dict):
        raw = {}
    incident = str(raw.get("incident_type", "")).upper()
    if incident not in _INCIDENTS:
        incident = IncidentType.OTHER
    return {
        "incident_type": incident,
        "people_affected": coerce_int(raw.get("people_affected"), min_v=1, max_v=1000),
        "injuries": _list_of_dicts(raw.get("injuries")),
        "location_hint": _clean_location(raw.get("location_hint")),
        "requested_assistance": _list_of_str(raw.get("requested_assistance")),
        "confidence": coerce_float(raw.get("confidence")),
    }


_SENTINEL_TOKENS = (
    "nearest recognizable place",
    "location_hint",
    "landmark",
    "unknown",
    "not provided",
    "n/a",
    "none",
    "null",
)


def _clean_location(value) -> str | None:
    if isinstance(value, list):
        value = " ".join(str(v) for v in value)
    if value is None:
        return None
    s = str(value).strip().strip('"')
    low = s.lower()
    if any(tok in low for tok in _SENTINEL_TOKENS):
        return None
    return s[:500] or None


def normalize_uncertainty(raw) -> dict:
    if not isinstance(raw, dict):
        raw = {}
    score = coerce_float(raw.get("uncertainty_score"))
    level = str(raw.get("level", "")).upper()
    if level not in {"LOW", "MEDIUM", "HIGH"}:
        level = "HIGH" if score >= 0.6 else ("MEDIUM" if score >= 0.3 else "LOW")
    return {
        "uncertainty_score": round(score, 2),
        "level": level,
        "flags": _list_of_str(raw.get("flags")),
    }


def normalize_priority(raw) -> dict:
    if not isinstance(raw, dict):
        raw = {}
    pri = str(raw.get("suggested_priority", "")).upper()
    if pri not in _PRIORITIES:
        pri = Priority.UNASSIGNED
    return {
        "suggested_priority": pri,
        "confidence": coerce_float(raw.get("confidence")),
        "rationale": _clean_str(raw.get("rationale")),
    }


def normalize_duplicate(raw, within: bool = True) -> dict:
    if not isinstance(raw, dict):
        raw = {}
    return {
        "duplicate_of": coerce_int(raw.get("duplicate_of"), min_v=1, default=None),
        "similarity": coerce_float(raw.get("similarity")),
        "suggested_merge": coerce_bool(raw.get("suggested_merge")),
    }


def _clean_str(value, max_len: int = 500) -> str | None:
    if isinstance(value, list):
        value = " ".join(str(v) for v in value)
    if value is None:
        return None
    s = str(value).strip()
    return s[:max_len] if s else None


def _list_of_str(value) -> list:
    if not value:
        return []
    if isinstance(value, list):
        out = []
        for v in value:
            if isinstance(v, str) and v.strip():
                out.append(v.strip()[:200])
        return out
    return [str(value)[:200]]


def _list_of_dicts(value) -> list:
    if not isinstance(value, list):
        return []
    out = []
    for v in value:
        if isinstance(v, dict):
            out.append(
                {
                    "type": _clean_str(v.get("type"), 100) or "unknown",
                    "location": _clean_str(v.get("location"), 200),
                }
            )
    return out
