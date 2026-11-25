import 'place_info.dart';

class PlaceSubmissionDefaults {
  const PlaceSubmissionDefaults({
    required this.accessType,
    this.isFree,
    this.rating,
    this.condition,
    this.hasPaper,
    this.hasSoap,
    this.wheelchairAccessible,
    this.phoneCharging,
  });

  /// Null means the person has not chosen yet. Ratings, condition and the
  /// price of a toilet are never pre-filled: a silent default would publish
  /// an opinion nobody gave.
  final bool? isFree;
  final int? rating;
  final String? condition;
  final String accessType;
  final bool? hasPaper;
  final bool? hasSoap;
  final bool? wheelchairAccessible;
  final bool? phoneCharging;

  static PlaceSubmissionDefaults forKind(PlaceKind kind) {
    return switch (kind) {
      PlaceKind.communityToilet || PlaceKind.publicToilet =>
        const PlaceSubmissionDefaults(accessType: 'public'),
      PlaceKind.cafe || PlaceKind.fuel => const PlaceSubmissionDefaults(
        isFree: true,
        accessType: 'customers',
      ),
      PlaceKind.organization => const PlaceSubmissionDefaults(
        isFree: true,
        accessType: 'destination',
      ),
      PlaceKind.phoneCharging => const PlaceSubmissionDefaults(
        isFree: true,
        accessType: 'public',
        phoneCharging: true,
      ),
      PlaceKind.evCharging || PlaceKind.water => const PlaceSubmissionDefaults(
        isFree: true,
        accessType: 'public',
      ),
    };
  }

  static const outdoorToilet = PlaceSubmissionDefaults(
    isFree: true,
    accessType: 'public',
    hasPaper: false,
    hasSoap: false,
    wheelchairAccessible: false,
    phoneCharging: false,
  );
}
