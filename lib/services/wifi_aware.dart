/// Wi-Fi Aware (NAN) peer discovery — EXPERIMENTAL / UNVERIFIED.
///
/// Dart side of the wifi_aware method channel implemented in
/// MainActivity.kt. That Kotlin was written without an Android SDK on the
/// build machine and has never been compiled; the UI marks this panel
/// EXPERIMENTAL and everything fails soft.
///
/// Honest scope: Wi-Fi Aware is *cooperative* discovery — it only sees
/// devices publishing/subscribing the same service name. It does NOT
/// passively detect strangers' phones. BLE scanning remains the passive
/// nearby-device sensor.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class WifiAwareService {
  static const _method = MethodChannel('rf_sentry/wifi_aware');
  static const _events = EventChannel('rf_sentry/wifi_aware_events');

  /// null = not checked yet.
  bool? available;
  String? error;
  bool discovering = false;

  /// Peer IDs seen during discovery (opaque labels, not identities).
  final List<String> peers = [];

  StreamSubscription? _sub;
  void Function()? onUpdate;

  Future<void> checkAvailable() async {
    if (!Platform.isAndroid) {
      available = false;
      return;
    }
    try {
      available = await _method.invokeMethod<bool>('isAwareAvailable');
    } catch (e) {
      available = false;
      error = 'Aware check failed: $e';
    }
    onUpdate?.call();
  }

  Future<void> startDiscovery({String serviceName = 'shepherd'}) async {
    if (available != true || discovering) return;
    discovering = true;
    error = null;
    onUpdate?.call();
    try {
      final ok = await _method.invokeMethod<bool>(
          'startDiscovery', {'serviceName': serviceName});
      if (ok != true) {
        error = 'Could not start Aware discovery.';
        discovering = false;
      } else {
        _sub = _events.receiveBroadcastStream().listen((e) {
          if (e is Map && e['peerId'] is String) {
            final id = e['peerId'] as String;
            if (!peers.contains(id)) peers.add(id);
            onUpdate?.call();
          }
        }, onError: (_) {});
      }
    } catch (e) {
      error = 'Discovery failed: $e';
      discovering = false;
    }
    onUpdate?.call();
  }

  Future<void> stopDiscovery() async {
    try {
      await _method.invokeMethod('stopDiscovery');
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    discovering = false;
    onUpdate?.call();
  }
}
