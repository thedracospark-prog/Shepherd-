import 'dart:math' as math;

/// Convex hull of a point set via Andrew's monotonic chain.
///
/// Returns hull vertices in counter-clockwise order, without repeating
/// the first point. Collinear points on hull edges are dropped, so the
/// result is the minimal vertex set. Degenerate inputs (fewer than 3
/// distinct points) are returned as-is: 2 points = the segment, 1 = the
/// point, 0 = empty.
List<math.Point<double>> convexHull(List<math.Point<double>> points) {
  final uniq = <math.Point<double>>{...points};
  final sorted = uniq.toList()
    ..sort((a, b) =>
        a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (sorted.length < 3) return sorted;

  double cross(math.Point<double> o, math.Point<double> a,
          math.Point<double> b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  final lower = <math.Point<double>>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <math.Point<double>>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return lower + upper;
}
