import 'dart:collection';
import 'dart:math' as math;

import '../models/link_sample.dart';

/// Tunables for the tripwire detector. Mirrors silvus_tripwire.py defaults.
class TripwireConfig {
  const TripwireConfig({
    this.baselineWindow = 60,
    this.minBaseline = 10,
    this.dipThreshold = 6.0,
    this.confirmPolls = 2,
  });

  /// Rolling history kept per link direction (in polls).
  final int baselineWindow;

  /// Polls of history before the baseline is trusted.
  final int minBaseline;

  /// Dip depth (radio units) that counts as a possible crossing.
  final double dipThreshold;

  /// Consecutive polls above threshold required to confirm an event.
  /// Lower = faster alerts, higher = fewer false alarms.
  final int confirmPolls;
}

/// Rolling-median baseline dip detector, one instance per link direction.
///
/// For each poll: baseline = median of the last N SNR samples;
/// dip = baseline − snr. A dip at/above [TripwireConfig.dipThreshold] for
/// [TripwireConfig.confirmPolls] consecutive polls emits a [CrossingEvent]
/// carrying the disturbance's peak depth and duration.
/// All magnitudes are estimates in radio-internal units.
class Tripwire {
  Tripwire({TripwireConfig? config})
      : config = config ?? const TripwireConfig();

  final TripwireConfig config;

  final Map<String, ListQueue<double>> _hist = {};
  final Map<String, int> _dipCount = {};
  final Map<String, DateTime> _dipStart = {};
  final Map<String, double> _dipPeak = {};
  final List<CrossingEvent> _pending = [];

  /// Feed one raw sample; returns the sample enriched with dip + baseline.
  LinkSample process(LinkSample raw) {
    final key = raw.linkKey;
    final hist = _hist.putIfAbsent(key, () => ListQueue<double>());

    final snr = raw.snr;
    if (snr != null) {
      hist.addLast(snr);
      while (hist.length > config.baselineWindow) {
        hist.removeFirst();
      }
    }

    final double baseline;
    if (hist.length >= config.minBaseline) {
      baseline = _median(hist.toList());
    } else if (snr != null) {
      baseline = snr; // warming up: not trusted yet
    } else {
      baseline = double.nan;
    }

    final dip =
        (snr != null && !baseline.isNaN) ? baseline - snr : 0.0;

    var count = _dipCount[key] ?? 0;
    if (dip >= config.dipThreshold) {
      if (count == 0) {
        _dipStart[key] = raw.timestamp;
        _dipPeak[key] = dip;
      } else {
        _dipPeak[key] = math.max(_dipPeak[key] ?? dip, dip);
      }
      count += 1;
      if (count == config.confirmPolls) {
        final start = _dipStart[key] ?? raw.timestamp;
        final peak = _dipPeak[key] ?? dip;
        _pending.add(CrossingEvent(
          timestamp: raw.timestamp,
          linkKey: key,
          dipDepth: peak,
          durationSecs:
              raw.timestamp.difference(start).inMilliseconds / 1000.0,
          sizeEstimate: _sizeEstimate(peak),
        ));
      }
    } else {
      count = 0;
      _dipStart.remove(key);
      _dipPeak.remove(key);
    }
    _dipCount[key] = count;

    return raw.copyWith(dip: dip, baseline: baseline);
  }

  /// Take and clear confirmed events.
  List<CrossingEvent> drainEvents() {
    final out = List<CrossingEvent>.from(_pending);
    _pending.clear();
    return out;
  }

  /// Crude heuristic size class from peak dip depth. Estimate only.
  static String _sizeEstimate(double dip) =>
      dip < 10 ? 'S' : dip < 20 ? 'M' : 'L';

  static double _median(List<double> xs) {
    xs.sort();
    final n = xs.length;
    if (n.isOdd) return xs[n ~/ 2];
    return (xs[n ~/ 2 - 1] + xs[n ~/ 2]) / 2;
  }
}
