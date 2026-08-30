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
  RelayManager({required this.api}) {
    _receivedController.stream.listen(_onReceived);
  }

  final ApiService api;
  BleTransport? _transport;

  // Emits whenever a report envelope arrives over the mesh (BLE), so the UI
  // can alert the user that a message has been received.
  final _receivedController = StreamController<RelayEnvelope>.broadcast();
  late final Stream<RelayEnvelope> received = _receivedController.stream;

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

  void _onReceived(RelayEnvelope envelope) {
    _refresh();
  }

  // ---- lifecycle ----------------------------------------------------------

  Future<void> start() async {
    if (_started) return;
    await RelayStore.instance.init();
    _started = true;

    // BLE mesh is unavailable in the browser (web), so only run the transport
    // on real devices; on web we keep store/flush (HTTP delivery) but skip the
    // Bluetooth layer to avoid unsupported-plugin noise in the console.
    if (!kIsWeb) {
      _transport = BleTransport(onInbound: _onInbound);
      _transport!.pendingOutboxProvider = () => RelayStore.instance.outboxMessages();
      _transport!.outboxSentCallback = (e) => RelayStore.instance.removeOutbox(e.id);
      await _transport!.start();
      _setStatus('mesh active');
    } else {
      _setStatus('online only (BLE unavailable on web)');
    }

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

  @override
  void dispose() {
    _receivedController.close();
    super.dispose();
  }

  // ---- inbound / outbound -------------------------------------------------

  /// Store an envelope received over BLE into the inbox.
  void _onInbound(RelayEnvelope envelope) {
    if (envelope.kind == 'REPORT') {
      RelayStore.instance.addInbox(envelope);
      _log('inbox + ${envelope.id} origin=${envelope.origin}');
      // Notify the UI so it can show a "message received" alert.
      _receivedController.add(envelope);
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
  ///
  /// Never throws: when the server is unreachable the envelopes stay buffered
  /// and the status simply reports that a retry is pending (the periodic or
  /// manual "Sync now" will try again).
  Future<int> flush() async {
    if (!_started) return 0;
    var delivered = 0;
    var unreachable = false;

    try {
      final inbox = RelayStore.instance.inboxMessages();
      for (final e in inbox) {
        if (e.expired) {
          RelayStore.instance.removeInbox(e.id);
          continue;
        }
        try {
          final ok = await api.deliverRelayMessage(e);
          if (ok) {
            RelayStore.instance.removeInbox(e.id);
            delivered++;
          }
        } catch (_) {
          unreachable = true;
          break;
        }
      }

      final outbox = RelayStore.instance.outboxMessages();
      for (final e in outbox) {
        if (e.expired) {
          RelayStore.instance.removeOutbox(e.id);
          continue;
        }
        try {
          final ok = await api.deliverRelayMessage(e);
          if (ok) {
            RelayStore.instance.removeOutbox(e.id);
            delivered++;
          }
        } catch (_) {
          unreachable = true;
          break;
        }
      }
    } catch (_) {
      unreachable = true;
    }

    if (delivered > 0) {
      _setStatus('delivered $delivered to server');
    } else if (unreachable) {
      _setStatus('server unreachable — will retry automatically');
    }
    _refresh();
    return delivered;
  }
}