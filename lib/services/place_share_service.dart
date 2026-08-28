import 'package:flutter/services.dart';

import '../core/app_config.dart';
import '../core/place_info.dart';

class PlaceShareService {
  const PlaceShareService();

  Uri buildLink(Map<String, dynamic> place) {
    return Uri.parse(AppConfig.publicAppUrl).replace(
      queryParameters: {
        'place': PlaceInfo.keyOf(place),
        'lat': (place['lat'] as num).toString(),
        'lng': (place['lng'] as num).toString(),
      },
    );
  }

  Future<Uri> copyLink(Map<String, dynamic> place) async {
    final link = buildLink(place);
    await Clipboard.setData(
      ClipboardData(
        text:
            '${PlaceInfo.titleOf(place)}\n'
            '${PlaceInfo.kindLabel(place)}\n'
            '$link',
      ),
    );
    return link;
  }

  Map<String, dynamic>? findLinkedPlace(
    Uri uri,
    Iterable<Map<String, dynamic>> places,
  ) {
    final placeKey = uri.queryParameters['place'];
    if (placeKey != null && placeKey.isNotEmpty) {
      for (final place in places) {
        if (PlaceInfo.keyOf(place) == placeKey) return place;
      }
    }

    final latitude = double.tryParse(uri.queryParameters['lat'] ?? '');
    final longitude = double.tryParse(uri.queryParameters['lng'] ?? '');
    if (latitude == null || longitude == null) return null;

    Map<String, dynamic>? nearest;
    var nearestSquaredDistance = double.infinity;
    for (final place in places) {
      final placeLatitude = (place['lat'] as num?)?.toDouble();
      final placeLongitude = (place['lng'] as num?)?.toDouble();
      if (placeLatitude == null || placeLongitude == null) continue;
      final latDelta = placeLatitude - latitude;
      final lngDelta = placeLongitude - longitude;
      final squaredDistance = latDelta * latDelta + lngDelta * lngDelta;
      if (squaredDistance < nearestSquaredDistance) {
        nearest = place;
        nearestSquaredDistance = squaredDistance;
      }
    }

    // Roughly 250 metres at Kazakhstan latitudes. Avoid opening an unrelated
    // place when a shared point has since been removed from the dataset.
    return nearestSquaredDistance <= 0.000009 ? nearest : null;
  }
}
