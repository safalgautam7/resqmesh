from django.db import transaction
from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import EmergencyReport, Priority, ReportStatus


def create_emergency_report(*, reporter, description, incident_type, latitude=None,
                            longitude=None, location_accuracy=None, people_affected=None):
    """Create an emergency report attributed to the authenticated reporter.

    The reporter is always taken from authentication, never from the client.
    """
    with transaction.atomic():
        report = EmergencyReport.objects.create(
            reporter=reporter,
            description=description,
            incident_type=incident_type,
            latitude=latitude,
            longitude=longitude,
            location_accuracy=location_accuracy,
            people_affected=people_affected,
        )
    # The AI agent workflow is triggered after save (see receiver below). The
    # report is stored even if analysis fails or is slow.
    return report


@receiver(post_save, sender=EmergencyReport, dispatch_uid="run_agent_analysis")
def _run_agent_analysis(sender, instance, created, **kwargs):
    """Invoke the multi-agent pipeline right after a report is first created.

    Wrapped so an AI/provider failure can never prevent the report from being
    saved or returned to the reporter. The coordinator can retry via the admin
    or a management command if needed.
    """
    if not created:
        return
    from apps.agents.services import analyze_report

    try:
        analyze_report(instance)
    except Exception:
        import logging

        logging.getLogger(__name__).exception("agent analysis failed for report %s", instance.pk)


def update_report_operational(*, report, status=None, priority=None):
    if status is not None and status in ReportStatus.values:
        report.status = status
    if priority is not None and priority in Priority.values:
        report.priority = priority
    report.save(update_fields=["status", "priority", "updated_at"])
    return report
