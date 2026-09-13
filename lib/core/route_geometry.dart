import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Local metre projection for measuring deviation from a walking route.
/// This measures proximity only; it never invents a walkable connecting line.
double distanceToWalkingRoute(LatLng point, List<LatLng> route) {
  if (route.length < 2) return double.infinity;
  final longitudeScale = 111320 * cos(point.latitude * pi / 180);
  const latitudeScale = 110540.0;
  var nearest = double.infinity;
  for (var i = 1; i < route.length; i++) {
    final start = route[i - 1];
    final end = route[i];
    final x = (start.longitude - point.longitude) * longitudeScale;
    final y = (start.latitude - point.latitude) * latitudeScale;
    final dx = (end.longitude - start.longitude) * longitudeScale;
    final dy = (end.latitude - start.latitude) * latitudeScale;
    final lengthSquared = dx * dx + dy * dy;
    final fraction = lengthSquared == 0
        ? 0.0
        : ((-x * dx - y * dy) / lengthSquared).clamp(0.0, 1.0);
    final nearestX = x + fraction * dx;
    final nearestY = y + fraction * dy;
    nearest = min(nearest, sqrt(nearestX * nearestX + nearestY * nearestY));
  }
  return nearest;
}
