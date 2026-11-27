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
        expect(body['name'], isNull);
        expect(body['isFree'], true);
        expect(body['deviceKey'], 'device-test-12345');
        return http.Response(jsonEncode({'id': 42, 'status': 'pending'}), 201);
      }),
    );

    final id = await backend.submitPlace(
      latitude: 45.0156,
      longitude: 78.3739,
      username: 'Асылбек',
      placeKind: PlaceKind.communityToilet,
      name: null,
      isFree: true,
      cleanliness: 4,
      condition: 'Хорошее',
      hasPaper: null,
      hasSoap: null,
      wheelchairAccessible: null,
      phoneCharging: null,
      accessType: 'public',
      deviceKey: 'device-test-12345',
    );

    expect(id, 42);
  });

  test('sends a named cafe submission with access details', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['placeKind'], 'cafe');
        expect(body['name'], 'Кофейня у парка');
        expect(body['accessType'], 'customers');
        expect(body['phoneCharging'], true);
        return http.Response(jsonEncode({'id': 51, 'status': 'pending'}), 201);
      }),
    );

    final id = await backend.submitPlace(
      latitude: 45.0156,
      longitude: 78.3739,
      username: 'Мирас',
      placeKind: PlaceKind.cafe,
      name: 'Кофейня у парка',
      isFree: true,
      cleanliness: 5,
      condition: 'Хорошее',
      hasPaper: null,
      hasSoap: null,
      wheelchairAccessible: null,
      phoneCharging: true,
      accessType: 'customers',
      deviceKey: 'device-test-12345',
    );

    expect(id, 51);
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

  test('loads approved location overrides', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/location-overrides');
        return http.Response(
          jsonEncode({
            'overrides': [
              {'place_key': 'osm:123', 'lat': 45.0157, 'lng': 78.374},
            ],
          }),
          200,
        );
      }),
    );

    final overrides = await backend.fetchLocationOverrides();
    expect(overrides, hasLength(1));
    expect(overrides.single['place_key'], 'osm:123');
  });

  test('loads submissions waiting for community review', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/community-reviews');
        return http.Response(
          jsonEncode({
            'submissions': [
              {
                'submission_id': 12,
                'lat': 45.01,
                'lng': 78.39,
                'confirmation_count': 1,
              },
            ],
          }),
          200,
        );
      }),
    );

    final submissions = await backend.fetchCommunityReviewSubmissions();
    expect(submissions.single['submission_id'], 12);
    expect(submissions.single['confirmation_count'], 1);
  });

  test('sends an independent community review vote', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/community-reviews/12/votes');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['voterKey'], 'device-test-67890');
        expect(body['isValid'], true);
        return http.Response(
          jsonEncode({
            'review': {
              'status': 'pending',
              'confirmation_count': 1,
              'rejection_count': 0,
            },
          }),
          200,
        );
      }),
    );

    final result = await backend.reviewSubmission(
      submissionId: 12,
      voterKey: 'device-test-67890',
      isValid: true,
    );
    expect(result['status'], 'pending');
    expect(result['confirmation_count'], 1);
  });

  test('loads active paper help signals', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/help-requests');
        return http.Response(
          jsonEncode({
            'requests': [
              {
                'place_key': 'osm:123',
                'request_type': 'paper',
                'expires_at': '2026-08-27T12:45:00Z',
              },
            ],
          }),
          200,
        );
      }),
    );

    final requests = await backend.fetchActiveHelpRequests();
    expect(requests.single['place_key'], 'osm:123');
  });

  test('loads active pedestrian road alerts', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/pedestrian-alerts');
        return http.Response(
          jsonEncode({
            'alerts': [
              {'id': 3, 'lat': 45.01, 'lng': 78.39, 'alert_type': 'ice'},
            ],
          }),
          200,
        );
      }),
    );

    final alerts = await backend.fetchPedestrianAlerts();
    expect(alerts.single['alert_type'], 'ice');
  });

  test('reports a pedestrian road condition', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/pedestrian-alerts');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['alertType'], 'construction');
        expect(body['description'], 'Тропинка перекрыта');
        return http.Response(jsonEncode({'id': 14}), 201);
      }),
    );

    final id = await backend.submitPedestrianAlert(
      latitude: 45.01,
      longitude: 78.39,
      alertType: 'construction',
      username: 'Мирас',
      reporterKey: 'device-test-12345',
      description: 'Тропинка перекрыта',
    );

    expect(id, 14);
  });

  test('creates a temporary paper help signal', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/help-requests');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['placeKey'], 'osm:123');
        expect(body['requesterKey'], 'device-test-12345');
        return http.Response(
          jsonEncode({'expiresAt': '2026-08-27T12:45:00Z'}),
          201,
        );
      }),
    );

    final expiresAt = await backend.requestPaperHelp(
      placeKey: 'osm:123',
      latitude: 45.01,
      longitude: 78.39,
      requesterKey: 'device-test-12345',
    );
    expect(expiresAt, DateTime.utc(2026, 8, 27, 12, 45));
  });

  test('submits a location correction for moderation', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/location-corrections');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['placeKey'], 'curated:beach-toilet');
        expect(body['currentLat'], 45.019598);
        expect(body['proposedLat'], 45.0197);
        expect(body['username'], 'Мирас');
        return http.Response(jsonEncode({'id': 9, 'status': 'pending'}), 201);
      }),
    );

    final id = await backend.submitLocationCorrection(
      placeKey: 'curated:beach-toilet',
      currentLatitude: 45.019598,
      currentLongitude: 78.399912,
      proposedLatitude: 45.0197,
      proposedLongitude: 78.4001,
      username: 'Мирас',
    );

    expect(id, 9);
  });

  test('attaches a fresh Turnstile token to protected writes only', () async {
    var issued = 0;
    final bodies = <String, Map<String, dynamic>>{};
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      turnstileToken: () async => 'token-${++issued}',
      client: MockClient((request) async {
        bodies[request.url.path] =
            jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/api/help-requests') {
          return http.Response(
            jsonEncode({'expiresAt': '2026-11-27T10:00:00Z'}),
            200,
          );
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );

    await backend.castVote(
      placeKey: 'community:1',
      voterKey: 'voter-test-12345',
      isCurrent: true,
    );
    await backend.requestPaperHelp(
      placeKey: 'community:1',
      latitude: 45.0,
      longitude: 78.0,
      requesterKey: 'voter-test-12345',
    );

    expect(bodies['/api/votes']!['turnstileToken'], 'token-1');
    expect(
      bodies['/api/help-requests']!.containsKey('turnstileToken'),
      isFalse,
    );
    expect(issued, 1);
  });

  test('reports a clear error when the Turnstile check fails', () async {
    final backend = HttpCommunityBackend(
      baseUrl: 'https://api.tmaps.test',
      turnstileToken: () async => throw StateError('widget failed'),
      client: MockClient((request) async {
        fail('No request should be sent without a token');
      }),
    );

    expect(
      backend.castVote(
        placeKey: 'community:1',
        voterKey: 'voter-test-12345',
        isCurrent: true,
      ),
      throwsA(isA<CommunityBackendException>()),
    );
  });
}
