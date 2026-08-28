import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/services/place_share_service.dart';

void main() {
  const service = PlaceShareService();
  final place = <String, dynamic>{
    'id': 42,
    'lat': 45.015,
    'lng': 78.39,
    'place_kind': 'public_toilet',
    'source': 'community',
  };

  test('builds one public canonical link for a place', () {
    final link = service.buildLink(place);

    expect(link.origin, 'https://njlahetbl.github.io');
    expect(link.path, '/TMaps/');
    expect(link.queryParameters['place'], 'community:42');
    expect(link.queryParameters['lat'], '45.015');
    expect(link.queryParameters['lng'], '78.39');
  });

  test('opens a linked place by stable key', () {
    final linkedPlace = service.findLinkedPlace(
      Uri.parse(
        'https://njlahetbl.github.io/TMaps/?place=community%3A42&lat=1&lng=2',
      ),
      [place],
    );

    expect(linkedPlace, same(place));
  });

  test('falls back to nearby coordinates when the key changed', () {
    final nearby = <String, dynamic>{
      'id': 77,
      'lat': 45.0154,
      'lng': 78.3904,
      'place_kind': 'public_toilet',
    };
    final linkedPlace = service.findLinkedPlace(
      Uri.parse(
        'https://njlahetbl.github.io/TMaps/?place=old%3Akey&lat=45.015&lng=78.39',
      ),
      [nearby],
    );

    expect(linkedPlace, same(nearby));
  });
}
