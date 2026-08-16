import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/map_marker_clustering.dart';

void main() {
  final bounds = LatLngBounds(const LatLng(44, 77), const LatLng(46, 79));
  final places = [
    {'name': 'Рядом 1', 'lat': 45.0, 'lng': 78.0},
    {'name': 'Рядом 2', 'lat': 45.01, 'lng': 78.01},
    {'name': 'Далеко', 'lat': 45.8, 'lng': 78.8},
  ];

  test('объединяет близкие метки на среднем масштабе', () {
    final groups = MapMarkerClustering.group(
      places,
      bounds: bounds,
      viewportWidth: 390,
      viewportHeight: 844,
      zoom: 12,
    );

    expect(groups, hasLength(2));
    expect(groups.any((group) => group.places.length == 2), isTrue);
  });

  test('на близком масштабе оставляет каждую метку отдельной', () {
    final groups = MapMarkerClustering.group(
      places,
      bounds: bounds,
      viewportWidth: 390,
      viewportHeight: 844,
      zoom: 16,
    );

    expect(groups, hasLength(3));
    expect(groups.every((group) => !group.isCluster), isTrue);
  });
}
