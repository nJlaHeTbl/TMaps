import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/place_info.dart';
import 'package:tmaps/core/place_submission_defaults.dart';

void main() {
  test('outdoor toilet preset has no paper or soap and no ready rating', () {
    const defaults = PlaceSubmissionDefaults.outdoorToilet;

    expect(defaults.rating, isNull);
    expect(defaults.condition, isNull);
    expect(defaults.isFree, isTrue);
    expect(defaults.hasPaper, isFalse);
    expect(defaults.hasSoap, isFalse);
  });

  test('no preset pre-fills a rating, a condition or a toilet price', () {
    for (final kind in PlaceKind.values) {
      final defaults = PlaceSubmissionDefaults.forKind(kind);
      expect(defaults.rating, isNull, reason: '$kind rating');
      expect(defaults.condition, isNull, reason: '$kind condition');
    }
    expect(
      PlaceSubmissionDefaults.forKind(PlaceKind.communityToilet).isFree,
      isNull,
    );
    expect(
      PlaceSubmissionDefaults.forKind(PlaceKind.publicToilet).isFree,
      isNull,
    );
  });

  test('venue presets use an appropriate access type', () {
    expect(
      PlaceSubmissionDefaults.forKind(PlaceKind.cafe).accessType,
      'customers',
    );
    expect(
      PlaceSubmissionDefaults.forKind(PlaceKind.organization).accessType,
      'destination',
    );
  });
}
