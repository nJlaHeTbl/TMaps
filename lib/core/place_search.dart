import 'package:latlong2/latlong.dart';

import 'place_info.dart';

class PlaceSearchResult {
  const PlaceSearchResult({required this.place, required this.distanceMeters});

  final Map<String, dynamic> place;
  final double distanceMeters;
}

abstract final class PlaceSearch {
  static const _aliases = <PlaceKind, String>{
    PlaceKind.publicToilet: 'туалет wc уборная санузел',
    PlaceKind.communityToilet:
        'туалет wc от людей сообщество добавили пользователи',
    PlaceKind.cafe: 'кафе еда ресторан кофе столовая',
    PlaceKind.fuel: 'азс заправка бензин топливо',
    PlaceKind.organization: 'место организация заведение магазин учреждение',
    PlaceKind.phoneCharging: 'телефон зарядка розетка usb',
    PlaceKind.evCharging: 'электро электромобиль зарядка авто ev',
  };

  static List<PlaceSearchResult> find(
    List<Map<String, dynamic>> places, {
    required String query,
    required LatLng origin,
    PlaceKind? category,
    int limit = 30,
  }) {
    final normalizedQuery = _normalize(query);
    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final scored =
        <({Map<String, dynamic> place, int relevance, double distance})>[];

    for (final place in places) {
      final kind = PlaceInfo.kindOf(place);
      if (category != null && kind != category) continue;

      final title = _normalize(place['name']?.toString() ?? '');
      final kindLabel = _normalize(PlaceInfo.kindLabel(place));
      final comment = _normalize(place['comment']?.toString() ?? '');
      final aliases = _aliases[kind] ?? '';
      final haystack = '$title $kindLabel $comment $aliases';
      if (tokens.isNotEmpty && !tokens.every(haystack.contains)) continue;

      final latitude = (place['lat'] as num?)?.toDouble();
      final longitude = (place['lng'] as num?)?.toDouble();
      if (latitude == null || longitude == null) continue;

      scored.add((
        place: place,
        relevance: _relevance(
          query: normalizedQuery,
          title: title,
          aliases: aliases,
          hasToilet: PlaceInfo.hasToilet(place),
        ),
        distance: const Distance().as(
          LengthUnit.Meter,
          origin,
          LatLng(latitude, longitude),
        ),
      ));
    }

    scored.sort((first, second) {
      final relevance = first.relevance.compareTo(second.relevance);
      if (relevance != 0) return relevance;
      return first.distance.compareTo(second.distance);
    });

    return scored
        .take(limit)
        .map(
          (entry) => PlaceSearchResult(
            place: entry.place,
            distanceMeters: entry.distance,
          ),
        )
        .toList(growable: false);
  }

  static int _relevance({
    required String query,
    required String title,
    required String aliases,
    required bool hasToilet,
  }) {
    if (query.isEmpty) return hasToilet ? 0 : 1;
    if (title == query) return 0;
    if (title.startsWith(query)) return 1;
    if (title.contains(query)) return 2;
    if (aliases.contains(query)) return 3;
    return 4;
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
