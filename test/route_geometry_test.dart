import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/route_geometry.dart';

void main() {
  const south = LatLng(45, 78);
  const north = LatLng(45.01, 78);
  test('measures the nearest segment, not just its endpoints', () {
    expect(
      distanceToWalkingRoute(const LatLng(45.005, 78), [south, north]),
      closeTo(0, .01),
    );
    expect(
      distanceToWalkingRoute(const LatLng(45.005, 78.001), [south, north]),
      closeTo(78.7, 1),
    );
  });
  test('does not extend a segment beyond the destination', () {
    expect(
      distanceToWalkingRoute(const LatLng(45.011, 78), [south, north]),
      closeTo(110.5, 1),
    );
  });
  test('handles repeated points and incomplete routes', () {
    expect(distanceToWalkingRoute(south, [south, south, north]), 0);
    expect(distanceToWalkingRoute(south, []), double.infinity);
    expect(distanceToWalkingRoute(south, [south]), double.infinity);
  });
  test('does not treat a shortcut across a corner as the walking path', () {
    expect(
      distanceToWalkingRoute(const LatLng(45.005, 78.005), [
        south,
        north,
        const LatLng(45.01, 78.01),
      ]),
      greaterThan(390),
    );
  });
}
