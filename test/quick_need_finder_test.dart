import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/quick_need_finder.dart';

void main() {
  test('finds the nearest confirmed place for every immediate need', () {
    final places = <Map<String, dynamic>>[
      {'id': 1, 'lat': 45.001, 'lng': 78.0, 'place_kind': 'public_toilet'},
      {
        'id': 2,
        'lat': 45.0001,
        'lng': 78.0,
        'place_kind': 'public_toilet',
        'submission_status': 'pending',
      },
      {
        'id': 3,
        'lat': 45.002,
        'lng': 78.0,
        'place_kind': 'water',
        'drinking_water': true,
      },
      {
        'id': 4,
        'lat': 45.0005,
        'lng': 78.0,
        'place_kind': 'water',
        'drinking_water': false,
      },
      {'id': 5, 'lat': 45.003, 'lng': 78.0, 'place_kind': 'phone_charging'},
    ];

    final results = QuickNeedFinder.findNearest(
      places: places,
      origin: const LatLng(45, 78),
    );

    expect(results.map((result) => result.kind), QuickNeedKind.values);
    expect(results.map((result) => result.place['id']), [1, 3, 5]);
    expect(results.every((result) => result.distanceMeters > 0), isTrue);
  });

  test('also finds charging available inside another kind of place', () {
    final results = QuickNeedFinder.findNearest(
      places: [
        {
          'id': 9,
          'lat': 45.001,
          'lng': 78.001,
          'place_kind': 'cafe',
          'has_toilet': false,
          'phone_charging': true,
        },
      ],
      origin: const LatLng(45, 78),
    );

    expect(results, hasLength(1));
    expect(results.single.kind, QuickNeedKind.phoneCharging);
    expect(results.single.place['id'], 9);
  });
}
