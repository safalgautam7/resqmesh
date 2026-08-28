"""Deterministic mock provider.

Used for fast, reproducible tests and as an offline fallback during outages.
It performs rule-based keyword analysis so the whole agent workflow can run
even when no model is reachable. Deterministic given the same input + seed.
"""

from __future__ import annotations

import re
from typing import Any, Dict, Optional

from .base import AnalysisProvider


_KEYWORDS = {
    "BUILDING_COLLAPSE": ["collapse", "collapsed", "building", "structure", "debris"],
    "MEDICAL": ["medical", "heart", "breath", "bleed", "injur", "unconscious", "sick", "ambulance"],
    "FIRE": ["fire", "burn", "smoke", "flame", "explosion"],
    "FLOOD": ["flood", "water", "drown", "submerge", "rising water"],
    "LANDSLIDE": ["landslide", "mud", "rockfall", "slope", "slide"],
    "TRAPPED": ["trap", "stuck", "pin", "buried", "under"],
    "OTHER": [],
}

_NUM_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "dozen": 12, "twenty": 20,
}

_PRIORITY_KEYWORDS = {
    "CRITICAL": ["bleed", "unconscious", "collapse", "fire", "trapped", "buried",
                 "explosion", "gas", "injured", "child", "elderly",
                 "chest", "breath", "breathing", "ambulance", "heart", "attack"],
    "HIGH": ["flood", "landslide", "water", "damage", "no water", "no food"],
    "MEDIUM": ["medical", "sick", "help needed"],
}


class MockProvider(AnalysisProvider):
    name = "mock"

    def __init__(self, model: str = "mock-rules"):
        self.model = model

    # -- public interface -------------------------------------------------
    def generate_json(
        self,
        prompt: str,
        system: Optional[str] = None,
        *,
        fallback: Optional[dict] = None,
        seed: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Dispatch on an instruction tag embedded in the prompt by services.py."""
        text = (system or "") + "\n" + (prompt or "")
        text_l = text.lower()
        if "extract" in text_l:
            return self._extract(text, seed)
        if "uncertainty" in text_l:
            return self._uncertainty(text, seed)
        if "priorit" in text_l:
            return self._priority(text, seed)
        if "duplicate" in text_l:
            return self._duplicate(text, seed)
        return dict(fallback or {})

    # -- extraction --------------------------------------------------------
    @staticmethod
    def _extract(text: str, seed: Optional[int]) -> Dict[str, Any]:
        body = _body(text)
        body_l = body.lower()

        incident = "OTHER"
        best_hits = 0
        for itype, words in _KEYWORDS.items():
            hits = sum(1 for w in words if w in body_l)
            if hits > best_hits:
                best_hits, incident = hits, itype

        people = _people(body_l)
        injuries = _injuries(body_l)
        # crude location guess: after "near" / "at" / "in"
        location_hint = _location(body)

        confidence = min(0.95, 0.4 + 0.15 * best_hits) if incident != "OTHER" else 0.55
        return {
            "incident_type": incident,
            "people_affected": people,
            "injuries": injuries,
            "location_hint": location_hint,
            "requested_assistance": _assistance(body_l),
            "confidence": round(confidence, 2),
        }

    # -- uncertainty --------------------------------------------------------
    @staticmethod
    def _uncertainty(text: str, seed: Optional[int]) -> Dict[str, Any]:
        body_l = _body(text).lower()
        score = 0.0
        flags = []
        for token in ["maybe", "perhaps", "not sure", "i think", "roughly", "about",
                      "approximate", "uncertain", "unknown", "could be"]:
            if token in body_l:
                score += 0.2
                flags.append(token)
        for token in ["not sure how many", "i don't know", "no coordinates",
                      "no gps", "can't tell"]:
            if token in body_l:
                score += 0.25
                flags.append(token)
        severity_markers = any(w in body_l for w in ["trapped", "bleed", "unconscious", "fire"])
        if not severity_markers:
            score += 0.1
        score = min(1.0, score)
        return {
            "uncertainty_score": round(score, 2),
            "level": "HIGH" if score >= 0.6 else ("MEDIUM" if score >= 0.3 else "LOW"),
            "flags": flags,
        }

    # -- priority ------------------------------------------------------------
    @staticmethod
    def _priority(text: str, seed: Optional[int]) -> Dict[str, Any]:
        body_l = _body(text).lower()
        best = "MEDIUM"
        best_hits = 0
        for level, words in _PRIORITY_KEYWORDS.items():
            hits = sum(1 for w in words if w in body_l)
            if hits > best_hits:
                best_hits, best = hits, level
        rationale = f"{best_hits} priority keyword(s) matched in reports/replies"
        return {"suggested_priority": best, "confidence": round(min(1.0, 0.5 + 0.1 * best_hits), 2), "rationale": rationale}

    # -- duplicate -------------------------------------------------------------
    @staticmethod
    def _duplicate(text: str, seed: Optional[int]) -> Dict[str, Any]:
        # In practice this runs against the current open reports in services.py,
        # which passes candidate summaries here; we just echo a "no match" stance
        # when there is nothing to compare (single-report path).
        return {"duplicate_of": None, "similarity": 0.0, "suggested_merge": False}


# ---- helpers (shared) ----------------------------------------------------

def _body(text: str) -> str:
    """Isolate the report text from the instruction prompt.

    Prompts place the report after a label line starting with "Report" (or
    "Candidate report"). We take everything from the LAST such label onward, and
    skip the bare label line when the report is on the following line.
    """
    lines = text.splitlines()
    idx = len(lines)
    for i, ln in enumerate(lines):
        head = ln.strip().lower()
        if head.startswith("report") or head.startswith("candidate report"):
            if ":" in ln:
                after = ln.split(":", 1)[1].strip().strip('"').strip()
                if after:
                    idx = i
                    lines[i] = after
                else:
                    idx = i + 1
            else:
                idx = i + 1
    return "\n".join(lines[idx:]).strip().strip('"').strip()


def _people(body_l: str) -> int:
    m = re.search(r"(\d+)\s*(?:people|persons|person|family|injured)", body_l)
    if m:
        return int(m.group(1))
    m = re.search(r"(?:^|\s)(one|two|three|four|five|six|seven|eight|nine|ten|dozen|twenty)\s*(?:people|person|family)", body_l)
    if m:
        return _NUM_WORDS[m.group(1)]
    return None


def _injuries(body_l: str) -> list:
    found = []
    if "bleed" in body_l:
        found.append({"type": "bleeding"})
    if "unconscious" in body_l:
        found.append({"type": "unconscious"})
    if "broken" in body_l or "fracture" in body_l:
        found.append({"type": "fracture"})
    if "burn" in body_l:
        found.append({"type": "burns"})
    return found


def _location(body: str) -> str:
    # Prefer the more specific "near"/"at" markers over the ambiguous "in".
    for marker in ("near", "around", "at"):
        m = re.search(rf"\b{marker}\s+([A-Za-z][A-Za-z0-9 .'/-]{{1,40}})", body, re.IGNORECASE)
        if m:
            return m.group(1).strip()
    m = re.search(r"\bin\s+([A-Za-z][A-Za-z0-9 .'/-]{1,40})", body, re.IGNORECASE)
    if m:
        # avoid capturing long clauses full of stopwords
        cand = m.group(1).strip()
        words = cand.split()
        while len(words) > 3 and words[0].lower() in {"a", "an", "the", "my", "our"}:
            words = words[1:]
        return " ".join(words)
    return None


def _assistance(body_l: str) -> list:
    need = []
    pairs = [
        ("medical", "medical aid"),
        ("ambulance", "ambulance"),
        ("rescu", "rescuers"),
        ("water", "drinking water"),
        ("food", "food"),
        ("shelter", "shelter"),
        ("generator", "power"),
        ("fire", "firefighting"),
        ("evacuat", "evacuation"),
    ]
    for key, label in pairs:
        if key in body_l:
            need.append(label)
    return need
