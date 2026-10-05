/// 802.11mc / 802.11az WiFi RTT ranging (Android only).
///
/// Uses the maintained `wifi_ftm` plugin. Measures true round-trip-time
/// distance to responder-capable access points — far more accurate than
/// RSSI-estimated distance. Requires Android 9+, a device with RTT
/// hardware, and APs that answer FTM requests.
///
/// Everything degrades gracefully: non-Android -> unsupported, plugin
/// errors -> error string, per-AP failures -> that AP is skipped.
library;

import 'dart:io';

import 'package:wifi_ftm/wifi_ftm.dart';

class RttReading {
  const RttReading({
    required this.meters,
    required this.stddevMeters,
    required this.at,
    required this.is80211az,
  });

  final double meters;
  final double stddevMeters;
  final DateTime at;
  final bool is80211az;
}

class WifiRttService {
  final WifiFtm _ftm = WifiFtm();

  /// null = not checked yet.
  bool? supported;
  String? error;
  bool ranging = false;

  /// BSSID (lowercase) -> latest successful reading.
  final Map<String, RttReading> readings = {};

  void Function()? onUpdate;

  Future<void> checkSupport() async {
    if (!Platform.isAndroid) {
      supported = false;
      return;
    }
    try {
      supported = await _ftm.isSupported();
      final ok = await _ftm.hasPermissions();
      if (supported == true && !ok) {
        error = 'RTT hardware present but location/nearby-device '
            'permission not granted.';
      }
    } catch (e) {
      supported = false;
      error = 'RTT check failed: $e';
    }
    onUpdate?.call();
  }

  /// Range a batch of BSSIDs. Only successful measurements are kept.
  Future<void> rangeBssids(List<String> bssids) async {
    if (supported != true || ranging) return;
    ranging = true;
    error = null;
    onUpdate?.call();
    try {
      final results = await _ftm.startRanging(bssids);
      final now = DateTime.now();
      for (final r in results) {
        if (r.status == RangingStatus.success && r.distanceMm > 0) {
          readings[r.macAddress.toLowerCase()] = RttReading(
            meters: r.distanceMeters,
            stddevMeters: r.distanceStdDevMm / 1000.0,
            at: now,
            is80211az: r.is80211azResult,
          );
        }
      }
      if (readings.isEmpty) {
        error = 'No AP answered RTT — the access points may not '
            'support 802.11mc FTM.';
      }
    } catch (e) {
      error = 'Ranging failed: $e';
    } finally {
      ranging = false;
      onUpdate?.call();
    }
  }

  void clear() {
    readings.clear();
    error = null;
  }
}
