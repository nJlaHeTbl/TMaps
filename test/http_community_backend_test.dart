import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmaps/core/place_info.dart';
import 'package:tmaps/data/community_backend.dart';
import 'package:tmaps/data/http_community_backend.dart';

void main() {
  test('loads community places from the configured API', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test/',
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://api.tmaps.test/api/places');
        return http.Response(
          jsonEncode({
            'places': [
              {'id': 7, 'lat': 45.0, 'lng': 78.0},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final places = await backend.fetchPlaces();
    expect(places, hasLength(1));
    expect(places.single['id'], 7);
  });

  test('sends a moderated submission and returns its id', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/submissions');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['placeKind'], 'community_toilet');
        expect(body['isFree'], true);
        return http.Response(jsonEncode({'id': 42, 'status': 'pending'}), 201);
      }),
    );

    final id = await backend.submitPlace(
      latitude: 45.0156,
      longitude: 78.3739,
      username: 'Асылбек',
      placeKind: PlaceKind.communityToilet,
      isFree: true,
      cleanliness: 4,
      condition: 'Хорошее',
    );

    expect(id, 42);
  });

  test('shows a readable server error', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'error': 'Слишком много действий'})),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    expect(
      backend.fetchReports,
      throwsA(
        isA<CommunityBackendException>().having(
          (error) => error.message,
          'message',
          'Слишком много действий',
        ),
      ),
    );
  });

  test('sends an updated toilet fee in a community report', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/reports');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['isFree'], false);
        return http.Response(
          jsonEncode({
            'report': {'id': 8, 'is_free': false},
          }),
          201,
        );
      }),
    );

    final report = await backend.addReport(
      placeKey: 'osm:123',
      latitude: 45,
      longitude: 78,
      username: 'Мирас',
      cleanliness: 4,
      condition: 'Хорошее',
      isFree: false,
      hasToilet: true,
      hasPaper: true,
      hasSoap: true,
      wheelchairAccessible: null,
      phoneCharging: null,
      accessType: 'public',
    );

    expect(report['is_free'], isFalse);
  });
}
