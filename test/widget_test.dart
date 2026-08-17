import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TMaps root widget can be created', () {
    expect(const TMapsApp(), isA<TMapsApp>());
  });

  test('Kazakhstan OpenStreetMap place dataset is bundled', () async {
    final json = await rootBundle.loadString(
      'assets/data/kazakhstan_toilets.json',
    );
    final payload = jsonDecode(json) as Map<String, dynamic>;
    final places = (payload['places'] ?? payload['toilets']) as List<dynamic>;

    expect(places, hasLength(payload['count'] as int));
    expect(places, isNotEmpty);
    expect(
      places.where(
        (place) =>
            (place as Map<String, dynamic>)['place_kind'] == 'public_toilet',
      ),
      isNotEmpty,
    );
    expect(
      places.where(
        (place) => (place as Map<String, dynamic>)['place_kind'] == 'water',
      ),
      isNotEmpty,
    );
  });

  test('curated Taldykorgan water points are bundled', () async {
    final json = await rootBundle.loadString('assets/data/curated_places.json');
    final payload = jsonDecode(json) as Map<String, dynamic>;
    final places = payload['places'] as List<dynamic>;

    expect(places, hasLength(payload['count'] as int));
    expect(
      places.where(
        (place) => (place as Map<String, dynamic>)['place_kind'] == 'water',
      ),
      hasLength(8),
    );
  });
}
