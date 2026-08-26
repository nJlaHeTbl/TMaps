import 'place_info.dart';

class PlaceSubmissionDefaults {
  const PlaceSubmissionDefaults({
    required this.isFree,
    required this.rating,
    required this.condition,
    required this.accessType,
    this.hasPaper,
    this.hasSoap,
    this.wheelchairAccessible,
    this.phoneCharging,
  });

  final bool isFree;
  final int rating;
  final String condition;
  final String accessType;
  final bool? hasPaper;
  final bool? hasSoap;
  final bool? wheelchairAccessible;
  final bool? phoneCharging;

  static PlaceSubmissionDefaults forKind(PlaceKind kind) {
    return switch (kind) {
      PlaceKind.communityToilet ||
      PlaceKind.publicToilet => const PlaceSubmissionDefaults(
        isFree: true,
        rating: 5,
        condition: 'Хорошее',
        accessType: 'public',
      ),
      PlaceKind.cafe || PlaceKind.fuel => const PlaceSubmissionDefaults(
        isFree: true,
        rating: 5,
        condition: 'Хорошее',
        accessType: 'customers',
      ),
      PlaceKind.organization => const PlaceSubmissionDefaults(
        isFree: true,
        rating: 5,
        condition: 'Хорошее',
        accessType: 'destination',
      ),
      PlaceKind.phoneCharging => const PlaceSubmissionDefaults(
        isFree: true,
        rating: 5,
        condition: 'Хорошее',
        accessType: 'public',
        phoneCharging: true,
      ),
      PlaceKind.evCharging || PlaceKind.water => const PlaceSubmissionDefaults(
        isFree: true,
        rating: 5,
        condition: 'Хорошее',
        accessType: 'public',
      ),
    };
  }

  static const outdoorToilet = PlaceSubmissionDefaults(
    isFree: true,
    rating: 3,
    condition: 'Плохое',
    accessType: 'public',
    hasPaper: false,
    hasSoap: false,
    wheelchairAccessible: false,
    phoneCharging: false,
  );
}
