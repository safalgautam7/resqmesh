import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:resqmesh/services/relay/relay_envelope.dart';

void main() {
  RelayEnvelope envelope() => RelayEnvelope.report(
        origin: 'karl',
        description: 'Family trapped near the market, one injured.',
        incidentType: 'BUILDING_COLLAPSE',
        peopleAffected: 3,
        latitude: 28.2,
        longitude: 83.9,
      );

  test('report envelope carries the backend wire payload', () {
    final e = envelope();
    expect(e.kind, 'REPORT');
    expect(e.origin, 'karl');
    expect(e.hops, 0);
    expect(e.canRelay, isTrue);
    final report = e.payload['report'] as Map<String, dynamic>;
    expect(report['reporter_username'], 'karl');
    expect(report['incident_type'], 'BUILDING_COLLAPSE');
    expect(report['people_affected'], 3);
  });

  test('single-frame envelope round-trips through the wire JSON', () {
    final e = envelope();
    final parsed = RelayEnvelope.fromWireJson(e.toWireJson());
    expect(parsed.id, e.id);
    expect(parsed.origin, e.origin);
    expect(parsed.payload, e.payload);
  });

  test('framer emits one frame for a small envelope and reassembles', () {
    final e = envelope();
    final frames = RelayFramer.frames(e);
    expect(frames, hasLength(1));

    final chunk = RelayFramer.parse(frames.single)!;
    expect(chunk.id, e.id);
    expect(chunk.offset, 0);
    expect(chunk.total, greaterThan(0));

    final acc = ChunkAccumulator(chunk.total);
    expect(
        acc.add(offset: chunk.offset, chunk: _b64(chunk.b64)), isTrue);
    expect(RelayEnvelope.fromWireJson(acc.decode()).id, e.id);
  });

  test('large envelope is chunked and reassembled across many frames', () {
    final big = RelayEnvelope.report(
      origin: 'karl',
      description: 'P' * 4000,
      incidentType: 'FLOOD',
    );
    final frames = RelayFramer.frames(big);
    expect(frames.length, greaterThan(1));

    RelayEnvelope? rebuilt;
    final acc = <String, ChunkAccumulator>{};
    for (final f in frames) {
      final c = RelayFramer.parse(f)!;
      final a = acc.putIfAbsent(c.id, () => ChunkAccumulator(c.total));
      if (a.add(offset: c.offset, chunk: _b64(c.b64))) {
        rebuilt = RelayEnvelope.fromWireJson(a.decode());
        acc.remove(c.id);
      }
    }
    final completed = rebuilt;
    if (completed == null) {
      fail('envelope was not reassembled');
    }
    expect(completed.id, big.id);
    expect(completed.payload, big.payload);
  });

  test('malformed frames are rejected', () {
    expect(RelayFramer.parse('garbage'), isNull);
    expect(RelayFramer.parse('R1|id|0|word|x'), isNull);
    expect(RelayFramer.parse('R1||0|100|abc'), isNull);
    expect(RelayFramer.parse('R2|id|0|100|abc'), isNull);
    expect(RelayFramer.parse('R1|id|0|0|abc'), isNull);
  });

  test('expired / max-hop envelopes cannot relay', () {
    final old = RelayEnvelope.report(
      origin: 'karl',
      description: 'stale',
      incidentType: 'OTHER',
    );
    final stale = RelayEnvelope(
      id: old.id,
      kind: old.kind,
      origin: old.origin,
      payload: old.payload,
      createdAt: DateTime.now().subtract(const Duration(hours: 30)),
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final maxed = old.copyWith(hops: 8);
    expect(stale.expired, isTrue);
    expect(stale.canRelay, isFalse);
    expect(maxed.canRelay, isFalse);
  });
}

List<int> _b64(String b64) => base64Decode(b64);