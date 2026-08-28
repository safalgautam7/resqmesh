"""Provider factory — resolves the configured AI provider behind one interface."""

from __future__ import annotations

from django.conf import settings

from .base import AnalysisProvider
from .mock import MockProvider


def get_provider() -> AnalysisProvider:
    """Return the configured provider instance.

    Setting ``AI_PROVIDER`` selects the provider (``mock`` | ``ollama``).
    Model and endpoint are taken from settings so the same code works across
    environments. The mock provider is the stable fallback for tests/offline.
    """
    provider = getattr(settings, "AI_PROVIDER", "mock")
    model = getattr(settings, "AI_MODEL", "qwen2.5:1b")
    ollama_url = getattr(settings, "OLLAMA_URL", "http://localhost:11434")

    if provider == "ollama":
        from .ollama import OllamaProvider

        return OllamaProvider(base_url=ollama_url, model=model)

    # mock (default and offline fallback)
    return MockProvider(model=model or "mock-rules")


__all__ = ["get_provider", "AnalysisProvider"]
