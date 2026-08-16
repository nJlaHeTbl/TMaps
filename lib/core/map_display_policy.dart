import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

abstract final class MapDisplayPolicy {
  static const double minPlaceZoom = 7.2;
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

    return _spreadAcrossBounds(
      candidates,
      bounds,
      _limitForZoom(zoom, maxMarkers),
    );
  }

  static int _limitForZoom(double zoom, int requestedLimit) {
    final adaptiveLimit = switch (zoom) {
      < 8.5 => 12,
      < 10.5 => 22,
      < 12.5 => 36,
      < 14.5 => 52,
      _ => requestedLimit,
    };
    return adaptiveLimit < requestedLimit ? adaptiveLimit : requestedLimit;
  }

  static List<Map<String, dynamic>> _spreadAcrossBounds(
    List<Map<String, dynamic>> candidates,
    LatLngBounds bounds,
    int limit,
  ) {
    if (candidates.length <= limit) return candidates;

    final latitudeSpan = math.max(
      (bounds.north - bounds.south).abs(),
      0.000001,
    );
    final longitudeSpan = math.max((bounds.east - bounds.west).abs(), 0.000001);
    final aspectRatio = longitudeSpan / latitudeSpan;
    final columns = math.sqrt(limit * aspectRatio).round().clamp(1, limit);
    final rows = (limit / columns).ceil();
    final buckets = <String, List<Map<String, dynamic>>>{};

    for (final place in candidates) {
      final latitude = (place['lat'] as num).toDouble();
      final longitude = (place['lng'] as num).toDouble();
      final row = (((latitude - bounds.south) / latitudeSpan) * rows)
          .floor()
          .clamp(0, rows - 1);
      final column = (((longitude - bounds.west) / longitudeSpan) * columns)
          .floor()
          .clamp(0, columns - 1);
      buckets.putIfAbsent('$row:$column', () => []).add(place);
    }

    final spread = <Map<String, dynamic>>[];
    for (var layer = 0; spread.length < limit; layer++) {
      var addedAny = false;
      for (final bucket in buckets.values) {
        if (layer >= bucket.length) continue;
        spread.add(bucket[layer]);
        addedAny = true;
        if (spread.length == limit) break;
      }
      if (!addedAny) break;
    }

    return spread;
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
