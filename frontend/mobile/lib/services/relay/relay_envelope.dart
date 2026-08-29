import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'relay_constants.dart';

/// A message stored/carried across the device mesh.
///
/// The wire format (what we serialize over BLE and ship to the backend relay
/// endpoint) is the envelope itself: `{"report": {...}}` payloads are
/// materialized into real EmergencyReports on receipt.
class RelayEnvelope {
  RelayEnvelope({
    required this.id,
    required this.kind,
    required this.origin,
    required this.payload,
    DateTime? createdAt,
    this.expiresAt,
    this.hops = 0,
    this.maxHops = kDefaultMaxHops,
  })  : createdAt = createdAt ?? DateTime.now();

  /// Globally unique — used everywhere for dedup (backend + every mailbox).
  final String id;

  /// Envelope kind, currently 'REPORT'.
  final String kind;

  /// Original author (username) — who created the message.
  final String origin;

  /// Wire payload, e.g. `{"report": {...}}`.
  final Map<String, dynamic> payload;

  final DateTime createdAt;
  final DateTime? expiresAt;

  /// Number of device-to-device hops already travelled.
  final int hops;
  final int maxHops;

  bool get expired {
    final e = expiresAt;
    if (e == null) return false;
    return DateTime.now().isAfter(e);
  }

  bool get canRelay => !expired && hops < maxHops;

  RelayEnvelope copyWith({int? hops}) => RelayEnvelope(
        id: id,
        kind: kind,
        origin: origin,
        payload: payload,
        createdAt: createdAt,
        expiresAt: expiresAt,
        hops: hops ?? this.hops,
        maxHops: maxHops,
      );

  RelayEnvelope relayedOnce() => copyWith(hops: hops + 1);

  /// ToMap for Hive storage (keep field names stable).
  Map<String, dynamic> toStorageMap() => {
        'id': id,
        'kind': kind,
        'origin': origin,
        'payload': payload,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt?.millisecondsSinceEpoch,
        'hops': hops,
        'maxHops': maxHops,
      };

  factory RelayEnvelope.fromStorageMap(Map<String, dynamic> m) => RelayEnvelope(
        id: m['id'] as String,
        kind: m['kind'] as String,
        origin: m['origin'] as String,
        payload: (m['payload'] as Map).cast<String, dynamic>(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
        expiresAt: m['expiresAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['expiresAt'] as int),
        hops: m['hops'] as int? ?? 0,
        maxHops: m['maxHops'] as int? ?? kDefaultMaxHops,
      );

  String toWireJson() => jsonEncode(toStorageMap());

  factory RelayEnvelope.fromWireJson(String s) =>
      RelayEnvelope.fromStorageMap(
          (jsonDecode(s) as Map).cast<String, dynamic>());

  /// Build a REPORT envelope directly from the fields the user submits online;
  /// used when an emergency report cannot be delivered to the backend.
  factory RelayEnvelope.report({
    required String origin,
    required String description,
    required String incidentType,
    double? latitude,
    double? longitude,
    int? peopleAffected,
  }) =>
      RelayEnvelope(
        id: _randomId(),
        kind: 'REPORT',
        origin: origin,
        payload: {
          'report': {
            'description': description,
            'incident_type': incidentType,
            'latitude': ?latitude,
            'longitude': ?longitude,
            'people_affected': ?peopleAffected,
            'reporter_username': origin,
          }
        },
      );

  static String _randomId() => DateTime.now().microsecondsSinceEpoch
      .toRadixString(16)
      .padLeft(13, '0') +
      List.generate(6, (_) => Random().nextInt(16).toRadixString(16)).join();
}

/// Chunking + reassembly for a single logically-sized write.
///
/// Frame (UTF-8 string, single write): `R1|<id>|<byteOffset>|<totalBytes>|<b64>`
/// where `<b64>` is the base64 of one byte-slice of the envelope's wire JSON.
class RelayFramer {
  static List<String> frames(RelayEnvelope envelope) {
    final bytes = utf8.encode(envelope.toWireJson());
    final total = bytes.length;
    final digits = '$total'.length;
    final overhead =
        kFrameMagic.length + 1 + envelope.id.length + 1 + digits + 1 + digits + 1;
    final chunkBytes = ((kMaxFrameBytes - overhead) ~/ 4) * 3;

    if (total <= chunkBytes) {
      return <String>[
        '$kFrameMagic|${envelope.id}|0|$total|${base64Encode(bytes)}'
      ];
    }
    final out = <String>[];
    var offset = 0;
    while (offset < total) {
      final end = offset + chunkBytes > total ? total : offset + chunkBytes;
      out.add('$kFrameMagic|${envelope.id}|$offset|$total|'
          '${base64Encode(bytes.sublist(offset, end))}');
      offset = end;
    }
    return out;
  }

  /// Parse a frame string; null if malformed.
  static ({String id, int offset, int total, String b64})? parse(String frame) {
    final parts = frame.split('|');
    if (parts.length != 5 || parts[0] != kFrameMagic) return null;
    final id = parts[1];
    final offset = int.tryParse(parts[2]);
    final total = int.tryParse(parts[3]);
    if (id.isEmpty || offset == null || total == null || total <= 0) return null;
    return (id: id, offset: offset, total: total, b64: parts[4]);
  }
}

/// Accumulates chunked frames of one message until every byte is filled.
class ChunkAccumulator {
  ChunkAccumulator(this.total)
      : _bytes = Uint8List(total),
        _filled = List<bool>.filled(total, false);

  final int total;
  int _seen = 0;
  final Uint8List _bytes;
  final List<bool> _filled;

  /// Adds one chunk. Returns true when the message is now whole.
  bool add({required int offset, required List<int> chunk}) {
    final end = offset + chunk.length;
    if (end > total) return false;
    _bytes.setRange(offset, end, chunk);
    for (var i = offset; i < end; i++) {
      if (!_filled[i]) {
        _filled[i] = true;
        _seen++;
      }
    }
    return _seen == total;
  }

  String decode() => utf8.decode(_bytes);
}