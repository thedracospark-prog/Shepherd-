/// BLE advertisement decoding: turn raw ad bytes into honest device labels.
///
/// What we get from `universal_ble` per device: a manufacturer-data list
/// (Bluetooth SIG company ID + payload) and advertised service UUIDs.
/// From those we derive:
/// - [vendor]: e.g. 'APPLE', 'SAMSUNG' — from the company ID.
/// - [kind]: e.g. 'AIRPODS (est.)' — from Apple Continuity subtypes and
///   well-known service UUIDs.
/// - [serviceLabels]: human tags like 'HEART RATE', 'BEACON (EDDYSTONE)'.
///
/// Honest limits, stated in the UI: these are heuristics from *public* ad
/// formats. Any device can spoof any ad, and most phones randomize their
/// MAC, so labels are estimates and counts are approximate — never
/// presented as identification.
library;

/// Vendor names for the Bluetooth SIG company IDs we actually see in
/// the wild. Unknown IDs render as '0xXXXX'.
const Map<int, String> bleVendors = {
  0x0006: 'MICROSOFT',
  0x004C: 'APPLE',
  0x0059: 'NORDIC',
  0x0075: 'SAMSUNG',
  0x00E0: 'GOOGLE',
  0x012D: 'SONY',
};

/// Apple Continuity frame types (first manufacturer-payload byte).
/// Reverse-engineered public knowledge; subtypes we don't recognize
/// fall back to a generic continuity label.
const Map<int, String> appleContinuityKinds = {
  0x02: 'NEARBY DEVICE',
  0x05: 'AIRPODS',
  0x07: 'AIRDROP',
  0x09: 'NEARBY ACTION',
  0x0C: 'HANDOFF',
  0x0D: 'NEARBY INFO',
  0x0F: 'FIND MY',
  0x10: 'PROXIMITY PAIRING',
  0x12: 'HEY SIRI',
};

/// Well-known 16-bit service UUIDs -> human labels.
const Map<String, String> bleServiceLabels = {
  '180D': 'HEART RATE',
  '181A': 'ENV SENSOR',
  '180F': 'BATTERY',
  '1812': 'HID DEVICE',
  'FD6F': 'EXPOSURE NOTIFY',
  'FEAA': 'BEACON (EDDYSTONE)',
};

/// Decoded identity of one BLE advertiser. All fields nullable/empty
/// when the ad carries nothing recognizable.
class BleDecodedInfo {
  const BleDecodedInfo({
    this.vendor,
    this.kind,
    this.serviceLabels = const [],
    this.companyId,
  });

  /// e.g. 'APPLE'. Null when the company ID is unknown/absent.
  final String? vendor;

  /// e.g. 'AIRPODS (est.)'. Null when nothing recognizable.
  final String? kind;

  /// e.g. ['HEART RATE']. Empty when no known service UUIDs.
  final List<String> serviceLabels;

  /// Raw company ID for display when the vendor is unknown.
  final int? companyId;

  /// One-line summary for the device row, e.g. 'APPLE · AIRPODS (est.)'.
  String get summary {
    final parts = <String>[];
    if (kind != null) {
      parts.add(kind!);
    } else if (vendor != null) {
      parts.add('$vendor DEVICE (est.)');
    }
    if (parts.isEmpty) {
      if (companyId != null) {
        final hex =
            '0x${companyId!.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        return 'UNKNOWN ADVERTISER ($hex)';
      }
      return 'UNKNOWN ADVERTISER';
    }
    return parts.join(' · ');
  }
}

/// Decode one advertiser's manufacturer data + service UUIDs.
///
/// [manufacturerData] is a list of (companyId, payload) records.
/// [services] are advertised UUID strings in any common text form.
BleDecodedInfo decodeBleAdvertiser(
  List<({int companyId, List<int> payload})> manufacturerData,
  List<String> services,
) {
  String? vendor;
  String? kind;
  int? companyId;

  for (final m in manufacturerData) {
    companyId ??= m.companyId;
    vendor ??= bleVendors[m.companyId];
    // Apple Continuity: first payload byte is the frame type.
    if (m.companyId == 0x004C && m.payload.isNotEmpty) {
      final sub = appleContinuityKinds[m.payload[0]] ?? 'CONTINUITY DEVICE';
      kind ??= 'APPLE · $sub (est.)';
    }
  }

  final serviceLabels = <String>[];
  for (final s in services) {
    final norm =
        s.toUpperCase().replaceAll('-', '').replaceAll(' ', '');
    for (final e in bleServiceLabels.entries) {
      if (norm.contains(e.key) && !serviceLabels.contains(e.value)) {
        serviceLabels.add(e.value);
      }
    }
  }

  // Service-based kind guesses, only when Apple didn't already answer.
  kind ??= () {
    if (serviceLabels.contains('EXPOSURE NOTIFY')) {
      return 'PHONE · EXPOSURE NOTIFY (est.)';
    }
    if (serviceLabels.contains('HEART RATE')) {
      return 'FITNESS SENSOR (est.)';
    }
    if (serviceLabels.contains('BEACON (EDDYSTONE)')) {
      return 'BEACON (est.)';
    }
    return null;
  }();

  return BleDecodedInfo(
    vendor: vendor,
    kind: kind,
    serviceLabels: serviceLabels,
    companyId: companyId,
  );
}
