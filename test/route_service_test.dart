import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/services/route_service.dart';

Map<String, dynamic> responseBody() => {
  'code': 'Ok',
  'routes': [
    <String, dynamic>{
      'distance': 150,
      'duration': 120,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [78, 45],
          [78.001, 45.001],
        ],
      },
    },
  ],
};

void main() {
  const from = LatLng(45, 78);
  const to = LatLng(45.001, 78.001);
  test('uses the pedestrian server and longitude-first GeoJSON', () async {
    final client = MockClient((request) async {
      expect(request.url.path, contains('/routed-foot/'));
      expect(request.url.path, endsWith('/78.0,45.0;78.001,45.001'));
      expect(request.url.queryParameters['geometries'], 'geojson');
      return http.Response(jsonEncode(responseBody()), 200);
    });
    addTearDown(client.close);
    final route = await RouteService(client: client).build(from: from, to: to);
    expect(route.points, [from, to]);
    expect(route.distance, 150);
    expect(route.duration, 120);
    expect(() => route.points[0] = to, throwsUnsupportedError);
  });

  final invalidBodies = <String, Object>{
    'non-object response': [],
    'no walking route': {'code': 'NoRoute'},
    'missing routes': {'code': 'Ok'},
    'empty routes': {'code': 'Ok', 'routes': []},
    'invalid route': {
      'code': 'Ok',
      'routes': [null],
    },
  };
  for (final entry in invalidBodies.entries) {
    test('rejects ${entry.key}', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(entry.value), 200),
      );
      addTearDown(client.close);
      await expectLater(
        RouteService(client: client).build(from: from, to: to),
        throwsException,
      );
    });
  }
  final invalidRoutes = <String, Map<String, dynamic>>{
    'negative distance': {'distance': -1},
    'missing duration': {'duration': null},
    'wrong geometry type': {
      'geometry': {
        'type': 'Point',
        'coordinates': [78, 45],
      },
    },
    'one coordinate': {
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [78, 45],
        ],
      },
    },
    'out of range': {
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [78, 45],
          [78, 95],
        ],
      },
    },
    'non-numeric coordinate': {
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [78, 45],
          ['bad', 45],
        ],
      },
    },
  };
  for (final entry in invalidRoutes.entries) {
    test('rejects ${entry.key}', () async {
      final body = responseBody();
      (body['routes'] as List).first.addAll(entry.value);
      final client = MockClient(
        (_) async => http.Response(jsonEncode(body), 200),
      );
      addTearDown(client.close);
      await expectLater(
        RouteService(client: client).build(from: from, to: to),
        throwsFormatException,
      );
    });
  }
  test('rejects HTTP failure and invalid JSON', () async {
    for (final response in [
      http.Response('unavailable', 503),
      http.Response('<html>', 200),
    ]) {
      final client = MockClient((_) async => response);
      addTearDown(client.close);
      await expectLater(
        RouteService(client: client).build(from: from, to: to),
        throwsException,
      );
    }
  });
}
