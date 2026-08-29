import 'dart:async';
import 'dart:convert';

import 'package:ble_peripheral/ble_peripheral.dart' as peripheral;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'relay_constants.dart';
import 'relay_envelope.dart';

/// Device-to-device Bluetooth-Low-Energy transport for the relay mesh.
///
/// Every device runs BOTH roles concurrently:
///   * peripheral — advertises [kRelayServiceUuid] and accepts writes of
///     relay envelopes onto its write characteristic;
///   * central — periodically scans for peers with [kRelayServiceUuid],
///     connects and writes its own outbox across.
/// Inbound envelopes are handed to the [onInbound] callback (the store inbox).
class BleTransport {
  BleTransport({required this.onInbound, this.logCallback});

  final void Function(RelayEnvelope) onInbound;

  /// Optional debug sink (defaults to debugPrint).
  final void Function(String)? logCallback;

  final Map<String, ChunkAccumulator> _reassembly = <String, ChunkAccumulator>{};

  bool _running = false;
  bool _centralBusy = false;
  final Map<String, DateTime> _lastHandled = <String, DateTime>{};

  void _log(String s) {
    final cb = logCallback;
    if (cb != null) {
      cb(s);
    } else {
      debugPrint('[relay-ble] $s');
    }
  }

  // ---- lifecycle ----------------------------------------------------------

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _log('starting BLE transport');
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      _log('turnOn failed: $e');
    }
    await _startPeripheral();
    unawaited(_centralLoop());
  }

  Future<void> stop() async {
    _running = false;
    try {
      await peripheral.BlePeripheral.stopAdvertising();
    } catch (_) {}
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _log('BLE transport stopped');
  }

  // ---- peripheral role ----------------------------------------------------

  Future<void> _startPeripheral() async {
    try {
      await peripheral.BlePeripheral.initialize();
      await peripheral.BlePeripheral.clearServices();
      await peripheral.BlePeripheral.addService(
        peripheral.BleService(
          uuid: kRelayServiceUuid,
          primary: true,
          characteristics: [
            peripheral.BleCharacteristic(
              uuid: kRelayWriteCharUuid,
              properties: [
                peripheral.CharacteristicProperties.read.index,
                peripheral.CharacteristicProperties.write.index,
                peripheral.CharacteristicProperties.writeWithoutResponse.index,
              ],
              permissions: [
                peripheral.AttributePermissions.readable.index,
                peripheral.AttributePermissions.writeable.index,
              ],
              value: null,
            ),
          ],
        ),
      );
      peripheral.BlePeripheral.setConnectionStateChangeCallback(
          (deviceId, connected) {
        _log('peer ${connected ? "connected" : "disconnected"}: $deviceId');
      });
      peripheral.BlePeripheral.setWriteRequestCallback(
          (deviceId, characteristicId, offset, value) {
        if (value != null) {
          _handleInboundData(Uint8List.fromList(value));
        }
        return peripheral.WriteRequestResult(value: value);
      });
      peripheral.BlePeripheral.setAdvertisingStatusUpdateCallback(
          (advertising, error) {
        _log('advertising=$advertising err=$error');
      });
      await peripheral.BlePeripheral.startAdvertising(
        services: [kRelayServiceUuid],
      );
      _log('advertising $kRelayServiceUuid');
    } catch (e, st) {
      _log('peripheral failed: $e\n$st');
    }
  }

  String? _handleInboundData(Uint8List data) {
    String frame;
    try {
      frame = utf8.decode(data);
    } catch (_) {
      return null;
    }
    final chunk = RelayFramer.parse(frame);
    if (chunk == null) return null;

    if (chunk.total > 16 * 1024) return null;
    final acc = _reassembly.putIfAbsent(
        chunk.id, () => ChunkAccumulator(chunk.total));
    final complete = acc.add(offset: chunk.offset, chunk: base64Decode(chunk.b64));
    if (!complete) return null;

    _reassembly.remove(chunk.id);
    try {
      final envelope = RelayEnvelope.fromWireJson(acc.decode());
      if (envelope.id != chunk.id) return null; // tampered
      _log('received envelope ${envelope.id} origin=${envelope.origin}');
      onInbound(envelope);
      return envelope.id;
    } catch (e) {
      _log('inbound envelope parse error: $e');
      return null;
    }
  }

  // ---- central role -------------------------------------------------------

  Future<void> _centralLoop() async {
    while (_running) {
      try {
        await _oneCentralCycle();
      } catch (e, st) {
        _log('central cycle error: $e\n$st');
      }
      await Future<void>.delayed(const Duration(seconds: 6));
    }
  }

  Future<void> _oneCentralCycle() async {
    if (_centralBusy || !_running) return;

    if (!await _isAdapterOn()) return;

    try {
      await FlutterBluePlus.startScan(withServices: [Guid(kRelayServiceUuid)]);
    } catch (e) {
      return;
    }

    // let the scan accumulate results
    await Future<void>.delayed(const Duration(seconds: 9));

    List<ScanResult> results = <ScanResult>[];
    try {
      results = FlutterBluePlus.lastScanResults.where((r) {
        return r.advertisementData.serviceUuids
            .map((u) => u.toString().toLowerCase())
            .contains(kRelayServiceUuid.toLowerCase());
      }).toList();
    } catch (_) {
      results = <ScanResult>[];
    }
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    for (final r in results) {
      if (!_running) break;
      await _sendOutboxTo(r.device);
    }
  }

  Future<bool> _isAdapterOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.firstWhere(
        (s) => s == BluetoothAdapterState.on,
        orElse: () => BluetoothAdapterState.off,
      );
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendOutboxTo(BluetoothDevice device) async {
    if (_centralBusy) return;
    _centralBusy = true;
    try {
      final key = '${device.remoteId}';
      final last = _lastHandled[key];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 45)) {
        return; // recently tried
      }
      _lastHandled[key] = DateTime.now();

      _log('connecting to peer ${device.remoteId}');
      await device.connect(mtu: kRelayMtu, timeout: const Duration(seconds: 30));

      final conn = await device.connectionState.firstWhere(
        (s) => s == BluetoothConnectionState.connected,
        orElse: () => BluetoothConnectionState.disconnected,
      );
      if (conn != BluetoothConnectionState.connected) {
        _log('peer ${device.remoteId} did not connect');
        return;
      }

      final services = await device.discoverServices();
      BluetoothCharacteristic? writeChar;
      outer:
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.uuid == Guid(kRelayWriteCharUuid) &&
              c.properties.writeWithoutResponseOrWrite) {
            writeChar = c;
            break outer;
          }
        }
      }
      if (writeChar == null) {
        _log('peer ${device.remoteId}: write char not found');
        return;
      }

      // outbox must be snapshotted while iterating (writes remove entries)
      final outgoing = pendingOutboxProvider?.call() ?? <RelayEnvelope>[];
      if (outgoing.isEmpty) {
        _log('peer ${device.remoteId}: nothing to send');
        return;
      }

      var sent = 0;
      for (final envelope in outgoing) {
        if (!envelope.canRelay) continue;
        final framesRaw = RelayFramer.frames(envelope);
        if (framesRaw.isEmpty) continue;
        var wrote = true;
        for (final f in framesRaw) {
          try {
            await writeChar.write(utf8.encode(f), withoutResponse: false);
          } catch (e) {
            _log('write failed for ${envelope.id}: $e');
            wrote = false;
            break;
          }
        }
        if (wrote) {
          outboxSentCallback?.call(envelope);
          sent++;
        }
      }
      _log('peer ${device.remoteId}: sent $sent envelope(s)');
    } catch (e, st) {
      _log('transfer to ${device.remoteId} failed: $e\n$st');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
      _centralBusy = false;
    }
  }

  /// Hooks supplied by RelayManager so the transport does not reach into the
  /// Hive store directly.
  List<RelayEnvelope> Function()? pendingOutboxProvider;
  void Function(RelayEnvelope)? outboxSentCallback;
}

extension _IsWriteable on CharacteristicProperties {
  bool get writeWithoutResponseOrWrite => write || writeWithoutResponse;
}