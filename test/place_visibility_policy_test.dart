import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/place_info.dart';
import 'package:tmaps/core/place_visibility_policy.dart';

bool matches(
  Map<String, dynamic> place, {
  PlaceKind? category,
  bool freeOnly = false,
}) {
  return PlaceVisibilityPolicy.matches(
    place,
    selectedCategory: category,
    freeOnly: freeOnly,
    wheelchairOnly: false,
    communityOnly: false,
    venueToilets: true,
    phoneCharging: true,
    evCharging: true,
  );
}

void main() {
  test('по умолчанию туалеты не теряются среди других мест', () {
    expect(
      matches({'place_kind': 'public_toilet', 'has_toilet': true}),
      isTrue,
    );
    expect(matches({'place_kind': 'fuel', 'has_toilet': true}), isTrue);
    expect(
      matches({'place_kind': 'cafe', 'has_toilet': false, 'name': 'Кафе'}),
      isFalse,
    );
    expect(
      matches({'place_kind': 'ev_charging', 'has_toilet': false}),
      isFalse,
    );
    expect(matches({'place_kind': 'water', 'has_toilet': false}), isFalse);
  });

  test('вода появляется только в своей категории', () {
    expect(
      matches({
        'place_kind': 'water',
        'has_toilet': false,
        'fee_known': true,
        'is_free': true,
      }, category: PlaceKind.water),
      isTrue,
    );
  });

  test('категория еды показывает именованные заведения', () {
    expect(
      matches({
        'place_kind': 'cafe',
        'has_toilet': false,
        'name': 'Бауырсак',
      }, category: PlaceKind.cafe),
      isTrue,
    );
    expect(
      matches({
        'place_kind': 'cafe',
        'has_toilet': false,
      }, category: PlaceKind.cafe),
      isFalse,
    );
  });

  test('фильтр бесплатных мест не пропускает неизвестную цену', () {
    expect(
      matches({
        'place_kind': 'public_toilet',
        'has_toilet': true,
        'fee_known': false,
        'is_free': true,
      }, freeOnly: true),
      isFalse,
    );
  });
}
