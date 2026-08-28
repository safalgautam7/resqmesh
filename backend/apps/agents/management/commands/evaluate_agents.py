"""Run the agent evaluation harness and print a report.

    uv run python manage.py evaluate_agents --provider mock
    uv run python manage.py evaluate_agents --provider ollama
"""

from django.core.management.base import BaseCommand

from apps.agents import evaluation
from apps.agents.providers import get_provider


class Command(BaseCommand):
    help = "Evaluate baseline vs agent pipeline over the scripted scenario set."

    def add_arguments(self, parser):
        parser.add_argument("--provider", default=None, help="Override provider (mock|ollama).")

    def handle(self, *args, **opts):
        provider = get_provider()
        if opts["provider"] and opts["provider"] != provider.name:
            from apps.agents.providers.mock import MockProvider

            if opts["provider"] == "ollama":
                from apps.agents.providers.ollama import OllamaProvider
                from django.conf import settings

                provider = OllamaProvider(base_url=settings.OLLAMA_URL, model=settings.AI_MODEL)
            else:
                provider = MockProvider()

        report = evaluation.evaluate_cases(provider)
        value = evaluation.analyze_pipeline_value(provider)

        self.stdout.write(f"\nAgent pipeline report — provider: {provider.name}")
        self.stdout.write("=" * 60)
        for r in report["rows"]:
            flag = "OK " if (r["ok_incident"] and r["ok_priority"]) else "!! "
            self.stdout.write(
                f"{flag}{r['id']}: expected {r['expected_incident']} / {r['expected_priority']}"
                f"  ->  agent {r['pred_incident']} / {r['pred_priority']}"
                f"  (people {r['pred_people']})"
            )
        self.stdout.write("=" * 60)
        self.stdout.write(f"incident accuracy : {report['incident_accuracy']}")
        self.stdout.write(f"priority ok       : {report['priority_accuracy_or_accept']}")
        self.stdout.write(f"people accuracy   : {report['people_accuracy']}")
        self.stdout.write("--- vs baseline (no AI) ---")
        self.stdout.write(f"baseline incident accuracy : {value['baseline_incident_accuracy']}")
        self.stdout.write(f"baseline priority ok       : {value['baseline_priority_ok']}")
        self.stdout.write(f"delta incident : {value['delta_incident']:+}")
        self.stdout.write(f"delta priority : {value['delta_priority']:+}")
