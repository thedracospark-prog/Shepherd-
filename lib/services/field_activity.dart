/// Field activity fusion: combine WiFi disturbance episodes, BLE signal
/// dips, and BLE sighting history into one activity level.
///
/// Scoring (documented, tunable):
/// - +2 per currently-disturbed WiFi AP (active crossing)
/// - +1 per WiFi crossing closed in the last 5 minutes
/// - +2 per BLE device currently in a signal dip
/// - +1 per BLE dip episode closed in the last 5 minutes
/// - +1 per BLE device first seen in the last 2 minutes (new arrival)
/// - +0.5 per BLE device seen in the last 5 minutes (capped at +3)
///
/// ACTIVE >= 5, STIRRING >= 2, else QUIET.
///
/// Honest scope, stated in the UI: this is *combined sensor activity*,
/// not a person count. Phone MACs randomize, so BLE counts are
/// approximate; a single phone can look like several advertisers.
library;

import 'ble_scan.dart';
import 'wifi_sense.dart';

class FieldActivityReport {
  const FieldActivityReport({
    required this.level,
    required this.score,
    required this.detail,
  });

  /// QUIET / STIRRING / ACTIVE.
  final String level;
  final double score;

  /// e.g. '2 WIFI LINKS HOT · 6 BLE SEEN (5 MIN)'.
  final String detail;
}

class FieldActivityService {
  const FieldActivityService();

  FieldActivityReport report(
      WifiVisionService wifi, BleScanService ble) {
    final now = DateTime.now();
    double score = 0;

    final activeWifi = wifi.activeCrossings.length;
    score += activeWifi * 2;

    var recentWifi = 0;
    for (final c in wifi.crossings) {
      final end = c.endTime;
      if (end != null && now.difference(end).inMinutes < 5) {
        recentWifi++;
      }
    }
    score += recentWifi;

    final activeBle = ble.activeBleDips.length;
    score += activeBle * 2;

    var recentBle = 0;
    for (final e in ble.bleEvents) {
      final end = e.endTime;
      if (end != null && now.difference(end).inMinutes < 5) {
        recentBle++;
      }
    }
    score += recentBle;

    var bleRecent = 0;
    var bleNew = 0;
    for (final s in ble.sightings.values) {
      if (now.difference(s.lastSeen).inMinutes < 5) bleRecent++;
      if (now.difference(s.firstSeen).inMinutes < 2) bleNew++;
    }
    score += (bleRecent * 0.5).clamp(0, 3);
    score += (bleNew * 1.0).clamp(0, 3);

    final level =
        score >= 5 ? 'ACTIVE' : score >= 2 ? 'STIRRING' : 'QUIET';
    final detail =
        '$activeWifi WIFI HOT · $activeBle BLE DIPPING · '
        '$bleRecent BLE SEEN (5 MIN)';
    return FieldActivityReport(
        level: level, score: score, detail: detail);
  }
}
