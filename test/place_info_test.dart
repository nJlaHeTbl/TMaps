import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/place_info.dart';

void main() {
  group('PlaceInfo', () {
    test('maps every supported category', () {
      const categories = {
        'public_toilet': PlaceKind.publicToilet,
        'community_toilet': PlaceKind.communityToilet,
        'cafe': PlaceKind.cafe,
        'fuel': PlaceKind.fuel,
        'organization': PlaceKind.organization,
        'phone_charging': PlaceKind.phoneCharging,
        'ev_charging': PlaceKind.evCharging,
      };

      for (final entry in categories.entries) {
        expect(PlaceInfo.kindOf({'place_kind': entry.key}), entry.value);
        expect(PlaceInfo.valueOfKind(entry.value), entry.key);
      }
    });

    test('charging-only places are not treated as toilets', () {
      expect(
        PlaceInfo.hasToilet({
          'place_kind': 'phone_charging',
          'has_toilet': false,
        }),
        isFalse,
      );
      expect(
        PlaceInfo.hasToilet({'place_kind': 'ev_charging', 'has_toilet': false}),
        isFalse,
      );
    });

    test('latest community report overrides imported amenities', () {
      final place = {
        'has_paper': false,
        'latest_report': {'has_paper': true, 'access_type': 'customers'},
      };

      expect(PlaceInfo.effectiveValue(place, 'has_paper'), isTrue);
      expect(PlaceInfo.accessLabel(place), 'Для клиентов');
    });
  });
}
