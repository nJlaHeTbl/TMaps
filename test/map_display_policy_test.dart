import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/map_display_policy.dart';

void main() {
  final places = [
    {'lat': 45.0156, 'lng': 78.3731, 'name': 'Талдыкорган'},
    {'lat': 43.2389, 'lng': 76.8897, 'name': 'Алматы'},
  ];

  test('не рисует тысячи меток на масштабе страны', () {
    final visible = MapDisplayPolicy.placesInside(
      places,
      zoom: 6,
      bounds: LatLngBounds(const LatLng(40, 70), const LatLng(50, 82)),
    );

    expect(visible, isEmpty);
  });

  test('оставляет только места в видимой области', () {
    final visible = MapDisplayPolicy.placesInside(
      places,
      zoom: 14,
      bounds: LatLngBounds(const LatLng(44.9, 78.2), const LatLng(45.2, 78.5)),
    );

    expect(visible.map((place) => place['name']), ['Талдыкорган']);
  });
}
