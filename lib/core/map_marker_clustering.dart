import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PlaceMarkerGroup {
  const PlaceMarkerGroup({required this.places, required this.center});

  final List<Map<String, dynamic>> places;
  final LatLng center;

  bool get isCluster => places.length > 1;
}

abstract final class MapMarkerClustering {
  static const double maxClusterZoom = 15.2;

  static List<PlaceMarkerGroup> group(
    List<Map<String, dynamic>> places, {
    required LatLngBounds? bounds,
    required double viewportWidth,
    required double viewportHeight,
    required double zoom,
  }) {
    if (places.isEmpty || bounds == null) return const [];
    if (places.length == 1 ||
        zoom >= maxClusterZoom ||
        viewportWidth <= 0 ||
        viewportHeight <= 0) {
      return places.map(_single).toList(growable: false);
    }

    final latitudeSpan = math.max(
      (bounds.north - bounds.south).abs(),
      0.000001,
    );
    final longitudeSpan = math.max((bounds.east - bounds.west).abs(), 0.000001);
    final cellSize = switch (zoom) {
      < 12.5 => 82.0,
      < 13.8 => 68.0,
      _ => 56.0,
    };
    final columns = math.max(1, (viewportWidth / cellSize).ceil());
    final rows = math.max(1, (viewportHeight / cellSize).ceil());
    final buckets = <String, List<Map<String, dynamic>>>{};

    for (final place in places) {
      final latitude = (place['lat'] as num?)?.toDouble();
      final longitude = (place['lng'] as num?)?.toDouble();
      if (latitude == null || longitude == null) continue;

      final column = (((longitude - bounds.west) / longitudeSpan) * columns)
          .floor()
          .clamp(0, columns - 1);
      final row = (((bounds.north - latitude) / latitudeSpan) * rows)
          .floor()
          .clamp(0, rows - 1);
      buckets.putIfAbsent('$row:$column', () => []).add(place);
    }

    return buckets.values.map(_fromPlaces).toList(growable: false);
  }

  static PlaceMarkerGroup _single(Map<String, dynamic> place) {
    return PlaceMarkerGroup(
      places: [place],
      center: LatLng(
        (place['lat'] as num).toDouble(),
        (place['lng'] as num).toDouble(),
      ),
    );
  }

  static PlaceMarkerGroup _fromPlaces(List<Map<String, dynamic>> places) {
    var latitude = 0.0;
    var longitude = 0.0;
    for (final place in places) {
      latitude += (place['lat'] as num).toDouble();
      longitude += (place['lng'] as num).toDouble();
    }
    return PlaceMarkerGroup(
      places: List.unmodifiable(places),
      center: LatLng(latitude / places.length, longitude / places.length),
    );
  }
}
