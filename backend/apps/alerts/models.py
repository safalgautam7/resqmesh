from django.conf import settings
from django.db import models
from django.utils import timezone


class AlertSeverity(models.TextChoices):
    INFO = "INFO", "Info"
    WARNING = "WARNING", "Warning"
    HIGH = "HIGH", "High"
    CRITICAL = "CRITICAL", "Critical"


class AlertStatus(models.TextChoices):
    ACTIVE = "ACTIVE", "Active"
    EXPIRED = "EXPIRED", "Expired"
    CANCELLED = "CANCELLED", "Cancelled"


class OfficialAlert(models.Model):
    """Official emergency alert issued by an authorized authority/coordinator.

    Distinct from citizen reports. Never intended to be created by citizens.
    """

    title = models.CharField(max_length=200)
    message = models.TextField()
    severity = models.CharField(
        max_length=20, choices=AlertSeverity.choices, default=AlertSeverity.WARNING
    )
    target_area = models.CharField(max_length=200, blank=True, default="")
    status = models.CharField(
        max_length=20, choices=AlertStatus.choices, default=AlertStatus.ACTIVE
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="created_alerts",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)

    def effective_status(self):
        """Return ACTIVE only if not expired/cancelled and within expiry window."""
        if self.status == AlertStatus.CANCELLED:
            return AlertStatus.CANCELLED
        if self.expires_at is not None and timezone.now() >= self.expires_at:
            return AlertStatus.EXPIRED
        return self.status

    @property
    def is_active(self):
        return self.effective_status() == AlertStatus.ACTIVE

    def __str__(self):
        return f"{self.title} [{self.effective_status()}]"
