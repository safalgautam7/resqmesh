from django.conf import settings
from django.db import models


class IncidentType(models.TextChoices):
    BUILDING_COLLAPSE = "BUILDING_COLLAPSE", "Building Collapse"
    MEDICAL = "MEDICAL", "Medical"
    FIRE = "FIRE", "Fire"
    FLOOD = "FLOOD", "Flood"
    LANDSLIDE = "LANDSLIDE", "Landslide"
    TRAPPED = "TRAPPED", "Trapped"
    OTHER = "OTHER", "Other"


class ReportStatus(models.TextChoices):
    SUBMITTED = "SUBMITTED", "Submitted"
    REVIEWING = "REVIEWING", "Reviewing"
    VERIFIED = "VERIFIED", "Verified"
    IN_PROGRESS = "IN_PROGRESS", "In Progress"
    RESOLVED = "RESOLVED", "Resolved"
    CLOSED = "CLOSED", "Closed"


class Priority(models.TextChoices):
    UNASSIGNED = "UNASSIGNED", "Unassigned"
    LOW = "LOW", "Low"
    MEDIUM = "MEDIUM", "Medium"
    HIGH = "HIGH", "High"
    CRITICAL = "CRITICAL", "Critical"


class EmergencyReport(models.Model):
    """A citizen's emergency report. The original description is never overwritten."""

    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reports",
    )
    description = models.TextField()
    incident_type = models.CharField(
        max_length=30,
        choices=IncidentType.choices,
        default=IncidentType.OTHER,
    )
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    location_accuracy = models.FloatField(null=True, blank=True)
    people_affected = models.PositiveIntegerField(null=True, blank=True)

    status = models.CharField(
        max_length=20,
        choices=ReportStatus.choices,
        default=ReportStatus.SUBMITTED,
    )
    priority = models.CharField(
        max_length=20,
        choices=Priority.choices,
        default=Priority.UNASSIGNED,
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"RQ-{self.pk} {self.incident_type}"
