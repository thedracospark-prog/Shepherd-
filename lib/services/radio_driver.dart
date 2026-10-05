/// Multi-radio driver framework.
///
/// Every supported radio family implements [RadioDriver]: it polls its
/// hardware and emits plain [LinkSample]s. Everything downstream —
/// tripwire, tracker, dashboard, map — is radio-agnostic and consumes
/// only LinkSamples.
///
/// Namespacing: each driver prefixes its node IDs (`silvus:90550`),
/// so link keys (`silvus:90550 → silvus:90551`) can never collide
/// across vendors, and per-link tripwire baselines stay independent.
library;

import '../models/link_sample.dart';
import '../models/tracking.dart';
import 'silvus_api.dart';
import 'simulated.dart';

/// One configured radio network.
class RadioConfig {
  RadioConfig({
    required this.driverId,
    required this.address,
    this.label = '',
    this.enabled = true,
    this.pollInterval = 0.25,
  });

  /// 'silvus' | 'mpu5' | 'harris' | 'simulated'.
  final String driverId;

  /// IP/host for network drivers; '' for simulated.
  final String address;
  final String label;
  bool enabled;
  double pollInterval;

  String get displayLabel =>
      label.isEmpty ? '${driverId.toUpperCase()} · $address' : label;

  Map<String, dynamic> toJson() => {
        'driverId': driverId,
        'address': address,
        'label': label,
        'enabled': enabled,
        'pollInterval': pollInterval,
      };

  factory RadioConfig.fromJson(Map<String, dynamic> j) => RadioConfig(
        driverId: '${j['driverId'] ?? 'silvus'}',
        address: '${j['address'] ?? ''}',
        label: '${j['label'] ?? ''}',
        enabled: j['enabled'] != false,
        pollInterval:
            (double.tryParse('${j['pollInterval']}') ?? 0.25).clamp(0.1, 60),
      );
}

/// Live status of one driver instance, for the dashboard radio card.
class DriverStatus {
  DriverStatus({
    required this.driverId,
    required this.label,
    required this.enabled,
    this.lastPoll,
    this.linkCount = 0,
    this.error,
  });

  final String driverId;
  final String label;
  final bool enabled;
  DateTime? lastPoll;
  int linkCount;
  String? error;
}

/// The contract every radio family implements.
abstract class RadioDriver {
  /// 'silvus' | 'mpu5' | 'harris' | 'simulated'.
  String get driverId;

  /// Human label, e.g. 'SILVUS'.
  String get label;

  /// True when this driver can actually run (telemetry implemented).
  bool get isImplemented;

  /// One poll: raw link samples with driver-namespaced node IDs.
  Future<List<LinkSample>> poll();

  /// Quick reachability check for discovery / setup validation.
  Future<bool> probe();

  void dispose() {}
}

/// Silvus StreamCaster driver: HTTP JSON-RPC `streamscape_data`.
class SilvusDriver extends RadioDriver {
  SilvusDriver({required String ip}) : _api = SilvusApi(ip: ip);

  final SilvusApi _api;

  @override
  String get driverId => 'silvus';

  @override
  String get label => 'SILVUS';

  @override
  bool get isImplemented => true;

  @override
  Future<List<LinkSample>> poll() async {
    final snap = await _api.fetchSnapshot();
    if (snap == null) return [];
    // Namespace node IDs so vendors can never collide.
    return [
      for (final l in snap.links)
        LinkSample(
          timestamp: l.timestamp,
          fromNode: 'silvus:${l.fromNode}',
          toNode: 'silvus:${l.toNode}',
          snr: l.snr,
          mcs: l.mcs,
          pcns: l.pcns,
          noiseFrom: l.noiseFrom,
          noiseTo: l.noiseTo,
        ),
    ];
  }

  @override
  Future<bool> probe() => _api.probe();
}

/// Simulated mesh driver: wraps [SimulatedSource] so simulated mode is
/// just another driver. Node IDs are namespaced `sim:...`.
class SimulatedDriver extends RadioDriver {
  SimulatedDriver({this.pollInterval = 0.25}) : _sim = SimulatedSource();

  final SimulatedSource _sim;
  final double pollInterval;

  @override
  String get driverId => 'sim';

  @override
  String get label => 'SIMULATED';

  @override
  bool get isImplemented => true;

  @override
  Future<List<LinkSample>> poll() async {
    final raw = _sim.tick(dt: pollInterval);
    return [
      for (final l in raw)
        LinkSample(
          timestamp: l.timestamp,
          fromNode: 'sim:${l.fromNode}',
          toNode: 'sim:${l.toNode}',
          snr: l.snr,
          mcs: l.mcs,
          pcns: l.pcns,
          noiseFrom: l.noiseFrom,
          noiseTo: l.noiseTo,
        ),
    ];
  }

  @override
  Future<bool> probe() async => true;

  /// Canonical sim layout with namespaced keys, matching [poll] output.
  Map<String, NodePosition> get nodeLayout => {
        for (final e in _sim.nodeLayout.entries)
          'sim:${e.key}': NodePosition(
            nodeId: 'sim:${e.key}',
            x: e.value.x,
            y: e.value.y,
            height: e.value.height,
            antenna: e.value.antenna,
          ),
      };
}

/// MPU5 (Persistent Systems Wave Relay) — telemetry not yet implemented.
/// Wave Relay does not mesh with Silvus MN-MIMO; it would be a separate
/// driver emitting LinkSamples once its management API is mapped.
class Mpu5Driver extends RadioDriver {
  @override
  String get driverId => 'mpu5';

  @override
  String get label => 'MPU5';

  @override
  bool get isImplemented => false;

  @override
  Future<List<LinkSample>> poll() =>
      throw UnimplementedError('MPU5 telemetry not yet implemented');

  @override
  Future<bool> probe() async => false;
}

/// L3Harris Falcon family — telemetry not yet implemented.
/// Needs a pollable per-neighbor signal interface (SNMP MIB or similar);
/// an SNMP probe will determine what is actually exposed.
class L3HarrisDriver extends RadioDriver {
  @override
  String get driverId => 'harris';

  @override
  String get label => 'L3HARRIS';

  @override
  bool get isImplemented => false;

  @override
  Future<List<LinkSample>> poll() =>
      throw UnimplementedError('L3Harris telemetry not yet implemented');

  @override
  Future<bool> probe() async => false;
}

/// Build a driver from a config. Throws for unimplemented families.
RadioDriver driverFor(RadioConfig config) {
  switch (config.driverId) {
    case 'silvus':
      return SilvusDriver(ip: config.address);
    case 'mpu5':
      return Mpu5Driver();
    case 'harris':
      return L3HarrisDriver();
    default:
      throw ArgumentError('Unknown driver: ${config.driverId}');
  }
}

/// Driver types the user can pick in the radio manager.
const List<({String id, String label, bool implemented})> driverTypes = [
  (id: 'silvus', label: 'SILVUS', implemented: true),
  (id: 'mpu5', label: 'MPU5 (Wave Relay)', implemented: false),
  (id: 'harris', label: 'L3HARRIS', implemented: false),
];
