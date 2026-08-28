from django.db import transaction

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
    # Stage 2 will invoke the agent workflow here; for now the report is
    # stored even if any asynchronously-triggered analysis fails.
    return report


def update_report_operational(*, report, status=None, priority=None):
    if status is not None and status in ReportStatus.values:
        report.status = status
    if priority is not None and priority in Priority.values:
        report.priority = priority
    report.save(update_fields=["status", "priority", "updated_at"])
    return report
