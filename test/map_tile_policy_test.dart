import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/map_tile_policy.dart';

void main() {
  test('satellite close zoom reuses the last reliable Kazakhstan tiles', () {
    expect(MapTilePolicy.satelliteMaxNativeZoom, 17);
    expect(
      MapTilePolicy.satelliteLabelsMaxNativeZoom,
      greaterThanOrEqualTo(MapTilePolicy.satelliteMaxNativeZoom),
    );
  });

  test('satellite has a second Esri host for network failures', () {
    expect(
      MapTilePolicy.satelliteFallbackUrl,
      isNot(MapTilePolicy.satelliteUrl),
    );
    expect(MapTilePolicy.keepBuffer, greaterThanOrEqualTo(2));
    expect(MapTilePolicy.panBuffer, greaterThanOrEqualTo(1));
  });
}
