import 'dart:collection';
import 'dart:math' as math;

import '../models/link_sample.dart';

/// Tunables for the tripwire detector. Mirrors silvus_tripwire.py defaults,
/// plus the adaptive-threshold and baseline-hold options.
class TripwireConfig {
  const TripwireConfig({
    this.baselineWindow = 120,
    this.minBaseline = 10,
    this.dipThreshold = 6.0,
    this.confirmPolls = 2,
    this.adaptive = true,
    this.madK = 5.0,
    this.adaptiveFloorFrac = 0.67,
    this.adaptiveCapMult = 3.0,
    this.maxHoldPolls = 480,
  });

  /// Rolling history kept per link direction (in polls).
  final int baselineWindow;

  /// Polls of history before the baseline is trusted.
  final int minBaseline;

  /// Reference dip depth (radio units) that counts as a possible crossing.
  /// With [adaptive] on, each link's own threshold is derived from its
  /// noise and kept within [adaptiveFloorFrac]..[adaptiveCapMult] times
  /// this value; with [adaptive] off it is used as-is on every link.
  final double dipThreshold;

  /// Consecutive polls above threshold required to confirm an event.
  /// Lower = faster alerts, higher = fewer false alarms.
  final int confirmPolls;

  /// Derive each link's threshold from its own noise (robust spread of
  /// its baseline window) instead of one fixed number for every link.
  /// Noisy links get a higher bar, quiet links a lower one.
  final bool adaptive;

  /// Adaptive threshold = madK × robust sigma (1.4826 × MAD) of the link's
  /// baseline window, then clamped (see below).
  final double madK;

  /// Lower clamp for the adaptive threshold, as a fraction of
  /// [dipThreshold]. Stops a perfectly flat (quantized) link from
  /// triggering on tiny wiggles.
  final double adaptiveFloorFrac;

  /// Upper clamp for the adaptive threshold, as a multiple of
  /// [dipThreshold]. Stops one very noisy link from going deaf.
  final double adaptiveCapMult;

  /// Longest a link's baseline is frozen during a continuous disturbance,
  /// in polls. Past this the new level is treated as the new normal
  /// (a node moved, lasting interference) and the link re-baselines.
  /// At the default 0.25 s poll interval, 480 polls = 2 minutes.
  final int maxHoldPolls;
}

/// Rolling-median baseline dip detector, one instance per link direction.
///
/// For each poll: baseline = median of the link's recent SNR history
/// (not including the current sample); dip = baseline − snr. A dip at/above
/// the link's threshold for [TripwireConfig.confirmPolls] consecutive polls
/// emits a [CrossingEvent] carrying the disturbance's peak depth and
/// duration.
///
/// Baseline hold: samples that are themselves disturbed are NOT added to
/// the history. Otherwise a target that lingers drags the median down and
/// the detector "heals" around it while it is still there. The hold is
/// bounded by [TripwireConfig.maxHoldPolls] so a genuine, lasting change
/// of level re-baselines instead of alarming forever.
///
/// All magnitudes are estimates in radio-internal units.
class Tripwire {
  Tripwire({TripwireConfig? config})
      : config = config ?? const TripwireConfig();

  final TripwireConfig config;

  final Map<String, ListQueue<double>> _hist = {};
  final Map<String, int> _dipCount = {};
  final Map<String, DateTime> _dipStart = {};
  final Map<String, double> _dipPeak = {};
  final Map<String, int> _held = {};
  final List<CrossingEvent> _pending = [];
  final Map<String, DateTime> _rebaselinedAt = {};
  int _rebaselines = 0;

  /// How many times a link gave up holding its baseline and re-baselined
  /// (lasting level change). Diagnostic.
  int get rebaselineCount => _rebaselines;

  /// When each link last gave up holding its baseline. After a reset the
  /// detector treats the new level as normal, so anything still standing
  /// there is invisible; callers should surface this, not show CLEAR.
  Map<String, DateTime> get rebaselinedAt => Map.unmodifiable(_rebaselinedAt);

  /// Feed one raw sample; returns the sample enriched with dip, baseline
  /// and this link's threshold.
  LinkSample process(LinkSample raw) {
    final key = raw.linkKey;
    final hist = _hist.putIfAbsent(key, () => ListQueue<double>());
    final snr = raw.snr;

    final trusted = hist.length >= config.minBaseline;
    var baseline = double.nan;
    var threshold = config.dipThreshold;
    var dip = 0.0;

    if (trusted) {
      final sorted = hist.toList()..sort();
      baseline = _medianSorted(sorted);
      threshold = _thresholdFor(sorted, baseline);
      if (snr != null) dip = baseline - snr;
    } else if (snr != null) {
      baseline = snr; // warming up: not trusted yet
    }

    final disturbed = trusted && snr != null && dip >= threshold;

    // History update. Only undisturbed samples extend the baseline.
    if (snr != null) {
      if (!trusted || !disturbed) {
        hist.addLast(snr);
        while (hist.length > config.baselineWindow) {
          hist.removeFirst();
        }
        _held[key] = 0;
      } else {
        final held = (_held[key] ?? 0) + 1;
        _held[key] = held;
        if (held > config.maxHoldPolls) {
          // The disturbance never ended: treat the new level as normal.
          hist
            ..clear()
            ..addLast(snr);
          _held[key] = 0;
          _resetEpisode(key);
          _rebaselines += 1;
          _rebaselinedAt[key] = raw.timestamp;
          return raw.copyWith(
            dip: 0.0,
            baseline: snr,
            threshold: config.dipThreshold,
          );
        }
      }
    }

    var count = _dipCount[key] ?? 0;
    if (disturbed) {
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
      _dipCount[key] = count;
    } else {
      _resetEpisode(key);
    }

    return raw.copyWith(dip: dip, baseline: baseline, threshold: threshold);
  }

  /// Take and clear confirmed events.
  List<CrossingEvent> drainEvents() {
    final out = List<CrossingEvent>.from(_pending);
    _pending.clear();
    return out;
  }

  void _resetEpisode(String key) {
    _dipCount[key] = 0;
    _dipStart.remove(key);
    _dipPeak.remove(key);
  }

  /// This link's detection threshold given its sorted baseline window.
  double _thresholdFor(List<double> sorted, double median) {
    final base = config.dipThreshold;
    if (!config.adaptive) return base;
    final devs = [for (final x in sorted) (x - median).abs()]..sort();
    final sigma = 1.4826 * _medianSorted(devs);
    final lo = base * config.adaptiveFloorFrac;
    final hi = base * config.adaptiveCapMult;
    return math.min(math.max(config.madK * sigma, lo), hi);
  }

  /// Crude heuristic size class from peak dip depth. Estimate only.
  static String _sizeEstimate(double dip) =>
      dip < 10 ? 'S' : dip < 20 ? 'M' : 'L';

  /// Median of an already-sorted, non-empty list.
  static double _medianSorted(List<double> xs) {
    final n = xs.length;
    if (n.isOdd) return xs[n ~/ 2];
    return (xs[n ~/ 2 - 1] + xs[n ~/ 2]) / 2;
  }
}
