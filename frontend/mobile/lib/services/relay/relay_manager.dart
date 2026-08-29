import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import 'ble_transport.dart';
import 'relay_envelope.dart';
import 'relay_store.dart';

/// Owns the device-to-device relay lifecycle:
///   * persistent Hive outbox/inbox,
///   * the concurrent BLE peripheral + central transport,
///   * periodic + manual *recovery*: any carried envelope (inbox or my own
///     outbox) is delivered to the backend as soon as connectivity exists.
class RelayManager extends ChangeNotifier {
  RelayManager({required this.api});

  final ApiService api;
  BleTransport? _transport;

  int _outbox = 0;
  int _inbox = 0;
  String _status = 'idle';

  bool _started = false;

  int get outboxPending => _outbox;
  int get inboxPending => _inbox;
  String get status => _status;
  bool get started => _started;

  void _log(String s) => debugPrint('[relay] $s');

  void _refresh() {
    _outbox = RelayStore.instance.outboxCount;
    _inbox = RelayStore.instance.inboxCount;
    notifyListeners();
  }

  void _setStatus(String s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  // ---- lifecycle ----------------------------------------------------------

  Future<void> start() async {
    if (_started) return;
    await RelayStore.instance.init();
    _started = true;

    _transport = BleTransport(onInbound: _onInbound);
    _transport!.pendingOutboxProvider = () => RelayStore.instance.outboxMessages();
    _transport!.outboxSentCallback = (e) => RelayStore.instance.removeOutbox(e.id);
    await _transport!.start();
    _setStatus('mesh active');

    _flushTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(flush()),
    );
    _refresh();
    _log('relay started');
  }

  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _transport?.stop();
    _transport = null;
    _started = false;
    _setStatus('idle');
  }

  // ---- inbound / outbound -------------------------------------------------

  /// Store an envelope received over BLE into the inbox.
  void _onInbound(RelayEnvelope envelope) {
    if (envelope.kind == 'REPORT') {
      RelayStore.instance.addInbox(envelope);
      _log('inbox + ${envelope.id} origin=${envelope.origin}');
    }
    _refresh();
  }

  /// Offline path: an emergency report could not reach the backend, so buffer
  /// it in the outbox to be carried through the mesh when we meet a peer.
  void enqueueOutbox(RelayEnvelope envelope) {
    if (!_started) return;
    RelayStore.instance.enqueueOutbox(envelope);
    _log('outbox + ${envelope.id}');
    _refresh();
  }

  // ---- recovery (try-on-drive + manual flush) -----------------------------

  Timer? _flushTimer;

  /// Push every carried envelope to the backend while we are online.
  /// Returns the number newly delivered.
  Future<int> flush() async {
    if (!_started) return 0;
    var delivered = 0;

    final inbox = RelayStore.instance.inboxMessages();
    for (final e in inbox) {
      if (e.expired) {
        RelayStore.instance.removeInbox(e.id);
        continue;
      }
      final ok = await api.deliverRelayMessage(e);
      if (ok) {
        RelayStore.instance.removeInbox(e.id);
        delivered++;
      }
    }

    final outbox = RelayStore.instance.outboxMessages();
    for (final e in outbox) {
      if (e.expired) {
        RelayStore.instance.removeOutbox(e.id);
        continue;
      }
      final ok = await api.deliverRelayMessage(e);
      if (ok) {
        RelayStore.instance.removeOutbox(e.id);
        delivered++;
      }
    }

    if (delivered > 0) {
      _setStatus('delivered $delivered to server');
    }
    _refresh();
    return delivered;
  }
}