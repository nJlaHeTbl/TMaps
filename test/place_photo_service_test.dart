import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmaps/services/place_photo_service.dart';

void main() {
  test('no request without an exact Commons file reference', () async {
    var requests = 0;
    final service = PlacePhotoService(
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    for (final place in [
      <String, dynamic>{},
      {'wikimedia_commons': 'Category:Toilets'},
      {'image': 'https://evil.test/track.jpg'},
    ]) {
      expect(await service.load(place), isNull);
    }
    expect(requests, 0);
  });
  Map<String, dynamic> response({
    String license = 'CC BY-SA 4.0',
    String host = 'upload.wikimedia.org',
  }) => {
    'query': {
      'pages': {
        '1': {
          'imageinfo': [
            {
              'thumburl': 'https://$host/photo.jpg',
              'mime': 'image/jpeg',
              'extmetadata': {
                'Artist': {'value': '<a href="/wiki/User:Alice">Alice</a>'},
                'LicenseShortName': {'value': license},
              },
            },
          ],
        },
      },
    },
  };
  test('retrieves thumbnail and attribution from Commons only', () async {
    final service = PlacePhotoService(
      client: MockClient((request) async {
        expect(request.url.host, 'commons.wikimedia.org');
        expect(request.url.queryParameters['titles'], 'File:Test toilet.jpg');
        return http.Response(jsonEncode(response()), 200);
      }),
    );
    final photo = await service.load({
      'wikimedia_commons': 'File:Test toilet.jpg',
    });
    expect(photo?.author, 'Alice');
    expect(photo?.license, 'CC BY-SA 4.0');
    expect(photo?.sourceUrl.host, 'commons.wikimedia.org');
  });
  test('rejects unlicensed images and arbitrary image hosts', () async {
    for (final payload in [
      response(license: 'Unknown'),
      response(host: 'evil.test'),
    ]) {
      final service = PlacePhotoService(
        client: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );
      expect(
        await service.load({'wikimedia_commons': 'File:Test.jpg'}),
        isNull,
      );
    }
  });
  test('accepts the current Wikimedia thumbnail host', () async {
    final service = PlacePhotoService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(response(host: 'thumb.wikimedia.org')),
          200,
        ),
      ),
    );
    final photo = await service.load({'wikimedia_commons': 'File:Test.jpg'});
    expect(photo?.url.host, 'thumb.wikimedia.org');
    expect(
      photo?.licenseUrl.toString(),
      'https://creativecommons.org/licenses/by-sa/4.0/',
    );
  });
  test('network failure is reported for a retry instead of hanging', () async {
    final service = PlacePhotoService(
      client: MockClient((_) async => http.Response('offline', 503)),
    );
    expect(
      service.load({'wikimedia_commons': 'File:Test.jpg'}),
      throwsA(isA<Exception>()),
    );
  });
}
