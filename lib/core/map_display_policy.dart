import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

abstract final class MapDisplayPolicy {
  static const double minPlaceZoom = 8.7;
  static const int maxVisibleMarkers = 90;

  static final kazakhstanBounds = LatLngBounds(
    const LatLng(40.45, 46.45),
    const LatLng(55.55, 87.40),
  );

  static bool canShowPlaces(double zoom) => zoom >= minPlaceZoom;

  static List<Map<String, dynamic>> placesInside(
    List<Map<String, dynamic>> places, {
    required double zoom,
    required LatLngBounds? bounds,
    int maxMarkers = maxVisibleMarkers,
  }) {
    if (!canShowPlaces(zoom) || bounds == null) return const [];

    final latitudePadding = (bounds.north - bounds.south).abs() * 0.18;
    final longitudePadding = (bounds.east - bounds.west).abs() * 0.18;
    final padded = LatLngBounds.unsafe(
      north: (bounds.north + latitudePadding).clamp(-90, 90).toDouble(),
      south: (bounds.south - latitudePadding).clamp(-90, 90).toDouble(),
      east: (bounds.east + longitudePadding).clamp(-180, 180).toDouble(),
      west: (bounds.west - longitudePadding).clamp(-180, 180).toDouble(),
    );

    final candidates = places
        .where((place) {
          final latitude = (place['lat'] as num?)?.toDouble();
          final longitude = (place['lng'] as num?)?.toDouble();
          if (latitude == null || longitude == null) return false;
          return padded.contains(LatLng(latitude, longitude));
        })
        .toList(growable: false);

    final centerLatitude = (bounds.north + bounds.south) / 2;
    final centerLongitude = (bounds.east + bounds.west) / 2;
    candidates.sort((first, second) {
      final priority = _priorityOf(first).compareTo(_priorityOf(second));
      if (priority != 0) return priority;

      return _distanceSquared(
        first,
        centerLatitude,
        centerLongitude,
      ).compareTo(_distanceSquared(second, centerLatitude, centerLongitude));
    });

    return candidates.take(maxMarkers).toList(growable: false);
  }

  static int _priorityOf(Map<String, dynamic> place) {
    final kind = place['place_kind']?.toString();
    if (kind == 'public_toilet' || kind == 'community_toilet') return 0;
    if (place['has_toilet'] == true) return 1;
    if (kind == 'phone_charging' || kind == 'ev_charging' || kind == 'fuel') {
      return 2;
    }
    final name = place['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return 3;
    return 4;
  }

  static double _distanceSquared(
    Map<String, dynamic> place,
    double centerLatitude,
    double centerLongitude,
  ) {
    final latitude = (place['lat'] as num).toDouble() - centerLatitude;
    final longitude = (place['lng'] as num).toDouble() - centerLongitude;
    return latitude * latitude + longitude * longitude;
  }
}
