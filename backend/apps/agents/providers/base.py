"""Provider abstraction for the ResQMesh AI agents.

Two guarantees for robust operation during a disaster:
  1. A provider must never raise a raw transport error that can break report
     ingestion. On any failure it returns a result carrying an ``"error"`` key
     and ``is_available=False`` so callers can fall back gracefully.
  2. A provider returns *parsed structured data* (dict/list), not raw text, so
     downstream agents and the coordinator UI never have to parse free text.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
import json
import logging
import random
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


def _error_result(err: Exception) -> dict:
    return {"error": f"{type(err).__name__}: {err}", "is_available": False}


class AnalysisProvider(ABC):
    """Interface every AI provider implements."""

    name: str = "base"

    @abstractmethod
    def generate_json(
        self,
        prompt: str,
        system: Optional[str] = None,
        *,
        fallback: Optional[dict] = None,
        seed: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Run the model and return a parsed JSON dict.

        ``fallback`` is returned AS-IS (merged best-effort) if the model call
        fails, so callers can degrade deterministically.
        """

    def available(self) -> bool:
        return True


def pick(items: list, seed: Optional[int] = None) -> Any:
    """Deterministic picker used by the mock provider (seeded for tests)."""
    if not items:
        return None
    rng = random.Random(seed)
    return items[rng.randrange(len(items))]


def safe_dumps(obj: Any) -> str:
    try:
        return json.dumps(obj, ensure_ascii=False)
    except (TypeError, ValueError):
        return "{}"
