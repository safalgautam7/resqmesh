"""Models for Stage 3 — offline relay / store-carry-forward.

These model the *logical* relay messages and participating devices on the
server, so the store-carry-forward and recovery behaviour can be exercised,
tested, and demonstrated end-to-end before a physical Bluetooth transport exists
(the mobile app will later write directly to the same data model).
"""

from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone

from apps.emergencies.models import EmergencyReport


class DeliveryStatus(models.TextChoices):
    QUEUED = "QUEUED", "Queued (outbox)"
    IN_TRANSIT = "IN_TRANSIT", "In transit"
    DELIVERED = "DELIVERED", "Delivered to backend"


class RelayMessage(models.Model):
    """A message carried device-to-device until it reaches an online backend.

    ``message_id`` is globally unique so duplicates can be suppressed anywhere
    in the mesh. ``expires_at`` and ``hop_count``/``max_hops`` bound how long and
    how far a message travels (TTL + hop limits).
    """

    message_id = models.CharField(max_length=64, unique=True)
    report = models.ForeignKey(
        EmergencyReport,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="relay_messages",
    )
    payload = models.JSONField(default=dict, blank=True)
    source_node = models.CharField(max_length=64)

    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)

    hop_count = models.PositiveIntegerField(default=0)
    max_hops = models.PositiveIntegerField(
        default=8, validators=[MinValueValidator(1)]
    )

    delivery_status = models.CharField(
        max_length=20,
        choices=DeliveryStatus.choices,
        default=DeliveryStatus.QUEUED,
    )
    attempt_count = models.PositiveIntegerField(default=0)

    # Devices this message has been physically carried by (inventory tracking).
    carried_by = models.ManyToManyField("RelayDevice", blank=True, related_name="carried_messages")

    synced_to_server = models.BooleanField(default=False)

    class Meta:
        ordering = ("created_at",)

    def __str__(self):
        return f"Relay {self.message_id}"

    @property
    def is_expired(self) -> bool:
        if self.expires_at is None:
            return False
        return timezone.now() >= self.expires_at

    @property
    def can_relay_more(self) -> bool:
        return self.hop_count < self.max_hops


class RelayDevice(models.Model):
    """A known participating device/node in the mesh."""

    name = models.CharField(max_length=64, unique=True)
    online = models.BooleanField(default=True)
    last_seen = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("name",)

    def __str__(self):
        return f"{self.name} ({'online' if self.online else 'offline'})"
