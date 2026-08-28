"""Notification service abstraction.

Alert creation should persist the alert record first, then trigger delivery
through a provider. Providers are swappable (console, FCM, web push, SMS...).
"""


class NotificationProvider:
    """Base interface for a notification provider."""

    def send(self, *, user_ids, title, body, data=None):
        raise NotImplementedError


class ConsoleNotificationProvider(NotificationProvider):
    """Dummy provider that logs notifications. Useful for dev and tests."""

    def send(self, *, user_ids, title, body, data=None):
        # Logging is intentionally lightweight; nothing is persisted here.
        import logging

        logger = logging.getLogger("resqmesh.notifications")
        logger.info(
            "Notification -> users=%s title=%r body=%r data=%r",
            len(user_ids), title, body, data or {},
        )
        return len(user_ids)


def get_notification_provider():
    """Return the configured notification provider (swap provider here later)."""
    return ConsoleNotificationProvider()
