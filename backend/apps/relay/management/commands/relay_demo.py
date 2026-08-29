"""Run the primary Stage 3 demonstration: an offline report carried
device-to-device until one node returns online and delivers it to Django.

    uv run python manage.py relay_demo

Shows the full recovery loop:
    A creates report -> A offline (outbox) -> A->B -> B->C -> C online -> Django
"""

from django.core.management.base import BaseCommand

from apps.emergencies.models import EmergencyReport
from apps.relay.models import RelayDevice, RelayMessage
from apps.relay.services import (
    DeviceStore,
    create_relay_message,
    exchange,
    recover_to_backend,
)


class Command(BaseCommand):
    help = "Demonstrate Stage 3 store-carry-forward recovery."

    def handle(self, *args, **opts):
        for name in ("relayA", "relayB", "relayC"):
            RelayDevice.objects.get_or_create(name=name, defaults={"online": False})

        A, B, C = (DeviceStore(RelayDevice.objects.get(name=n)) for n in ("relayA", "relayB", "relayC"))
        A.go_offline()

        payload = {
            "report": {
                "description": "Family trapped after a quake, three people, one injured near the market.",
                "incident_type": "BUILDING_COLLAPSE",
                "people_affected": 3,
                "reporter_username": "relay_demo",
            }
        }

        self.stdout.write("Device A (OFFLINE) creates a report -> held in local outbox.")
        msg = create_relay_message(A, payload, ttl_seconds=3600)
        self.stdout.write(f"  message_id={msg.message_id[:8]}... synced_to_server={msg.synced_to_server}")

        self.stdout.write("A meets B -> exchange")
        n = exchange(A, B)
        self.stdout.write(f"  transferred {n} message(s) A->B ; B now has {len(B.message_ids)}")

        self.stdout.write("B meets C -> exchange")
        n = exchange(B, C)
        self.stdout.write(f"  transferred {n} message(s) B->C ; C now has {len(C.message_ids)}")

        self.stdout.write("C regains connectivity -> delivers to Django backend")
        C.go_online()
        delivered = recover_to_backend([C])
        self.stdout.write(f"  delivered {delivered} message(s) to backend")

        msg.refresh_from_db()
        self.stdout.write(
            f"  relay message synced_to_server={msg.synced_to_server} status={msg.delivery_status}"
        )
        report = EmergencyReport.objects.filter(
            description__startswith="Family trapped"
        ).first()
        if report:
            self.stdout.write(
                self.style.SUCCESS(
                    f"  Django now holds EmergencyReport #{report.pk} "
                    f"({report.incident_type}, people={report.people_affected}) "
                    f"reaching the backend via C."
                )
            )
