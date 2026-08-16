import 'place_info.dart';

abstract final class PlaceVisibilityPolicy {
  static bool matches(
    Map<String, dynamic> place, {
    required PlaceKind? selectedCategory,
    required bool freeOnly,
    required bool wheelchairOnly,
    required bool communityOnly,
    required bool venueToilets,
    required bool phoneCharging,
    required bool evCharging,
  }) {
    final kind = PlaceInfo.kindOf(place);
    final hasToilet = PlaceInfo.hasToilet(place);

    // TMaps opens as a toilet map. Other useful categories are one tap away.
    if (selectedCategory == null && !hasToilet) return false;
    if (selectedCategory != null && kind != selectedCategory) return false;

    // Unnamed, unconfirmed food nodes are not useful enough to occupy the map.
    if (kind == PlaceKind.cafe && !hasToilet && !_hasUsefulName(place)) {
      return false;
    }

    if (freeOnly &&
        (!hasToilet ||
            place['fee_known'] == false ||
            place['is_free'] != true)) {
      return false;
    }

    final wheelchair = PlaceInfo.effectiveValue(place, 'wheelchair_accessible');
    if (wheelchairOnly && wheelchair != true && place['wheelchair'] != 'yes') {
      return false;
    }

    if (communityOnly && place['source'] == 'openstreetmap') return false;
    if (!venueToilets && PlaceInfo.isVenue(place)) return false;
    if (!phoneCharging && kind == PlaceKind.phoneCharging) return false;
    if (!evCharging && kind == PlaceKind.evCharging) return false;

    return true;
  }

  static bool _hasUsefulName(Map<String, dynamic> place) {
    final name = place['name']?.toString().trim();
    return name != null && name.isNotEmpty;
  }
}
