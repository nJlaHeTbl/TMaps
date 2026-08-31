import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum PedestrianAlertType {
  open,
  closed,
  ice,
  construction,
  snow,
  flooding,
  obstacle,
}

extension PedestrianAlertTypeInfo on PedestrianAlertType {
  static PedestrianAlertType? fromValue(String? value) {
    return switch (value) {
      'open' => PedestrianAlertType.open,
      'closed' => PedestrianAlertType.closed,
      'ice' => PedestrianAlertType.ice,
      'construction' => PedestrianAlertType.construction,
      'snow' => PedestrianAlertType.snow,
      'flooding' => PedestrianAlertType.flooding,
      'obstacle' => PedestrianAlertType.obstacle,
      _ => null,
    };
  }

  String get value => name;

  String get label => switch (this) {
    PedestrianAlertType.open => 'Проход открыт',
    PedestrianAlertType.closed => 'Проход закрыт',
    PedestrianAlertType.ice => 'Гололёд',
    PedestrianAlertType.construction => 'Ремонтные работы',
    PedestrianAlertType.snow => 'Снег или не расчищено',
    PedestrianAlertType.flooding => 'Вода или подтопление',
    PedestrianAlertType.obstacle => 'Препятствие на пути',
  };

  String get description => switch (this) {
    PedestrianAlertType.open => 'Участок проверен — пройти можно',
    PedestrianAlertType.closed => 'Пешеходный проход временно недоступен',
    PedestrianAlertType.ice => 'Скользкий участок — иди осторожно',
    PedestrianAlertType.construction => 'На пути идут ремонтные работы',
    PedestrianAlertType.snow => 'Тропинка занесена или плохо расчищена',
    PedestrianAlertType.flooding => 'Проход затоплен или покрыт водой',
    PedestrianAlertType.obstacle => 'На тропинке есть помеха для прохода',
  };

  IconData get icon => switch (this) {
    PedestrianAlertType.open => Icons.check_circle_rounded,
    PedestrianAlertType.closed => Icons.block_rounded,
    PedestrianAlertType.ice => Icons.ac_unit_rounded,
    PedestrianAlertType.construction => Icons.construction_rounded,
    PedestrianAlertType.snow => Icons.cloudy_snowing,
    PedestrianAlertType.flooding => Icons.flood_rounded,
    PedestrianAlertType.obstacle => Icons.warning_amber_rounded,
  };

  Color get color => switch (this) {
    PedestrianAlertType.open => const Color(0xFF16A34A),
    PedestrianAlertType.closed => const Color(0xFFDC2626),
    PedestrianAlertType.ice => const Color(0xFF0284C7),
    PedestrianAlertType.construction => const Color(0xFFF97316),
    PedestrianAlertType.snow => const Color(0xFF2563EB),
    PedestrianAlertType.flooding => const Color(0xFF0891B2),
    PedestrianAlertType.obstacle => const Color(0xFFD97706),
  };

  bool get blocksOrEndangersRoute => this != PedestrianAlertType.open;
}

class PedestrianAlert {
  const PedestrianAlert({
    required this.id,
    required this.position,
    required this.type,
    required this.username,
    required this.description,
    required this.createdAt,
    required this.expiresAt,
  });

  final int id;
  final LatLng position;
  final PedestrianAlertType type;
  final String username;
  final String? description;
  final DateTime createdAt;
  final DateTime expiresAt;

  static PedestrianAlert? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    final latitude = (json['lat'] as num?)?.toDouble();
    final longitude = (json['lng'] as num?)?.toDouble();
    final type = PedestrianAlertTypeInfo.fromValue(
      json['alert_type']?.toString(),
    );
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(json['expires_at']?.toString() ?? '');
    if (id == null ||
        latitude == null ||
        longitude == null ||
        type == null ||
        createdAt == null ||
        expiresAt == null) {
      return null;
    }

    return PedestrianAlert(
      id: id,
      position: LatLng(latitude, longitude),
      type: type,
      username: json['username']?.toString().trim().isNotEmpty == true
          ? json['username'].toString().trim()
          : 'Пользователь TMaps',
      description: json['description']?.toString().trim().isNotEmpty == true
          ? json['description'].toString().trim()
          : null,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

class PedestrianAlertDraft {
  const PedestrianAlertDraft({required this.type, this.description});

  final PedestrianAlertType type;
  final String? description;
}

abstract final class PedestrianAlertPolicy {
  static List<PedestrianAlert> active(
    Iterable<PedestrianAlert> alerts, {
    DateTime? now,
  }) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    return alerts
        .where((alert) => alert.expiresAt.toUtc().isAfter(currentTime))
        .toList(growable: false);
  }

  static List<PedestrianAlert> nearRoute(
    Iterable<PedestrianAlert> alerts,
    List<LatLng> route, {
    double thresholdMeters = 70,
  }) {
    if (route.length < 2) return const [];
    return alerts
        .where((alert) => alert.type.blocksOrEndangersRoute)
        .where(
          (alert) =>
              _distanceToRouteMeters(alert.position, route) <= thresholdMeters,
        )
        .toList(growable: false)
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  static double _distanceToRouteMeters(LatLng point, List<LatLng> route) {
    final latitudeRadians = point.latitude * pi / 180;
    final longitudeScale = 111320 * cos(latitudeRadians);
    const latitudeScale = 110540.0;
    var minimum = double.infinity;

    for (var index = 1; index < route.length; index++) {
      final start = route[index - 1];
      final end = route[index];
      final startX = (start.longitude - point.longitude) * longitudeScale;
      final startY = (start.latitude - point.latitude) * latitudeScale;
      final endX = (end.longitude - point.longitude) * longitudeScale;
      final endY = (end.latitude - point.latitude) * latitudeScale;
      final deltaX = endX - startX;
      final deltaY = endY - startY;
      final lengthSquared = deltaX * deltaX + deltaY * deltaY;
      final fraction = lengthSquared == 0
          ? 0.0
          : ((-startX * deltaX - startY * deltaY) / lengthSquared).clamp(
              0.0,
              1.0,
            );
      final closestX = startX + fraction * deltaX;
      final closestY = startY + fraction * deltaY;
      minimum = min(minimum, sqrt(closestX * closestX + closestY * closestY));
    }

    return minimum;
  }
}
