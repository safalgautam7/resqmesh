from django.test import TestCase

from apps.emergencies.models import EmergencyReport
from apps.relay.models import DeliveryStatus, RelayDevice, RelayMessage
from apps.relay.services import (
    DeviceStore,
    create_relay_message,
    deliver_to_server,
    exchange,
    recover_to_backend,
)


class RelayTestBase(TestCase):
    def mkstore(self, name, online=True):
        dev, _ = RelayDevice.objects.get_or_create(name=name, defaults={"online": online})
        return DeviceStore(dev)


class Stage3OfflineTests(RelayTestBase):
    def test_1_offline_save_buffers_in_outbox(self):
        """A device that is offline does not lose the report; it stays queued."""
        a = self.mkstore("A", online=False)
        msg = create_relay_message(a, {"description": "trapped help", "incident_type": "OTHER"})
        self.assertFalse(msg.synced_to_server)
        self.assertEqual(msg.delivery_status, DeliveryStatus.IN_TRANSIT)
        self.assertIn(msg.message_id, a.message_ids)  # still on device, not lost

    def test_2_recovery_single_online_device(self):
        """An online device delivers its queued message straight to the backend."""
        a = self.mkstore("A", online=False)
        msg = create_relay_message(a, {"description": "fire top floor", "incident_type": "FIRE"})
        a.go_online()
        deliver_to_server(msg)
        msg.refresh_from_db()
        self.assertTrue(msg.synced_to_server)
        self.assertEqual(msg.delivery_status, DeliveryStatus.DELIVERED)


class Stage3RelayTests(RelayTestBase):
    def test_3_direct_relay_stored_exactly_once(self):
        """A -> B: B stores the report exactly once."""
        a = self.mkstore("A", online=False)
        b = self.mkstore("B", online=False)
        msg = create_relay_message(a, {"description": "landslide north road", "incident_type": "LANDSLIDE"})
        exchange(a, b)
        self.assertIn(msg.message_id, b.message_ids)
        self.assertEqual(RelayMessage.objects.filter(message_id=msg.message_id).count(), 1)

    def test_4_multi_hop_relay(self):
        """A -> B -> C: C receives the report, hops bounded."""
        a, b, c = self.mkstore("A"), self.mkstore("B"), self.mkstore("C")
        msg = create_relay_message(a, {"description": "collapse near school", "incident_type": "BUILDING_COLLAPSE"})
        exchange(a, b)
        exchange(b, c)
        self.assertIn(msg.message_id, c.message_ids)
        msg.refresh_from_db()
        self.assertEqual(msg.hop_count, 2)

    def test_5_duplicate_suppression(self):
        """Sending the same message twice yields one logical message."""
        a = self.mkstore("A", online=False)
        b = self.mkstore("B", online=False)
        msg = create_relay_message(a, {"description": "flood street", "incident_type": "FLOOD"})
        exchange(a, b)
        exchange(a, b)  # repeat exchange
        self.assertEqual(RelayMessage.objects.filter(message_id=msg.message_id).count(), 1)
        self.assertEqual(b.message_ids, {msg.message_id})

    def test_6_expiration_not_relayed(self):
        """A message past its TTL is not relayed."""
        a = self.mkstore("A", online=False)
        b = self.mkstore("B", online=False)
        msg = create_relay_message(a, {"description": "old message"}, ttl_seconds=-1)
        self.assertTrue(msg.is_expired)
        transferred = exchange(a, b)
        self.assertEqual(transferred, 0)
        self.assertNotIn(msg.message_id, b.message_ids)


class Stage3FullRecoveryTests(RelayTestBase):
    def test_7_full_recovery_chain(self):
        """A creates -> A offline -> A->B -> B->C -> C online -> Django receives.

        This is the primary Stage 3 demonstration.
        """
        payload = {
            "report": {
                "description": "Family trapped after quake, three people, one injured.",
                "incident_type": "BUILDING_COLLAPSE",
                "people_affected": 3,
                "reporter_username": "relay_hero",
            }
        }
        a = self.mkstore("A", online=False)
        msg = create_relay_message(a, payload, ttl_seconds=3600)

        # A offline : message in outbox, not yet at backend
        self.assertFalse(msg.synced_to_server)

        # A -> B, B -> C (multi-hop store-carry)
        b = self.mkstore("B", online=False)
        c = self.mkstore("C", online=False)
        exchange(a, b)
        exchange(b, c)
        self.assertIn(msg.message_id, c.message_ids)

        # C gains connectivity -> delivers to Django
        c.go_online()
        recover_to_backend([c])
        msg.refresh_from_db()
        self.assertTrue(msg.synced_to_server)

        # Backend now holds a real EmergencyReport from the relayed payload
        report = EmergencyReport.objects.filter(
            description=payload["report"]["description"]
        ).first()
        self.assertIsNotNone(report)
        self.assertEqual(report.people_affected, 3)

    def test_hop_limit_stops_relay(self):
        """A message exceeding max_hops is not relayed further."""
        a = self.mkstore("A", online=False)
        b = self.mkstore("B", online=False)
        c = self.mkstore("C", online=False)
        msg = create_relay_message(a, {"description": "gas leak"}, max_hops=1)
        self.assertEqual(exchange(a, b), 1)  # hop 0 -> 1, allowed
        self.assertEqual(exchange(b, c), 0)  # hop_count >= max_hops -> stop
        self.assertNotIn(msg.message_id, c.message_ids)


class RelayInboundEndpointTests(RelayTestBase):
    def setUp(self):
        self.url = "/api/v1/relay/messages/"
        self.payload = {
            "message_id": "abc123",
            "source": "citizenKarl",
            "hops": 2,
            "max_hops": 8,
            "payload": {
                "report": {
                    "description": "Relayed via BLE from Karl.",
                    "incident_type": "MEDICAL",
                    "people_affected": 2,
                    "reporter_username": "citizenKarl",
                }
            },
        }

    def test_8_post_materializes_relayed_report(self):
        resp = self.client.post(self.url, self.payload, content_type="application/json")
        self.assertEqual(resp.status_code, 201)
        body = resp.json()
        self.assertEqual(body["status"], "received")
        report = EmergencyReport.objects.filter(
            description=self.payload["payload"]["report"]["description"]
        ).first()
        self.assertIsNotNone(report)
        self.assertEqual(report.incident_type, "MEDICAL")

    def test_9_duplicate_post_is_idempotent(self):
        self.client.post(self.url, self.payload, content_type="application/json")
        resp = self.client.post(self.url, self.payload, content_type="application/json")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["status"], "duplicate")
        self.assertEqual(
            EmergencyReport.objects.filter(
                description=self.payload["payload"]["report"]["description"]
            ).count(),
            1,
        )

    def test_get_lists_inbound_messages(self):
        self.client.post(self.url, self.payload, content_type="application/json")
        resp = self.client.get(self.url)
        self.assertEqual(resp.status_code, 200)
        results = resp.json()["results"]
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["message_id"], "abc123")
        self.assertEqual(results[0]["hop_count"], 2)
        self.assertTrue(results[0]["synced_to_server"])
        self.assertIsInstance(results[0]["report_id"], int)
