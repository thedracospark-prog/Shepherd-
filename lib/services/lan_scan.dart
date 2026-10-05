import 'dart:async';
import 'dart:io';

/// LAN device discovery: who is on the local subnet right now.
///
/// Honest scope: a normal WiFi adapter cannot see *which access point* a
/// device is associated with — APs don't broadcast client lists and
/// `netsh` has no such command. What the host PC *can* do is an ARP
/// sweep of its own subnet: every reachable device answers ARP, so we
/// get IP + MAC for everything on the local network. On a home or
/// small-site network that is effectively "the devices on your APs".
///
/// Windows-first (arp/ipconfig formats); the Linux `arp -a` format is
/// parsed too for future Android use.

/// One device found on the local subnet.
class LanDevice {
  LanDevice({
    required this.ip,
    required this.mac,
    this.isSelf = false,
    this.isGateway = false,
  });

  final String ip;
  final String mac;
  final bool isSelf;
  final bool isGateway;
}

/// Parse `arp -a` output into devices. Handles the Windows table format
/// and the Linux `? (ip) at mac` format. Multicast and broadcast entries
/// are dropped — they are not devices.
List<LanDevice> parseArpTable(String output, {String? selfIp}) {
  final devices = <LanDevice>[];
  final seen = <String>{};

  void add(String ip, String mac) {
    mac = mac.toLowerCase().replaceAll('-', ':');
    if (mac == 'ff:ff:ff:ff:ff:ff') return; // broadcast
    if (mac.startsWith('01:00:5e')) return; // IPv4 multicast
    if (mac.startsWith('33:33:')) return; // IPv6 multicast
    if (!seen.add(ip)) return;
    devices.add(LanDevice(
      ip: ip,
      mac: mac,
      isSelf: selfIp != null && ip == selfIp,
    ));
  }

  // Windows: "  192.168.1.1           aa-bb-cc-dd-ee-ff     dynamic"
  final winRe = RegExp(
    r'^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F]{2}(?:-[0-9a-fA-F]{2}){5})\s+(?:dynamic|static)',
    multiLine: true,
  );
  for (final m in winRe.allMatches(output)) {
    add(m.group(1)!, m.group(2)!);
  }

  // Linux: "? (192.168.1.1) at aa:bb:cc:dd:ee:ff [ether] on wlan0"
  // "(incomplete)" entries have no MAC and are skipped.
  final linuxRe = RegExp(
    r'\((\d{1,3}(?:\.\d{1,3}){3})\)\s+at\s+([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})',
  );
  for (final m in linuxRe.allMatches(output)) {
    add(m.group(1)!, m.group(2)!);
  }

  devices.sort((a, b) => _ipKey(a.ip).compareTo(_ipKey(b.ip)));
  return devices;
}

int _ipKey(String ip) {
  var key = 0;
  for (final part in ip.split('.')) {
    key = key * 256 + (int.tryParse(part) ?? 0);
  }
  return key;
}

/// Result of one subnet sweep.
class LanScanResult {
  LanScanResult({
    required this.devices,
    required this.subnet,
    required this.at,
  });

  final List<LanDevice> devices;
  final String subnet;
  final DateTime at;
}

class LanScanner {
  /// Ping-sweep the local /24, then read the ARP table.
  ///
  /// The /24 assumption is stated in the UI; multi-subnet or carved
  /// networks will show only the interface's own /24.
  static Future<LanScanResult> scan() async {
    final selfIp = await _localIpv4();
    if (selfIp == null) {
      throw const LanScanException(
          'NO LOCAL IPV4 ADDRESS FOUND — ARE YOU ON A NETWORK?');
    }
    final prefix = selfIp.split('.').sublist(0, 3).join('.');
    final subnet = '$prefix.0/24';

    // Parallel ping sweep in batches so quiet hosts populate ARP.
    // One ping each, short timeout — a manual scan of a /24 takes
    // a few seconds.
    const batchSize = 48;
    final targets = [
      for (var i = 1; i < 255; i++) '$prefix.$i',
    ];
    for (var b = 0; b < targets.length; b += batchSize) {
      final batch = targets.sublist(
          b,
          (b + batchSize).clamp(0, targets.length));
      await Future.wait(batch.map(_pingOnce));
    }

    final arpRes = await Process.run('arp', ['-a']);
    if (arpRes.exitCode != 0) {
      throw const LanScanException(
          'COULD NOT READ THE ARP TABLE.');
    }
    final devices =
        parseArpTable(arpRes.stdout as String, selfIp: selfIp);

    // Flag the default gateway (Windows: ipconfig).
    final gateway = await _defaultGateway();
    if (gateway != null) {
      for (final d in devices) {
        if (d.ip == gateway) {
          devices[devices.indexOf(d)] = LanDevice(
            ip: d.ip,
            mac: d.mac,
            isSelf: d.isSelf,
            isGateway: true,
          );
        }
      }
    }

    return LanScanResult(
      devices: devices,
      subnet: subnet,
      at: DateTime.now(),
    );
  }

  static Future<String?> _localIpv4() async {
    try {
      final ifs = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _pingOnce(String ip) async {
    try {
      final args = Platform.isWindows
          ? ['-n', '1', '-w', '250', ip]
          : ['-c', '1', '-W', '1', ip];
      await Process.run('ping', args)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Unreachable hosts are the normal case — ignore.
    }
  }

  static Future<String?> _defaultGateway() async {
    if (!Platform.isWindows) return null;
    try {
      final res = await Process.run('ipconfig', []);
      if (res.exitCode != 0) return null;
      final out = res.stdout as String;
      final m = RegExp(
        r'Default Gateway[^\n:]*:\s*(\d{1,3}(?:\.\d{1,3}){3})',
      ).firstMatch(out);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Plausible demo devices for simulated mode.
  static List<LanDevice> simulatedDevices() => [
        LanDevice(ip: '192.168.1.1', mac: 'aa:bb:cc:00:00:01', isGateway: true),
        LanDevice(ip: '192.168.1.10', mac: 'aa:bb:cc:00:00:0a', isSelf: true),
        LanDevice(ip: '192.168.1.23', mac: 'aa:bb:cc:00:00:17'),
        LanDevice(ip: '192.168.1.42', mac: 'aa:bb:cc:00:00:2a'),
      ];
}

class LanScanException implements Exception {
  const LanScanException(this.message);
  final String message;
  @override
  String toString() => message;
}
