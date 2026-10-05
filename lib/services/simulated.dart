import 'dart:math' as math;

import '../models/link_sample.dart';
import '../models/tracking.dart';

/// Synthetic 4-node mesh for hardware-free testing of the tracking engine.
///
/// Three ground nodes plus one 15 m mast node. A single target wanders the
/// field at varying altitude; each link's dip is a Gaussian falloff of the
/// target's 3D distance to that link's segment. Output flows through the
/// same [Tripwire] + [Tracker] pipeline as real telemetry, so the UI
/// behaves identically in both modes.
class SimulatedSource {
  SimulatedSource({int seed = 7}) : _rng = math.Random(seed);

  final math.Random _rng;
  double _t = 0.0;

  /// Canonical demo layout. AppState uses this instead of auto-layout
  /// while simulated mode is on.
  Map<String, NodePosition> get nodeLayout => {
        'SIM-A': NodePosition(nodeId: 'SIM-A', x: -30, y: -30, height: 0),
        'SIM-B': NodePosition(nodeId: 'SIM-B', x: 30, y: -30, height: 0),
        'SIM-C': NodePosition(nodeId: 'SIM-C', x: 30, y: 30, height: 0),
        'SIM-D': NodePosition(nodeId: 'SIM-D', x: -30, y: 30, height: 15),
      };

  /// Advance the simulation by [dt] seconds and return raw link samples.
  List<LinkSample> tick({double dt = 0.5}) {
    _t += dt;
    final nodes = nodeLayout;
    final ids = nodes.keys.toList();

    // Wandering target, altitude varying 2..14 m.
    final tx = 42 * math.sin(_t / 16);
    final ty = 42 * math.sin(_t / 23 + 1.3);
    final tz = 8 + 6 * math.sin(_t / 31 + 0.5);

    final out = <LinkSample>[];
    for (var i = 0; i < ids.length; i++) {
      for (var j = 0; j < ids.length; j++) {
        if (i == j) continue;
        final a = nodes[ids[i]]!;
        final b = nodes[ids[j]]!;
        final d = _distToSegment3D(tx, ty, tz, a, b);
        final targetDip = 26 * math.exp(-math.pow(d / 11, 2));
        out.add(_sample(ids[i], ids[j], targetDip));
      }
    }
    return out;
  }

  LinkSample _sample(String from, String to, double targetDip) {
    final phase = (from.hashCode ^ to.hashCode) & 0xFF;
    final noise = (_rng.nextDouble() +
            _rng.nextDouble() +
            _rng.nextDouble() -
            1.5) *
        2.0;
    final base = 90 + 4 * math.sin(_t / 9 + phase);
    final jitter = (_rng.nextDouble() - 0.5) * 1.5;
    final snr = base + noise * 1.2 - targetDip + jitter;
    final now = DateTime.now();
    return LinkSample(
      timestamp: now,
      fromNode: from,
      toNode: to,
      snr: snr,
      mcs: 8 + _rng.nextInt(3),
      pcns: [snr - 70 + noise, snr - 71 - noise, -114.0, -114.0],
      noiseFrom: -72.0,
      noiseTo: -74.0,
    );
  }

  /// 3D distance from point P to segment AB (node heights included).
  static double _distToSegment3D(
      double px, double py, double pz, NodePosition a, NodePosition b) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final abz = b.height - a.height;
    final apx = px - a.x;
    final apy = py - a.y;
    final apz = pz - a.height;
    final len2 = abx * abx + aby * aby + abz * abz;
    var t = len2 == 0 ? 0.0 : (apx * abx + apy * aby + apz * abz) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = a.x + abx * t - px;
    final cy = a.y + aby * t - py;
    final cz = a.height + abz * t - pz;
    return math.sqrt(cx * cx + cy * cy + cz * cz);
  }
}
