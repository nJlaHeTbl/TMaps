import 'package:latlong2/latlong.dart';

import 'place_info.dart';

enum QuickNeedKind { toilet, drinkingWater, phoneCharging }

class QuickNeedResult {
  const QuickNeedResult({
    required this.kind,
    required this.place,
    required this.distanceMeters,
  });

  final QuickNeedKind kind;
  final Map<String, dynamic> place;
  final double distanceMeters;
}

abstract final class QuickNeedFinder {
  static const Distance _distance = Distance();

  static List<QuickNeedResult> findNearest({
    required Iterable<Map<String, dynamic>> places,
    required LatLng origin,
  }) {
    final confirmedPlaces = places
        .where((place) => place['submission_status'] == null)
        .toList(growable: false);

    return QuickNeedKind.values
        .map(
          (kind) => _nearestForKind(
            kind: kind,
            places: confirmedPlaces,
            origin: origin,
          ),
        )
        .whereType<QuickNeedResult>()
        .toList(growable: false);
  }

  static QuickNeedResult? _nearestForKind({
    required QuickNeedKind kind,
    required Iterable<Map<String, dynamic>> places,
    required LatLng origin,
  }) {
    QuickNeedResult? nearest;

    for (final place in places) {
      if (!_matches(kind, place)) continue;
      final latitude = (place['lat'] as num?)?.toDouble();
      final longitude = (place['lng'] as num?)?.toDouble();
      if (latitude == null || longitude == null) continue;

      final distanceMeters = _distance.as(
        LengthUnit.Meter,
        origin,
        LatLng(latitude, longitude),
      );
      if (nearest == null || distanceMeters < nearest.distanceMeters) {
        nearest = QuickNeedResult(
          kind: kind,
          place: place,
          distanceMeters: distanceMeters,
        );
      }
    }

    return nearest;
  }

  static bool _matches(QuickNeedKind kind, Map<String, dynamic> place) {
    return switch (kind) {
      QuickNeedKind.toilet => PlaceInfo.hasToilet(place),
      QuickNeedKind.drinkingWater =>
        PlaceInfo.kindOf(place) == PlaceKind.water &&
            PlaceInfo.drinkingWater(place) == true,
      QuickNeedKind.phoneCharging =>
        PlaceInfo.kindOf(place) == PlaceKind.phoneCharging ||
            PlaceInfo.effectiveValue(place, 'phone_charging') == true,
    };
  }
}
