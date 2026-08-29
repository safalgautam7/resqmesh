"""Connectivity detection (M10).

Determines whether a node is online/offline and, by extension, whether a
message should go straight to the server or stay in the local outbox.

In the physical app this maps to checking for reachable network/Bluetooth peers.
Here it is a thin, swappable abstraction so the rest of the relay logic is
transport-agnostic and testable.
"""

from __future__ import annotations

from django.utils import timezone


class NodeState:
    """Simple online/offline state for a node."""

    ONLINE = "online"
    OFFLINE = "offline"

    def __init__(self, online: bool = True):
        self.online = online

    @property
    def status(self) -> str:
        return self.ONLINE if self.online else self.OFFLINE

    def go_online(self) -> None:
        self.online = True

    def go_offline(self) -> None:
        self.online = False


def connectivity_status() -> bool:
    """Probe whether the current device has connectivity.

    A placeholder for real network reachability checks; kept swappable so the
    mobile app can substitute a real detector without touching relay logic.
    """
    return True


def should_buffer_message(state: NodeState) -> bool:
    """Decide whether a newly-created message should go to the remote server
    immediately (online) or stay in the local outbox (offline)."""
    return not state.online
