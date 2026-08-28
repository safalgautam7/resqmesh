from uuid import uuid4

from apps.notifications.services import get_notification_provider

from .models import OfficialAlert


def notify_alert_created(alert):
    """Trigger notification delivery for a persisted alert.

    Best-effort: must never block or undo alert creation.
    """
    provider = get_notification_provider()
    provider.send(
        user_ids=[],  # subscriber targeting resolved in a later stage
        title=f"🚨 {alert.title}",
        body=alert.message,
        data={"alert_id": str(alert.id), "request_id": str(uuid4())},
    )
