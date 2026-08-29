"""Inbound wire endpoints for the mobile BLE transport.

Any mesh device that has carried a relay message can hand it to the server
(endpoint deliberately unauthenticated: relayers are store-carry-forward
carriers, not necessarily the message's author). Dedup is idempotent by
``message_id`` so the same message can arrive from several devices.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .models import DeliveryStatus, RelayMessage
from .services import deliver_to_server, make_message_id
from .services import logger

FIELDS = (
    "message_id",
    "payload",
    "source_node",
    "created_at",
    "hop_count",
    "max_hops",
    "delivery_status",
    "synced_to_server",
    "report_id",
)


def _serialize(msg: RelayMessage) -> dict:
    return {
        "message_id": msg.message_id,
        "payload": msg.payload,
        "source_node": msg.source_node,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
        "hop_count": msg.hop_count,
        "max_hops": msg.max_hops,
        "delivery_status": msg.delivery_status,
        "synced_to_server": msg.synced_to_server,
        "report_id": msg.report_id,
    }


@api_view(["GET", "POST"])
@permission_classes([AllowAny])
def relay_messages(request):
    if request.method == "GET":
        qs = RelayMessage.objects.order_by("created_at")
        return Response({"results": [_serialize(m) for m in qs]})

    message_id = request.data.get("message_id") or make_message_id()
    existed = RelayMessage.objects.filter(message_id=message_id).first()
    if existed:
        return Response(
            {"message_id": message_id, "status": "duplicate", **_serialize(existed)}
        )

    msg = RelayMessage.objects.create(
        message_id=message_id,
        payload=request.data.get("payload") or {},
        source_node=request.data.get("source") or "mobile",
        hop_count=int(request.data.get("hops", 0) or 0),
        max_hops=int(request.data.get("max_hops", 8) or 8),
        delivery_status=DeliveryStatus.IN_TRANSIT,
    )
    deliver_to_server(msg)
    msg.refresh_from_db()
    logger.info("relay inbound message_id=%s report_id=%s", msg.message_id, msg.report_id)
    return Response(
        {"message_id": message_id, "status": "received", "report_id": msg.report_id},
        status=201,
    )