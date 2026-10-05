/// Driver-namespace helpers for node IDs and link keys.
///
/// Every radio driver namespaces its node IDs (`silvus:90550`,
/// `meshtastic:!a1b2c3d4`) so link keys can never collide across
/// vendors. These pure-string helpers live here (not in app_state)
/// so services like the track stitcher can use them without an
/// import cycle.
library;

/// Short display ID: strips the driver namespace (`silvus:90550` → `90550`).
String shortNodeId(String id) {
  final i = id.indexOf(':');
  return i < 0 ? id : id.substring(i + 1);
}

/// Driver namespace of a node ID (`silvus:90550` → `silvus`), '' if none.
String driverOf(String id) {
  final i = id.indexOf(':');
  return i < 0 ? '' : id.substring(0, i);
}

/// Short display form of a link key (`silvus:90550 → silvus:90551`
/// becomes `90550 → 90551`).
String shortLinkKey(String linkKey) =>
    linkKey.split(' → ').map(shortNodeId).join(' → ');
