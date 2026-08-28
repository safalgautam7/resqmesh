"""Local Ollama provider.

Uses Ollama's native ``format: "json"`` constraint to force structured JSON
output, which is far more reliable than instructing the model with text.


"""

from __future__ import annotations

from typing import Any, Dict, Optional

import requests

from .base import AnalysisProvider

try:
    from urllib.parse import urljoin
except ImportError:  # pragma: no cover
    from urllib.parse import urljoin  # type: ignore


class OllamaProvider(AnalysisProvider):
    name = "ollama"

    def __init__(self, base_url: str = "http://localhost:11434", model: str = "qwen2.5:1b"):
        self.base_url = base_url.rstrip("/")
        self.model = model

    def available(self) -> bool:
        try:
            r = requests.get(f"{self.base_url}/api/tags", timeout=2)
            return r.ok
        except requests.RequestException:
            return False

    def generate_json(
        self,
        prompt: str,
        system: Optional[str] = None,
        *,
        fallback: Optional[dict] = None,
        seed: Optional[int] = None,
    ) -> Dict[str, Any]:
        url = f"{self.base_url}/api/generate"
        payload: Dict[str, Any] = {
            "model": self.model,
            "prompt": prompt,
            "format": "json",
            "stream": False,
        }
        if system:
            payload["system"] = system
        if seed is not None:
            payload["seed"] = seed

        try:
            resp = requests.post(url, json=payload, timeout=120)
            resp.raise_for_status()
            data = resp.json()
            raw = data.get("response", "")
        except (requests.RequestException, ValueError) as exc:
            merged = dict(fallback or {})
            merged.update(_error(exc))
            return merged

        parsed = _try_parse(raw)
        if isinstance(parsed, dict) and "error" not in parsed:
            return parsed

        # Model returned unparseable/non-object JSON: fall back.
        if fallback:
            merged = dict(fallback)
            merged.setdefault("error", f"ollama unparseable response: {raw[:200]}")
            merged["is_available"] = False
            return merged
        return {"error": f"ollama unparseable response: {raw[:200]}", "is_available": False}


def _try_parse(raw: str):
    import json

    raw = (raw or "").strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        # Tolerate code fences some models add around JSON.
        start = raw.find("{")
        end = raw.rfind("}")
        if start != -1 and end != -1 and end > start:
            try:
                return json.loads(raw[start : end + 1])
            except json.JSONDecodeError:
                pass
        return raw


def _error(exc: Exception) -> dict:
    return {"error": f"{type(exc).__name__}: {exc}", "is_available": False}
