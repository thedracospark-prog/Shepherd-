/// Embedded disturbance classifier — the app's small, task-oriented AI.
///
/// This is a tiny trained neural network (10 features -> 24 -> 12 -> 4
/// classes), NOT an LLM. It classifies one CLOSED radio disturbance
/// event as PASSING / LINGERING / INTERFERENCE / FAULT.
///
/// Honest-scope rules, enforced by design:
/// - Detection stays DETERMINISTIC (the tripwire). This model only
///   classifies what the tripwire already found — it can never suppress
///   an alert.
/// - It was trained on SYNTHETIC disturbance models, so its labels are
///   heuristics shown as estimates with confidence, never identifications.
/// - Inference runs on the shared [TinyMlp] kernel: pure Dart math,
///   no native plugin. test/ai_golden.json checks the kernel
///   numerically against the Python trainer.
library;

import 'dart:math';

import 'package:flutter/services.dart';

import 'tiny_ml.dart';

/// Feature order MUST match tools/train_disturbance_clf.py.
List<double> extractDisturbanceFeatures({
  required List<double> dips,
  required double threshold,
  required double durationSecs,
  required int simulLinks,
  required bool crossDriver,
  required int meshLinks,
}) {
  final n = dips.length;
  var peak = dips[0];
  var ipeak = 0;
  var sum = 0.0;
  var above = 0.0;
  for (var i = 0; i < n; i++) {
    final d = dips[i];
    if (d > peak) {
      peak = d;
      ipeak = i;
    }
    sum += d;
    if (d >= threshold) above += 1.0;
  }
  final mean = sum / n;
  var v = 0.0;
  for (final d in dips) {
    v += (d - mean) * (d - mean);
  }
  final std = sqrt(v / n);
  final preN = max(2, n ~/ 5);
  var preSum = 0.0;
  for (var i = 0; i < preN; i++) {
    preSum += dips[i];
  }
  final preMean = preSum / preN;
  var preV = 0.0;
  for (var i = 0; i < preN; i++) {
    preV += (dips[i] - preMean) * (dips[i] - preMean);
  }
  final preStd = sqrt(preV / preN);
  return [
    peak / threshold,
    log(durationSecs + 1.0) / ln10,
    ipeak / max(n - 1, 1),
    std / (mean + 1e-6),
    log(simulLinks + 1.0) / ln10,
    crossDriver ? 1.0 : 0.0,
    above / n,
    (peak - dips[n - 1]) / (peak + 1e-6),
    preStd / threshold,
    log(meshLinks + 1.0) / ln10,
  ];
}

class DisturbanceClassifier {
  DisturbanceClassifier._(this._mlp);

  final TinyMlp _mlp;

  static DisturbanceClassifier? _instance;

  /// Loads the bundled model once; null when the asset is missing.
  static Future<DisturbanceClassifier?> load() async {
    if (_instance != null) return _instance;
    try {
      final raw =
          await rootBundle.loadString('assets/models/disturbance_clf.json');
      _instance = DisturbanceClassifier.fromJson(
          TinyMlp.decodeJson(raw));
      return _instance;
    } catch (_) {
      return null;
    }
  }

  /// Build from a decoded model document (the format written by
  /// tools/train_disturbance_clf.py). Public for tests.
  factory DisturbanceClassifier.fromJson(Map<String, dynamic> j) =>
      DisturbanceClassifier._(TinyMlp.fromJson(j));

  Map<String, double> predictProbs(List<double> features) =>
      _mlp.predictProbs(features);

  /// (top label, confidence)
  (String, double) classify(List<double> features) =>
      _mlp.classify(features);

  double get holdoutAccuracy => _mlp.holdoutAccuracy;
}
