import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TMaps root widget can be created', () {
    expect(const TMapsApp(), isA<TMapsApp>());
  });

  test('Kazakhstan OpenStreetMap toilet dataset is bundled', () async {
    final json = await rootBundle.loadString(
      'assets/data/kazakhstan_toilets.json',
    );
    final payload = jsonDecode(json) as Map<String, dynamic>;
    final toilets = payload['toilets'] as List<dynamic>;

    expect(toilets, hasLength(payload['count'] as int));
    expect(toilets, isNotEmpty);
  });
}
