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
      'name': 'Community WC',
      'place_kind': 'community_toilet',
      'has_toilet': true,
      'lat': 45.002,
      'lng': 78.002,
    },
    {
      'name': 'Водомат',
      'place_kind': 'water',
      'water_type': 'vending_machine',
      'has_toilet': false,
      'lat': 45.03,
      'lng': 78.03,
    },
    {
      'name': 'City Market',
      'place_kind': 'organization',
      'has_toilet': false,
      'lat': 45.04,
      'lng': 78.04,
    },
    {
      'name': 'Power Hub',
      'place_kind': 'phone_charging',
      'has_toilet': false,
      'lat': 45.05,
      'lng': 78.05,
    },
    {
      'name': 'E-Charge',
      'place_kind': 'ev_charging',
      'has_toilet': false,
      'lat': 45.06,
      'lng': 78.06,
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

  test('ищет категории по русским, казахским и английским синонимам', () {
    const cases = <({String query, PlaceKind kind})>[
      (query: 'санузел', kind: PlaceKind.publicToilet),
      (query: 'дәретхана', kind: PlaceKind.publicToilet),
      (query: 'restroom', kind: PlaceKind.publicToilet),
      (query: 'user added toilet', kind: PlaceKind.communityToilet),
      (query: 'столовая', kind: PlaceKind.cafe),
      (query: 'мейрамхана', kind: PlaceKind.cafe),
      (query: 'restaurant', kind: PlaceKind.cafe),
      (query: 'топливо', kind: PlaceKind.fuel),
      (query: 'жанармай', kind: PlaceKind.fuel),
      (query: 'petrol', kind: PlaceKind.fuel),
      (query: 'магазин', kind: PlaceKind.organization),
      (query: 'дүкен', kind: PlaceKind.organization),
      (query: 'shop', kind: PlaceKind.organization),
      (query: 'розетка', kind: PlaceKind.phoneCharging),
      (query: 'телефон қуаттау', kind: PlaceKind.phoneCharging),
      (query: 'phone outlet', kind: PlaceKind.phoneCharging),
      (query: 'электромобиль', kind: PlaceKind.evCharging),
      (query: 'электр көлігі', kind: PlaceKind.evCharging),
      (query: 'electric vehicle', kind: PlaceKind.evCharging),
      (query: 'скважина', kind: PlaceKind.water),
      (query: 'ауыз су', kind: PlaceKind.water),
      (query: 'drinking water', kind: PlaceKind.water),
    ];

    for (final searchCase in cases) {
      final results = PlaceSearch.find(
        places,
        query: searchCase.query,
        origin: const LatLng(45, 78),
      );

      expect(
        results.map((result) => PlaceInfo.kindOf(result.place)),
        contains(searchCase.kind),
        reason: 'Запрос: ${searchCase.query}',
      );
    }
  });
}
