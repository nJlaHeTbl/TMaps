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
        'water': PlaceKind.water,
      };

      for (final entry in categories.entries) {
        expect(PlaceInfo.kindOf({'place_kind': entry.key}), entry.value);
        expect(PlaceInfo.valueOfKind(entry.value), entry.key);
      }
    });

    test('water-only places are not treated as toilets', () {
      expect(
        PlaceInfo.hasToilet({'place_kind': 'water', 'has_toilet': false}),
        isFalse,
      );
      expect(
        PlaceInfo.waterTypeLabel({
          'place_kind': 'water',
          'water_type': 'vending_machine',
        }),
        'Автомат для набора воды',
      );
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

    test('uses stable keys for curated and pending places', () {
      expect(
        PlaceInfo.keyOf({'source': 'curated', 'source_id': '2gis/123'}),
        'curated:2gis/123',
      );
      expect(
        PlaceInfo.keyOf({'source': 'pending_submission', 'submission_id': 17}),
        'pending:17',
      );
    });

    test('labels a pending submission clearly', () {
      expect(
        PlaceInfo.kindLabel({
          'place_kind': 'community_toilet',
          'submission_status': 'pending',
        }),
        'Моя заявка · ожидает проверки',
      );
    });

    test('latest community report overrides imported amenities', () {
      final place = {
        'has_paper': false,
        'has_toilet': false,
        'place_kind': 'cafe',
        'latest_report': {
          'has_paper': true,
          'has_toilet': true,
          'access_type': 'customers',
        },
      };

      expect(PlaceInfo.effectiveValue(place, 'has_paper'), isTrue);
      expect(PlaceInfo.hasToilet(place), isTrue);
      expect(PlaceInfo.accessLabel(place), 'Для клиентов');
    });
  });
}
