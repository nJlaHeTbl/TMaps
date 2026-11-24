import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmaps/data/http_community_backend.dart';
import 'package:tmaps/data/toilet_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a stalled community backend cannot block bundled places', () async {
    final repository = ToiletRepository(
      HttpCommunityBackend(
        baseUrl: 'https://tmaps.test',
        client: MockClient((_) => Completer<http.Response>().future),
      ),
    );
    final places = await repository.fetchAll().timeout(
      const Duration(seconds: 8),
    );
    expect(places.length, greaterThan(2000));
  });
  test(
    'photo references attach to the correct bundled place without a backend',
    () async {
      final repository = ToiletRepository(
        HttpCommunityBackend(
          baseUrl: 'https://tmaps.test',
          client: MockClient((_) async => http.Response('offline', 503)),
        ),
      );
      final places = await repository.fetchAll();
      final silkway = places.singleWhere(
        (p) => p['source_id'] == 'way/499328514',
      );
      expect(silkway['name'], 'Mega Silk Way');
      expect(
        silkway['wikimedia_commons'],
        'File:Aĉetcentro SilkWay (Astano) 02.jpg',
      );
      final spring = places.singleWhere(
        (p) => p['source_id'] == 'node/6755420269',
      );
      expect(spring['water_type'], 'spring');
      expect(
        spring['wikimedia_commons'],
        'File:03 Родник Чокана Валиханова.jpg',
      );
      expect(places.where((p) => p['wikimedia_commons'] != null), hasLength(2));
      expect(places.length, greaterThan(2000));
    },
  );
}
