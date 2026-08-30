"""Store-carry-forward relay services (M11) + relay rules (M12).

Modelled as in-process *virtual relay nodes* (per Stage 3) so the full
device-to-device recovery loop is demonstrable and fully testable before any
physical Bluetooth transport exists. A ``DeviceStore`` is one participating
device; message presence on a device is tracked by the ``carried_by`` M2M.

Relay rules enforced on every transfer (M12):
  - Dedup: a global unique ``message_id``; presence is a set, so a device can
    never store the same message twice and a duplicate exchange is a no-op.
  - TTL: expired messages are not relayed.
  - Hop limit: ``hop_count >= max_hops`` messages are not relayed further.
"""

from __future__ import annotations

import logging
import uuid
from typing import Optional

from django.utils import timezone

from apps.emergencies.models import EmergencyReport

from .connectivity import NodeState
from .models import DeliveryStatus, RelayDevice, RelayMessage

logger = logging.getLogger(__name__)


class DeviceStore:
    """A single participating device with a local outbox/inbox (Node)."""

    def __init__(self, device: RelayDevice):
        self.device = device
        self._state = NodeState(online=device.online)

    # -- connectivity -----------------------------------------------------
    @property
    def online(self) -> bool:
        return self._state.online

    def go_online(self) -> "DeviceStore":
        self._state.go_online()
        self.device.online = True
        self.device.save(update_fields=["online", "last_seen"])
        return self

    def go_offline(self) -> "DeviceStore":
        self._state.go_offline()
        self.device.online = False
        self.device.save(update_fields=["online", "last_seen"])
        return self

    # -- inventory ----------------------------------------------------------
    @property
    def message_ids(self) -> set:
        """message_ids currently carried on this device."""
        return set(self._all().values_list("message_id", flat=True))

    def messages(self) -> list:
        return list(self._all())

    def _all(self):
        return RelayMessage.objects.filter(carried_by=self.device)

    def has(self, message_id: str) -> bool:
        return message_id in self.message_ids

    def __repr__(self):
        return f"<DeviceStore {self.device.name} online={self.online} msgs={len(self.message_ids)}>"


# ---- creation ----------------------------------------------------------

def make_message_id() -> str:
    return uuid.uuid4().hex


def create_relay_message(
    store: DeviceStore,
    payload: dict,
    report: Optional[EmergencyReport] = None,
    *,
    ttl_seconds: Optional[int] = None,
    max_hops: int = 8,
) -> RelayMessage:
    """Create a message in the creating device's outbox.

    If the device is online, it is delivered to the backend immediately; if
    offline, it is buffered for store-carry-forward. The reporter is never lost.
    """
    msg = RelayMessage.objects.create(
        message_id=make_message_id(),
        report=report,
        payload=payload,
        source_node=store.device.name,
        hop_count=0,
        max_hops=max_hops,
        expires_at=timezone.now() + timezone.timedelta(seconds=ttl_seconds)
        if ttl_seconds
        else None,
        delivery_status=DeliveryStatus.IN_TRANSIT,
    )
    msg.carried_by.add(store.device)
    _sync_outbox(store)
    return msg


# ---- inventory exchange (store-carry-forward) --------------------------

def exchange(src: DeviceStore, dst: DeviceStore) -> int:
    """Two devices meet and synchronize their inventories (M11).

    dst sends src the messages src is missing, respecting TTL/hop rules (M12).
    Returns the number of messages transferred.
    """
    src_ids = src.message_ids
    dst_ids = dst.message_ids
    missing_in_src = dst_ids - src_ids

    transferred = 0
    for msg_id in missing_in_src:
        msg = RelayMessage.objects.filter(message_id=msg_id).first()
        if msg is None:
            continue
        if not _may_transfer(msg):
            continue
        msg.carried_by.add(src.device)
        msg.hop_count += 1
        msg.save(update_fields=["hop_count"])
        transferred += 1

    missing_in_dst = src_ids - dst_ids
    for msg_id in missing_in_dst:
        msg = RelayMessage.objects.filter(message_id=msg_id).first()
        if msg is None:
            continue
        if not _may_transfer(msg):
            continue
        msg.carried_by.add(dst.device)
        msg.hop_count += 1
        msg.save(update_fields=["hop_count"])
        transferred += 1

    logger.info("exchange %s<->%s transferred=%d", src.device.name, dst.device.name, transferred)
    return transferred


def _may_transfer(msg: RelayMessage) -> bool:
    """M12 relay rules: don't send expired or over-hopped messages."""
    if msg.is_expired:
        logger.debug("drop %s (expired)", msg.message_id)
        return False
    if msg.hop_count >= msg.max_hops:
        logger.debug("drop %s (max hops)", msg.message_id)
        return False
    return True


# ---- delivery to backend (recovery) ------------------------------------

def _sync_outbox(store: DeviceStore) -> None:
    """If the device is online, deliver all its QUEUED/IN_TRANSIT messages."""
    if not store.online:
        return
    for msg in store.messages():
        if not msg.synced_to_server:
            deliver_to_server(msg)


def deliver_to_server(msg: RelayMessage) -> None:
    """Deliver a relay message to the online Django backend (M13 recovery).

    Marks the message delivered; if the payload embeds an emergency report it
    is materialized as a real EmergencyReport so the full
    A -> B -> C -> Django chain is observable.
    """
    report = msg.report
    payload = msg.payload or {}
    if report is None and payload.get("report"):
        report = _materialize_report(payload["report"], source=msg.source_node)
        msg.report = report
    msg.synced_to_server = True
    msg.delivery_status = DeliveryStatus.DELIVERED
    msg.attempt_count += 1
    msg.save(update_fields=["report", "synced_to_server", "delivery_status", "attempt_count"])
    return report


def _materialize_report(data: dict, source: str):
    from apps.accounts.models import User

    reporter, _ = User.objects.get_or_create(
        username=data.get("reporter_username", f"relay_{source}"),
        defaults={"role": "CITIZEN"},
    )
    return EmergencyReport.objects.create(
        reporter=reporter,
        description=data.get("description", ""),
        incident_type=data.get("incident_type", "OTHER"),
        people_affected=data.get("people_affected"),
        latitude=data.get("latitude"),
        longitude=data.get("longitude"),
    )


# ---- recovery orchestration --------------------------------------------

def recover_to_backend(stores: list) -> int:
    """Any online store delivers everything it carries to the backend.

    Called when a node that has been carrying messages regains connectivity.
    Returns the number of messages delivered.
    """
    delivered = 0
    for store in stores:
        if not store.online:
            continue
        for msg in store.messages():
            if not msg.synced_to_server:
                deliver_to_server(msg)
                delivered += 1
    return delivered
