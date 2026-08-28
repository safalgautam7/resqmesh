"""Re-run / backfill the AI agent analysis for reports.

Usage:
    uv run python manage.py analyze_reports                # all without analysis
    uv run python manage.py analyze_reports --report 12     # one report (force)
    uv run python manage.py analyze_reports --provider ollama --all
"""

from django.core.management.base import BaseCommand

from apps.agents.services import analyze_report
from apps.emergencies.models import EmergencyReport


class Command(BaseCommand):
    help = "Run/refresh the multi-agent analysis over emergency reports."

    def add_arguments(self, parser):
        parser.add_argument("--report", type=int, help="Analyze/refresh a specific report id.")
        parser.add_argument("--all", action="store_true", help="Force re-analysis of all reports.")
        parser.add_argument("--unprocessed", action="store_true", help="Only reports lacking an analysis (default).")

    def handle(self, *args, **opts):
        qs = EmergencyReport.objects.all()
        if opts["report"]:
            qs = qs.filter(pk=opts["report"])
        if opts["unprocessed"] and not opts["all"]:
            qs = qs.filter(analysis__isnull=True)
        total = qs.count()
        done = 0
        for r in qs.iterator():
            analyze_report(r, force=bool(opts["all"] or opts["report"]))
            done += 1
            self.stdout.write(f"analyzed report {r.pk}")
        self.stdout.write(self.style.SUCCESS(f"analyzed {done}/{total} report(s)"))
