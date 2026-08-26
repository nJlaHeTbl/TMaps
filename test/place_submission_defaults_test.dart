import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/place_info.dart';
import 'package:tmaps/core/place_submission_defaults.dart';

void main() {
  test('outdoor toilet preset starts at three stars without paper', () {
    const defaults = PlaceSubmissionDefaults.outdoorToilet;

    expect(defaults.rating, 3);
    expect(defaults.condition, 'Плохое');
    expect(defaults.isFree, isTrue);
    expect(defaults.hasPaper, isFalse);
    expect(defaults.hasSoap, isFalse);
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
