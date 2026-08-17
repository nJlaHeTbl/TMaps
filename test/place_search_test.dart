import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/place_info.dart';
import 'package:tmaps/core/place_search.dart';

void main() {
  final places = <Map<String, dynamic>>[
    {
      'name': 'Qazaq Oil',
      'place_kind': 'fuel',
      'has_toilet': true,
      'lat': 45.01,
      'lng': 78.01,
    },
    {
      'name': 'Бауырсак',
      'place_kind': 'cafe',
      'has_toilet': false,
      'lat': 45.02,
      'lng': 78.02,
    },
    {
      'place_kind': 'public_toilet',
      'has_toilet': true,
      'lat': 45.001,
      'lng': 78.001,
    },
    {
      'name': 'Водомат',
      'place_kind': 'water',
      'water_type': 'vending_machine',
      'has_toilet': false,
      'lat': 45.03,
      'lng': 78.03,
    },
  ];

  test('понимает короткие названия категорий', () {
    final results = PlaceSearch.find(
      places,
      query: 'азс',
      origin: const LatLng(45, 78),
    );

    expect(results, hasLength(1));
    expect(PlaceInfo.kindOf(results.single.place), PlaceKind.fuel);
  });

  test('поиск по названию не зависит от регистра', () {
    final results = PlaceSearch.find(
      places,
      query: 'qAzAq',
      origin: const LatLng(45, 78),
    );

    expect(results.single.place['name'], 'Qazaq Oil');
  });

  test('без запроса первым показывает ближайшее место с туалетом', () {
    final results = PlaceSearch.find(
      places,
      query: '',
      origin: const LatLng(45, 78),
    );

    expect(PlaceInfo.kindOf(results.first.place), PlaceKind.publicToilet);
  });

  test('фильтрует по выбранной категории', () {
    final results = PlaceSearch.find(
      places,
      query: '',
      origin: const LatLng(45, 78),
      category: PlaceKind.cafe,
    );

    expect(results, hasLength(1));
    expect(results.single.place['name'], 'Бауырсак');
  });

  test('находит воду по разговорному названию', () {
    final results = PlaceSearch.find(
      places,
      query: 'водомат',
      origin: const LatLng(45, 78),
    );

    expect(results, hasLength(1));
    expect(PlaceInfo.kindOf(results.single.place), PlaceKind.water);
  });
}
