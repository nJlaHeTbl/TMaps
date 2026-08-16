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

  test('на масштабе области оставляет компактный обзор', () {
    final manyPlaces = List.generate(
      30,
      (index) => {
        'lat': 44.0 + index / 100,
        'lng': 77.0 + index / 100,
        'place_kind': 'public_toilet',
      },
    );

    final visible = MapDisplayPolicy.placesInside(
      manyPlaces,
      zoom: 11.4,
      bounds: LatLngBounds(const LatLng(43, 76), const LatLng(46, 80)),
    );

    expect(visible, hasLength(8));
  });

  test('на масштабе области ещё не показывает отдельные метки', () {
    final visible = MapDisplayPolicy.placesInside(
      places,
      zoom: 9.8,
      bounds: LatLngBounds(const LatLng(43, 76), const LatLng(47, 82)),
    );

    expect(visible, isEmpty);
  });

  test('распределяет метки по всей видимой области', () {
    final clusteredPlaces = [
      for (var index = 0; index < 20; index++)
        {
          'name': 'Центр $index',
          'lat': 45.0 + index / 10000,
          'lng': 78.0 + index / 10000,
          'place_kind': 'cafe',
        },
      {'name': 'Север', 'lat': 45.8, 'lng': 78.8, 'place_kind': 'cafe'},
    ];

    final visible = MapDisplayPolicy.placesInside(
      clusteredPlaces,
      zoom: 11.4,
      bounds: LatLngBounds(const LatLng(44.9, 77.9), const LatLng(46, 79)),
    );

    expect(visible, hasLength(8));
    expect(visible.any((place) => place['name'] == 'Север'), isTrue);
  });
}
