/// BLE mesh transport constants.
///
/// One 128-bit service UUID is broadcast on ALL devices (dedup + filtering);
/// every device acts as both a GATT server (advertise + accept writes) and a
/// GATT client (scan + connect + write its own outbox to a peer).
const String kRelayServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kRelayWriteCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// Attribute MTU after negotiation; keep one write comfortably under it.
const int kRelayMtu = 512;

/// Maximum bytes carried by a single characteristic write.
const int kMaxFrameBytes = 470;

/// Wire-frame version tag (first frame byte magic + version).
const String kFrameMagic = 'R1';

/// Relay rules (mirror backend M12).
const int kDefaultMaxHops = 8;
const int kDefaultTtlHours = 24;