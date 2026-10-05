import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/tracking.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// 3D beam view: an orbit-able wireframe scene showing idealized antenna
/// lobes (whip donut / panel cone), first Fresnel sensing ellipsoids per
/// link, and the live track estimate as a glowing marker.
///
/// Honest limits (stated in the UI): lobe shapes are textbook ideals,
/// not measured patterns, and are not to scale; the TRACK marker is the
/// track estimate — meters-scale, not an image of the object. With 2
/// nodes there is no position fix, so no marker appears; the marker sits
/// at ground level when altitude is unknown.
class BeamScreen extends StatefulWidget {
  const BeamScreen({super.key, required this.state});

  final AppState state;

  @override
  State<BeamScreen> createState() => _BeamScreenState();
}

class _BeamScreenState extends State<BeamScreen> {
  double _azimuth = -0.7;
  double _elevation = 0.5;
  double _zoom = 1.0;
  double _baseZoom = 1.0;

  static const _defaultAzimuth = -0.7;
  static const _defaultElevation = 0.5;

  void _bumpZoom(double f) => setState(() {
        _zoom = (_zoom * f).clamp(0.5, 4.0);
      });

  void _resetView() => setState(() {
        _zoom = 1.0;
        _azimuth = _defaultAzimuth;
        _elevation = _defaultElevation;
      });

  /// Fullscreen 3D view: the beam visualization fills the tab area.
  bool _fullscreen = false;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final nodes = state.effectiveNodes.values.toList();
        if (_fullscreen) {
          return Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _beamVisualization(nodes),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _exitFullscreenChip(),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SentryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('BEAM VIEW', style: SentryType.section()),
                      const Spacer(),
                      IconButton(
                        tooltip: 'FULLSCREEN',
                        icon: const Icon(Icons.fullscreen,
                            color: SentryColors.muted, size: 20),
                        onPressed: () =>
                            setState(() => _fullscreen = true),
                      ),
                      Text('DRAG TO ORBIT',
                          style: SentryType.section(10).copyWith(
                              color: SentryColors.blue)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'IDEALIZED WHIP + PANEL PATTERNS — NOT TO SCALE. '
                    'PANEL AIM AUTO-POINTS AT THE NEAREST NODE. '
                    'SET EACH NODE\'S ANTENNA TYPE ON THE TRACKING TAB.',
                    style: SentryType.section(10)
                        .copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _LegendDot(
                          color: SentryColors.blue, label: 'WHIP'),
                      _LegendDot(
                          color: SentryColors.orange, label: 'PANEL'),
                      _LegendDot(
                          color: SentryColors.amber,
                          label: 'FRESNEL ZONE'),
                      _LegendDot(
                          color: SentryColors.amber,
                          label: 'TRACK'),
                      _LegendDot(
                          color: SentryColors.red, label: 'DEFENDED'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SentryPanel(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                height: 380,
                child: _beamVisualization(nodes),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resetView,
                child: const Text('RESET VIEW'),
              ),
            ),
            const SizedBox(height: 4),
            const _BeamScopeNote(),
          ],
        );
      },
    );
  }

  /// The 3D beam visualization. Adapts to whatever space the parent
  /// gives it (card height normally, full tab in fullscreen).
  Widget _beamVisualization(List<NodePosition> nodes) {
    if (nodes.isEmpty) {
      return Center(
        child: Text('NO NODES YET — START POLLING FIRST',
            style: SentryType.section()),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final vsize =
            Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            Listener(
              onPointerSignal: (signal) {
                if (signal is PointerScrollEvent) {
                  _bumpZoom(signal.scrollDelta.dy < 0
                      ? 1.12
                      : 1 / 1.12);
                }
              },
              child: GestureDetector(
                // Drag orbits, pinch zooms.
                onScaleStart: (_) => _baseZoom = _zoom,
                onScaleUpdate: (d) {
                  setState(() {
                    _zoom =
                        (_baseZoom * d.scale).clamp(0.5, 4.0);
                    _azimuth += d.focalPointDelta.dx * 0.012;
                    _elevation = (_elevation +
                            d.focalPointDelta.dy * 0.012)
                        .clamp(0.08, 1.35);
                  });
                },
                child: CustomPaint(
                  size: vsize,
                  painter: _BeamPainter(
                    nodes: nodes,
                    disturbedPairs: state.disturbedPairs,
                    defended: state.defended,
                    track: state.track,
                    azimuth: _azimuth,
                    elevation: _elevation,
                    zoom: _zoom,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: SentryZoomControls(
                onZoomIn: () => _bumpZoom(1.25),
                onZoomOut: () => _bumpZoom(1 / 1.25),
                onReset: _resetView,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Floating exit-fullscreen chip shown over the fullscreen view.
  Widget _exitFullscreenChip() {
    return Material(
      color: SentryColors.surface2.withAlpha(220),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _fullscreen = false),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fullscreen_exit,
                  color: SentryColors.onDark, size: 16),
              const SizedBox(width: 6),
              Text('EXIT FULLSCREEN',
                  style: SentryType.section(10)
                      .copyWith(color: SentryColors.onDark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: SentryType.section(10)),
      ],
    );
  }
}

class _BeamScopeNote extends StatelessWidget {
  const _BeamScopeNote();

  @override
  Widget build(BuildContext context) {
    return SentryPanel(
      child: Text(
        'WHAT THIS SHOWS — TEXTBOOK ANTENNA PATTERNS PLACED AT YOUR NODE LAYOUT, '
        'PLUS EACH LINK\'S FIRST FRESNEL ZONE (THE SENSITIVE REGION). THE TRACK MARKER '
        'IS THE TRACK ESTIMATE — METERS-SCALE, NOT AN IMAGE OF THE OBJECT. WITH 2 NODES '
        'THERE IS NO POSITION FIX, SO NO MARKER APPEARS. THE MARKER SITS AT GROUND LEVEL '
        'WHEN ALTITUDE IS UNKNOWN.',
        style: SentryType.section(10).copyWith(height: 1.7),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal 3D wireframe engine (perspective projection, painter's algorithm).
// ---------------------------------------------------------------------------

class _V3 {
  const _V3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 scale(double s) => _V3(x * s, y * s, z * s);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) => _V3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );
  double get len => math.sqrt(x * x + y * y + z * z);
  _V3 get norm {
    final l = len;
    return l < 1e-9 ? this : scale(1 / l);
  }
}

class _Wire {
  _Wire(this.pts, this.color, this.width);

  final List<_V3> pts;
  final Color color;
  final double width;
  double depth = 0;
}

class _Billboard {
  _Billboard(this.pos, this.color, this.radiusPx);

  final _V3 pos;
  final Color color;
  final double radiusPx;
}

class _Label3 {
  _Label3(this.pos, this.text, this.color);

  final _V3 pos;
  final String text;
  final Color color;
}

String _pairKey(String a, String b) {
  final ids = [a, b]..sort();
  return '${ids[0]}|${ids[1]}';
}

List<_V3> _circle(_V3 c, _V3 u, _V3 v, double r, int n) {
  return List.generate(n + 1, (i) {
    final a = 2 * math.pi * i / n;
    final ca = math.cos(a) * r;
    final sa = math.sin(a) * r;
    return _V3(c.x + u.x * ca + v.x * sa, c.y + u.y * ca + v.y * sa,
        c.z + u.z * ca + v.z * sa);
  });
}

class _BeamPainter extends CustomPainter {
  _BeamPainter({
    required this.nodes,
    required this.disturbedPairs,
    required this.defended,
    required this.track,
    required this.azimuth,
    required this.elevation,
    required this.zoom,
  });

  final List<NodePosition> nodes;
  final Set<String> disturbedPairs;
  final DefendedPoint defended;
  final TrackEstimate? track;
  final double azimuth;
  final double elevation;
  final double zoom;

  static const _xAxis = _V3(1, 0, 0);
  static const _yAxis = _V3(0, 1, 0);
  static const _zAxis = _V3(0, 0, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final wires = <_Wire>[];
    final boards = <_Billboard>[];
    final labels = <_Label3>[];

    final tops = <String, _V3>{};
    for (final n in nodes) {
      tops[n.nodeId] = _V3(n.x, n.y, n.height);
    }

    // Scene bounds from nodes (+ track + defended).
    var minX = double.infinity,
        maxX = -double.infinity,
        minY = double.infinity,
        maxY = -double.infinity;
    void grow(_V3 p) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    for (final p in tops.values) {
      grow(p);
    }
    grow(_V3(defended.x, defended.y, 0));
    final t = track;
    if (t != null) {
      grow(_V3(t.x, t.y, 0));
    }
    const pad = 18.0;
    minX -= pad;
    maxX += pad;
    minY -= pad;
    maxY += pad;

    // Ground grid, 10 m.
    final gridColor = SentryColors.border.withAlpha(100);
    for (var gx = (minX / 10).floor() * 10.0; gx <= maxX; gx += 10) {
      wires.add(_Wire(
          [_V3(gx, minY, 0), _V3(gx, maxY, 0)], gridColor, 1));
    }
    for (var gy = (minY / 10).floor() * 10.0; gy <= maxY; gy += 10) {
      wires.add(_Wire(
          [_V3(minX, gy, 0), _V3(maxX, gy, 0)], gridColor, 1));
    }

    // Faint mesh links between node tops.
    final linkColor = SentryColors.border.withAlpha(160);
    final ids = tops.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        wires.add(
            _Wire([tops[ids[i]]!, tops[ids[j]]!], linkColor, 1));
      }
    }

    // Fresnel ellipsoids: disturbed pairs always; quiet pairs only when
    // the mesh is small (keeps the scene readable).
    final pairCount = ids.length * (ids.length - 1) ~/ 2;
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final hot =
            disturbedPairs.contains(_pairKey(ids[i], ids[j]));
        if (!hot && pairCount > 6) continue;
        _addFresnel(
            wires,
            tops[ids[i]]!,
            tops[ids[j]]!,
            hot ? SentryColors.amber : SentryColors.muted);
      }
    }

    // Nodes: mast, lobe, dot, label.
    for (final n in nodes) {
      final top = tops[n.nodeId]!;
      wires.add(_Wire([
        _V3(n.x, n.y, 0),
        top
      ], SentryColors.muted.withAlpha(120), 1));
      if (n.antenna == 'panel') {
        _addPanel(wires, top, _aimAtNearest(n));
      } else {
        _addWhip(wires, top);
      }
      boards.add(_Billboard(top, SentryColors.blue, 5));
      labels.add(_Label3(
          _V3(n.x, n.y, n.height + 2.5), n.nodeId, SentryColors.onDark));
    }

    // Defended point marker.
    final dp = _V3(defended.x, defended.y, 0);
    boards.add(_Billboard(dp, SentryColors.red, 5));
    labels.add(
        _Label3(_V3(defended.x, defended.y, 2.5), 'DEF', SentryColors.red));

    // Track marker: glow rings + billboard core + drop line.
    if (t != null) {
      final z = t.altitudeM ?? 0.0;
      final c = _V3(t.x, t.y, z);
      wires.add(_Wire([_V3(t.x, t.y, 0), c],
          SentryColors.amber.withAlpha(130), 1.5));
      for (final r in [3.0, 6.0]) {
        wires.add(_Wire(_circle(c, _xAxis, _yAxis, r, 20),
            SentryColors.amber.withAlpha(110), 1.5));
      }
      boards.add(_Billboard(c, SentryColors.amber, 9));
      boards.add(_Billboard(c, const Color(0xFFFFFFFF), 4));
      labels.add(_Label3(
          _V3(t.x, t.y, z + 3.5),
          t.altitudeM == null ? 'TRACK — ALT UNKNOWN' : 'TRACK',
          SentryColors.amber));
    }

    // Camera.
    final center = _V3((minX + maxX) / 2, (minY + maxY) / 2, 4);
    final extent = math.max(maxX - minX, maxY - minY);
    final dist = math.max(70.0, extent * 1.9 + 30) / zoom;
    final cam = _V3(
      center.x + dist * math.cos(elevation) * math.cos(azimuth),
      center.y + dist * math.cos(elevation) * math.sin(azimuth),
      center.z + dist * math.sin(elevation),
    );
    final fwd = (center - cam).norm;
    final right = fwd.cross(_zAxis).norm;
    final up = right.cross(fwd).norm;
    final focal = size.height * 1.15;

    Offset? project(_V3 p) {
      final rel = p - cam;
      final cz = rel.dot(fwd);
      if (cz < 1.0) return null;
      final cx = rel.dot(right);
      final cy = rel.dot(up);
      return Offset(size.width / 2 + cx * focal / cz,
          size.height / 2 - cy * focal / cz);
    }

    // Project + depth-sort wires (painter's algorithm).
    final drawable = <_Wire>[];
    for (final w in wires) {
      var dSum = 0.0;
      var dN = 0;
      for (final p in w.pts) {
        final cz = (p - cam).dot(fwd);
        if (cz >= 1.0) {
          dSum += cz;
          dN++;
        }
      }
      if (dN == 0) continue;
      w.depth = dSum / dN;
      drawable.add(w);
    }
    drawable.sort((a, b) => b.depth.compareTo(a.depth));

    for (final w in drawable) {
      final paint = Paint()
        ..color = w.color
        ..strokeWidth = w.width
        ..style = PaintingStyle.stroke;
      final path = Path();
      var pen = false;
      for (final p in w.pts) {
        final s = project(p);
        if (s == null) {
          pen = false;
          continue;
        }
        if (!pen) {
          path.moveTo(s.dx, s.dy);
          pen = true;
        } else {
          path.lineTo(s.dx, s.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    // Billboards (screen-space glow dots).
    for (final b in boards) {
      final s = project(b.pos);
      if (s == null) continue;
      canvas.drawCircle(
          s, b.radiusPx + 5, Paint()..color = b.color.withAlpha(45));
      canvas.drawCircle(s, b.radiusPx, Paint()..color = b.color);
    }

    // Labels.
    for (final l in labels) {
      final s = project(l.pos);
      if (s == null) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: l.text,
            style: TextStyle(
              color: l.color,
              fontSize: 10,
              fontFamily: SentryType.mono,
              letterSpacing: 1.2,
            )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, s + const Offset(8, -8));
    }
  }

  /// Direction from [n] to its nearest other node (panel aim).
  _V3 _aimAtNearest(NodePosition n) {
    var best = 1e18;
    _V3? dir;
    for (final o in nodes) {
      if (o.nodeId == n.nodeId) continue;
      final d = _V3(o.x - n.x, o.y - n.y, o.height - n.height);
      final l = d.len;
      if (l < best) {
        best = l;
        dir = d;
      }
    }
    return (dir ?? const _V3(1, 0, 0)).norm;
  }

  /// Idealized whip (short dipole) power pattern: sin^2(polar).
  void _addWhip(List<_Wire> wires, _V3 apex) {
    const L = 16.0; // display size only — not to scale
    const color = SentryColors.blue;
    for (var ti = 1; ti <= 11; ti++) {
      final th = ti * math.pi / 12;
      final r = L * math.pow(math.sin(th), 2);
      final ringR = r * math.sin(th);
      if (ringR < 0.3) continue;
      wires.add(_Wire(
          _circle(_V3(apex.x, apex.y, apex.z + r * math.cos(th)),
              _xAxis, _yAxis, ringR, 20),
          color.withAlpha(80),
          1));
    }
    for (var mi = 0; mi < 8; mi++) {
      final p = mi * math.pi / 4;
      final pts = <_V3>[];
      for (var k = 0; k <= 24; k++) {
        final th = 0.1 + k * (math.pi - 0.2) / 24;
        final r = L * math.pow(math.sin(th), 2);
        pts.add(_V3(
          apex.x + r * math.sin(th) * math.cos(p),
          apex.y + r * math.sin(th) * math.sin(p),
          apex.z + r * math.cos(th),
        ));
      }
      wires.add(_Wire(pts, color.withAlpha(60), 1));
    }
  }

  /// Idealized panel lobe: cone aimed at [aim], ~64° beamwidth.
  void _addPanel(List<_Wire> wires, _V3 apex, _V3 aim) {
    const color = SentryColors.orange;
    const halfAngle = 32 * math.pi / 180;
    final ref = aim.z.abs() < 0.9 ? _zAxis : _yAxis;
    final u = aim.cross(ref).norm;
    final v = aim.cross(u).norm;
    for (final d in [9.0, 18.0, 27.0]) {
      // display sizes only — not to scale
      final c = apex + aim.scale(d);
      wires.add(_Wire(_circle(c, u, v, d * math.tan(halfAngle), 20),
          color.withAlpha(110), 1));
    }
    final outerR = 27.0 * math.tan(halfAngle);
    final outerC = apex + aim.scale(27.0);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final edge = _V3(
        outerC.x + (u.x * math.cos(a) + v.x * math.sin(a)) * outerR,
        outerC.y + (u.y * math.cos(a) + v.y * math.sin(a)) * outerR,
        outerC.z + (u.z * math.cos(a) + v.z * math.sin(a)) * outerR,
      );
      wires.add(_Wire([apex, edge], color.withAlpha(70), 1));
    }
  }

  /// First Fresnel zone ellipsoid between two node tops at 2440 MHz.
  void _addFresnel(List<_Wire> wires, _V3 a, _V3 b, Color color) {
    const lambda = 0.123; // 2440 MHz
    final d = (b - a).len;
    if (d < 2) return;
    final axis = (b - a).norm;
    final ref = axis.z.abs() < 0.9 ? _zAxis : _yAxis;
    final u = axis.cross(ref).norm;
    final v = axis.cross(u).norm;
    for (var k = 1; k <= 5; k++) {
      final f = k / 6;
      final r = math.sqrt(lambda * d * f * (1 - f));
      final c = a + axis.scale(d * f);
      wires.add(_Wire(
          _circle(c, u, v, r, 24), color.withAlpha(55), 1));
    }
    for (final w in [u, v]) {
      for (final sgn in [1.0, -1.0]) {
        final pts = <_V3>[];
        for (var k = 0; k <= 24; k++) {
          final f = k / 24;
          final r =
              math.sqrt(math.max(0, lambda * d * f * (1 - f)));
          final c = a + axis.scale(d * f);
          pts.add(_V3(c.x + w.x * r * sgn, c.y + w.y * r * sgn,
              c.z + w.z * r * sgn));
        }
        wires.add(_Wire(pts, color.withAlpha(55), 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BeamPainter old) => true;
}
