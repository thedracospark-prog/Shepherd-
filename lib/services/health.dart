import '../models/link_sample.dart';
import '../utils/node_ids.dart';

/// How much of the perimeter the system can honestly vouch for.
enum Coverage {
  /// Session just began; no verdict yet. Never shown as CLEAR.
  starting,

  /// Every radio answering, every known link direction reporting.
  ok,

  /// Monitoring, but with gaps. CLEAR only holds for part of the field.
  degraded,

  /// Nothing is being monitored. CLEAR cannot be assumed.
  blind,
}

/// What kind of alert to raise.
enum AlertKind { detection, fault }

/// What the health check needs to know about one radio poller.
class DriverHealthInput {
  const DriverHealthInput({
    required this.driverId,
    required this.label,
    required this.pollIntervalSecs,
    this.lastPoll,
    this.error,
  });

  final String driverId;
  final String label;
  final double pollIntervalSecs;

  /// Last successful poll, or null if none yet this session.
  final DateTime? lastPoll;

  /// Non-null when the last poll failed or returned no links.
  final String? error;
}

class HealthReport {
  const HealthReport({
    required this.level,
    required this.reasons,
    required this.liveLinks,
    required this.expectedLinks,
  });

  final Coverage level;

  /// Operator-readable causes, most important first.
  final List<String> reasons;

  /// Link directions reporting fresh data right now.
  final int liveLinks;

  /// Link directions seen this session (what "all reporting" means).
  final int expectedLinks;

  /// True when the system is watching at least part of the field.
  bool get monitoring =>
      level == Coverage.ok || level == Coverage.degraded;
}

/// Decide how far a CLEAR verdict can be trusted.
///
/// Pure function: no clocks, no state. The point is that a failed or
/// partially failed system must never look the same as a quiet perimeter.
///
/// * [staleAfter] gives, per driver id, how old a sample or poll may be
///   before it stops counting as live.
/// * [rebaselines] are links that gave up holding their baseline after a
///   long continuous disturbance (see TripwireConfig.maxHoldPolls). The
///   detector now treats the new level as normal, so a person who stayed
///   put would silently read as CLEAR. For [persistentChangeWindow] after
///   such a reset the system reports DEGRADED instead.
HealthReport assessHealth({
  required DateTime now,
  required DateTime startedAt,
  required List<DriverHealthInput> drivers,
  required Map<String, LinkSample> lastByLink,
  required Duration Function(String driverId) staleAfter,
  Map<String, DateTime> rebaselines = const {},
  Duration persistentChangeWindow = const Duration(minutes: 10),
}) {
  final reasons = <String>[];

  if (drivers.isEmpty) {
    return const HealthReport(
      level: Coverage.blind,
      reasons: ['NO RADIOS ENABLED'],
      liveLinks: 0,
      expectedLinks: 0,
    );
  }

  var anyDriverBad = false;
  for (final d in drivers) {
    final limit = staleAfter(d.driverId);
    final lastPoll = d.lastPoll;
    final age = now.difference(lastPoll ?? startedAt);

    if (lastPoll == null && d.error == null && age <= limit) {
      continue; // first poll still in flight
    }
    if (d.error != null) {
      anyDriverBad = true;
      reasons.add('${d.label}: ${_short(d.error!)}');
    } else if (age > limit) {
      anyDriverBad = true;
      reasons.add(lastPoll == null
          ? '${d.label}: NO RESPONSE since start (${age.inSeconds}s)'
          : '${d.label}: NOT RESPONDING (${age.inSeconds}s since last data)');
    }
  }

  var live = 0;
  lastByLink.forEach((_, s) {
    if (now.difference(s.timestamp) <= staleAfter(driverOf(s.fromNode))) {
      live += 1;
    }
  });
  final expected = lastByLink.length;

  if (expected == 0) {
    return HealthReport(
      level: anyDriverBad ? Coverage.blind : Coverage.starting,
      reasons: reasons,
      liveLinks: 0,
      expectedLinks: 0,
    );
  }
  if (live == 0) {
    reasons.insert(0, 'NO LIVE LINKS (0 of $expected reporting)');
    return HealthReport(
      level: Coverage.blind,
      reasons: reasons,
      liveLinks: 0,
      expectedLinks: expected,
    );
  }

  final missing = expected - live;
  if (missing > 0) {
    reasons.add('$missing of $expected link directions not reporting');
  }

  final recent = [
    for (final e in rebaselines.entries)
      if (now.difference(e.value) <= persistentChangeWindow) e,
  ]..sort((a, b) => b.value.compareTo(a.value));
  for (final e in recent.take(3)) {
    reasons.add('${e.key}: baseline reset after prolonged disturbance '
        '(${now.difference(e.value).inSeconds}s ago) — presence may persist');
  }
  if (recent.length > 3) {
    reasons.add('+${recent.length - 3} more links reset');
  }

  final degraded = anyDriverBad || missing > 0 || recent.isNotEmpty;
  return HealthReport(
    level: degraded ? Coverage.degraded : Coverage.ok,
    reasons: reasons,
    liveLinks: live,
    expectedLinks: expected,
  );
}

String _short(String s) => s.length <= 90 ? s : '${s.substring(0, 87)}…';
