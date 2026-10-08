/// Track-stitching specialist — the app's second tiny embedded model.
///
/// Question it answers: a disturbance just went quiet on radio A and a
/// fresh one lit up on radio B — same physical mover, or two unrelated
/// events?
///
/// This is the learned follow-up to the deterministic cross-driver
/// tracker (grid search + time/space continuity), which always runs
/// first. The stitcher only scores ambiguous handoffs, and its verdict
/// is shown as an estimate with confidence, never as fact.
///
/// Runtime design:
/// - `observe()` watches each fused update, grouping disturbed links by
///   driver and maintaining one open "detection" per driver (centroid of
///   disturbed link midpoints, first/last time, peak dip, link count).
///   When a driver's links go quiet, its detection closes into a short
///   history.
/// - `checkHandoff()` fires when a driver has a NEW detection (opened
///   within [newWindow]) and another driver closed one within
///   [memoryWindow]: it scores every candidate pair with the tiny MLP
///   and returns the best above [stitchThreshold.
///
/// Trained on synthetic two-mesh crossing scenarios
/// (tools/train_stitcher.py); inference runs on the shared [TinyMlp]
/// kernel, verified by test/stitcher_golden.json.
library;

import 'dart:math';

import 'package:flutter/services.dart';

import '../models/link_sample.dart';
import '../models/tracking.dart';
import '../utils/node_ids.dart';
import 'tiny_ml.dart';

/// Feature order MUST match tools/train_stitcher.py.
List<double> extractStitchFeatures(DriverDetection a, DriverDetection b) {
  final gapSecs =
      b.tFirst.difference(a.tLast).inMilliseconds / 1000.0;
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final dist = sqrt(dx * dx + dy * dy);
  final dtFirst = max(
      b.tFirst.difference(a.tFirst).inMilliseconds / 1000.0, 1.0);
  final implied = dist / dtFirst;
  final abAng = atan2(dy, dx);
  // Runtime heading = direction the A detection's centroid drifted.
  // Neutral (0) when it barely moved — "no directional evidence".
  final drift = sqrt(pow(a.x - a.firstX, 2) + pow(a.y - a.firstY, 2));
  final dcos = drift < 2.0
      ? 0.0
      : cos(abAng - atan2(a.y - a.firstY, a.x - a.firstX));
  final overlap =
      (a.tFirst.isBefore(b.tLast) && b.tFirst.isBefore(a.tLast))
          ? 1.0
          : 0.0;
  return [
    gapSecs / 60.0,
    log(dist + 1.0) / ln10,
    log(implied + 0.1) / ln10,
    exp(-pow(log(implied / 4.0 + 1e-9), 2) / 2.0),
    1.0 - (a.peakDip - b.peakDip).abs() / (a.peakDip + b.peakDip + 1e-9),
    overlap,
    log(a.nLinks + b.nLinks) / ln10,
    dcos,
  ];
}

/// One driver's currently-open (or recently closed) disturbance.
class DriverDetection {
  DriverDetection({
    required this.driverId,
    required this.tFirst,
    required this.tLast,
    required this.x,
    required this.y,
    required this.firstX,
    required this.firstY,
    required this.peakDip,
    required this.nLinks,
  });

  final String driverId;
  final DateTime tFirst;
  DateTime tLast;
  double x, y;
  final double firstX, firstY;
  double peakDip;
  int nLinks;
}

class TrackStitcher {
  TrackStitcher._(this._mlp);

  final TinyMlp? _mlp;

  /// Detections newer than this after closing are still stitchable.
  static const memoryWindow = Duration(minutes: 4);

  /// A detection counts as "new" (stitch candidate target) within this.
  static const newWindow = Duration(seconds: 45);

  /// Minimum P(same mover) to report a stitch.
  static const stitchThreshold = 0.65;

  static TrackStitcher? _instance;

  static Future<TrackStitcher> load() async {
    if (_instance != null) return _instance!;
    TinyMlp? mlp;
    try {
      final raw = await rootBundle
          .loadString('assets/models/track_stitcher.json');
      mlp = TinyMlp.fromJson(TinyMlp.decodeJson(raw));
    } catch (_) {
      mlp = null;
    }
    _instance = TrackStitcher._(mlp);
    return _instance!;
  }

  /// Test/placeholder constructor without a model (scoring disabled).
  TrackStitcher.withoutModel() : _mlp = null;

  bool get hasModel => _mlp != null;

  final Map<String, DriverDetection> _open = {};
  final List<DriverDetection> _closed = [];

  /// Feed one fused update. Disturbed links are grouped by driver; each
  /// driver keeps a single open detection that tracks the disturbed
  /// centroid until its links go quiet.
  void observe({
    required DateTime now,
    required List<LinkSample> samples,
    required Map<String, NodePosition> nodes,
    required double dipThreshold,
  }) {
    final cx = <String, double>{};
    final cy = <String, double>{};
    final peak = <String, double>{};
    final count = <String, int>{};
    for (final s in samples) {
      if (!s.isDisturbed(dipThreshold)) continue;
      final a = nodes[s.fromNode];
      final b = nodes[s.toNode];
      if (a == null || b == null) continue;
      final d = driverOf(s.fromNode);
      final mx = (a.x + b.x) / 2;
      final my = (a.y + b.y) / 2;
      final n = (count[d] ?? 0) + 1;
      count[d] = n;
      cx[d] = (cx[d] ?? 0) + (mx - (cx[d] ?? 0)) / n;
      cy[d] = (cy[d] ?? 0) + (my - (cy[d] ?? 0)) / n;
      peak[d] = max(peak[d] ?? 0.0, s.dip);
    }
    for (final d in count.keys) {
      final open = _open[d];
      if (open == null) {
        _open[d] = DriverDetection(
          driverId: d,
          tFirst: now,
          tLast: now,
          x: cx[d]!,
          y: cy[d]!,
          firstX: cx[d]!,
          firstY: cy[d]!,
          peakDip: peak[d]!,
          nLinks: count[d]!,
        );
      } else {
        open.tLast = now;
        open.x = cx[d]!;
        open.y = cy[d]!;
        open.peakDip = max(open.peakDip, peak[d]!);
        open.nLinks = max(open.nLinks, count[d]!);
      }
    }
    // Close detections whose drivers went quiet.
    for (final d in _open.keys.toList()) {
      if (!count.containsKey(d)) {
        _closed.add(_open.remove(d)!);
        if (_closed.length > 30) _closed.removeAt(0);
      }
    }
    _closed.removeWhere((c) => now.difference(c.tLast) > memoryWindow);
  }

  /// P(same mover) for a closed-then-new detection pair.
  double sameMoverProb(DriverDetection a, DriverDetection b) {
    final mlp = _mlp;
    if (mlp == null) return 0.0;
    final probs = mlp.predictProbs(extractStitchFeatures(a, b));
    return probs['1'] ?? 0.0;
  }

  /// If [activeDriver] has a NEW open detection, score it against
  /// recently closed detections on other drivers. Returns the best
  /// (fromDriver, confidence) at/above threshold, else null.
  ({String fromDriver, double confidence})? checkHandoff({
    required DateTime now,
    required String activeDriver,
  }) {
    final mlp = _mlp;
    if (mlp == null) return null;
    final cur = _open[activeDriver];
    if (cur == null) return null;
    if (now.difference(cur.tFirst) > newWindow) return null;
    var bestConf = 0.0;
    String? bestFrom;
    for (final a in _closed) {
      if (a.driverId == activeDriver) continue;
      if (now.difference(a.tLast) > memoryWindow) continue;
      final p = sameMoverProb(a, cur);
      if (p > bestConf) {
        bestConf = p;
        bestFrom = a.driverId;
      }
    }
    if (bestFrom != null && bestConf >= stitchThreshold) {
      return (fromDriver: bestFrom, confidence: bestConf);
    }
    return null;
  }

  /// For tests: inspect open/closed state.
  Map<String, DriverDetection> get openForTest => _open;
  List<DriverDetection> get closedForTest => _closed;
}
