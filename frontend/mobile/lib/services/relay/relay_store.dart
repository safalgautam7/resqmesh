import 'package:hive_flutter/hive_flutter.dart';

import 'relay_envelope.dart';

/// Hive-backed mailboxes: an *outbox* (messages this device must pass on) and
/// an *inbox* (messages received from the mesh, waiting to reach the backend).
class RelayStore {
  RelayStore._();

  static final RelayStore instance = RelayStore._();

  Box<dynamic>? _outbox;
  Box<dynamic>? _inbox;

  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter();
    _outbox = await Hive.openBox<dynamic>('relay_outbox');
    _inbox = await Hive.openBox<dynamic>('relay_inbox');
    // Purge envelopes that expired while the app was closed.
    _dropExpired(_outbox!);
    _dropExpired(_inbox!);
    _ready = true;
  }

  void _dropExpired(Box<dynamic> box) {
    final gone = box.keys
        .where((k) {
          final e = RelayEnvelope.fromStorageMap(
              (box.get(k) as Map).cast<String, dynamic>());
          return e.expired;
        })
        .toList();
    for (final k in gone) {
      box.delete(k);
    }
  }

  // ---- outbox ------------------------------------------------------------
  int get outboxCount => _outbox?.length ?? 0;

  bool outboxContains(String id) => _outbox?.containsKey(id) ?? false;

  void enqueueOutbox(RelayEnvelope envelope) {
    assert(_ready, 'RelayStore.init() first');
    if (envelope.expired) return;
    if (_outbox!.containsKey(envelope.id)) return; // dedup
    _outbox!.put(envelope.id, envelope.toStorageMap());
  }

  List<RelayEnvelope> outboxMessages() =>
      (_outbox?.values ?? <dynamic>[])
          .map((m) => RelayEnvelope.fromStorageMap((m as Map).cast()))
          .toList();

  void removeOutbox(String id) => _outbox?.delete(id);

  // ---- inbox -------------------------------------------------------------
  int get inboxCount => _inbox?.length ?? 0;

  bool inboxContains(String id) => _inbox?.containsKey(id) ?? false;

  /// A peer delivered this envelope to us. Drop expired, dedup by id.
  void addInbox(RelayEnvelope envelope) {
    if (!_ready) return;
    if (envelope.expired) return;
    if (_inbox!.containsKey(envelope.id)) return;
    _inbox!.put(envelope.id, envelope.toStorageMap());
  }

  List<RelayEnvelope> inboxMessages() =>
      (_inbox?.values ?? <dynamic>[])
          .map((m) => RelayEnvelope.fromStorageMap((m as Map).cast()))
          .toList();

  void removeInbox(String id) => _inbox?.delete(id);
}