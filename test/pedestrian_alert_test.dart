import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/pedestrian_alert.dart';

void main() {
  final now = DateTime.utc(2026, 8, 31, 10);

  PedestrianAlert alert({
    required int id,
    required LatLng position,
    required PedestrianAlertType type,
    Duration expiresIn = const Duration(hours: 1),
  }) {
    return PedestrianAlert(
      id: id,
      position: position,
      type: type,
      username: 'Мирас',
      description: null,
      createdAt: now.subtract(const Duration(minutes: 5)),
      expiresAt: now.add(expiresIn),
    );
  }

  test('parses an alert returned by the backend', () {
    final parsed = PedestrianAlert.fromJson({
      'id': 7,
      'lat': 45.0156,
      'lng': 78.3739,
      'alert_type': 'ice',
      'username': 'Мирас',
      'description': 'Скользко у моста',
      'created_at': '2026-08-31T09:00:00Z',
      'expires_at': '2026-08-31T21:00:00Z',
    });

    expect(parsed, isNotNull);
    expect(parsed!.type, PedestrianAlertType.ice);
    expect(parsed.description, 'Скользко у моста');
  });

  test('removes expired alerts', () {
    final alerts = PedestrianAlertPolicy.active([
      alert(
        id: 1,
        position: const LatLng(45, 78),
        type: PedestrianAlertType.snow,
      ),
      alert(
        id: 2,
        position: const LatLng(45, 78),
        type: PedestrianAlertType.ice,
        expiresIn: const Duration(minutes: -1),
      ),
    ], now: now);

    expect(alerts.map((item) => item.id), [1]);
  });

  test(
    'finds hazards near a walking route but ignores open and far reports',
    () {
      final route = [
        const LatLng(45.0150, 78.3730),
        const LatLng(45.0160, 78.3740),
      ];
      final alerts = PedestrianAlertPolicy.nearRoute([
        alert(
          id: 1,
          position: const LatLng(45.0155, 78.3735),
          type: PedestrianAlertType.ice,
        ),
        alert(
          id: 2,
          position: const LatLng(45.0155, 78.3735),
          type: PedestrianAlertType.open,
        ),
        alert(
          id: 3,
          position: const LatLng(45.0255, 78.3835),
          type: PedestrianAlertType.closed,
        ),
      ], route);

      expect(alerts.map((item) => item.id), [1]);
    },
  );
}
