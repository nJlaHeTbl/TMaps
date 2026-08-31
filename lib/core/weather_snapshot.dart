import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.position,
    required this.cityName,
    required this.temperature,
    required this.apparentTemperature,
    required this.weatherCode,
    required this.windSpeed,
    required this.precipitation,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.precipitationProbability,
    required this.updatedAt,
  });

  final LatLng position;
  final String cityName;
  final double temperature;
  final double apparentTemperature;
  final int weatherCode;
  final double windSpeed;
  final double precipitation;
  final double minimumTemperature;
  final double maximumTemperature;
  final int precipitationProbability;
  final DateTime updatedAt;

  String get condition => switch (weatherCode) {
    0 => 'Ясно',
    1 || 2 => 'Переменная облачность',
    3 => 'Пасмурно',
    45 || 48 => 'Туман',
    51 || 53 || 55 || 56 || 57 => 'Морось',
    61 || 63 || 65 || 66 || 67 => 'Дождь',
    71 || 73 || 75 || 77 => 'Снег',
    80 || 81 || 82 => 'Ливень',
    85 || 86 => 'Снегопад',
    95 || 96 || 99 => 'Гроза',
    _ => 'Погода рядом',
  };

  IconData get icon => switch (weatherCode) {
    0 => Icons.wb_sunny_rounded,
    1 || 2 => Icons.wb_cloudy_rounded,
    3 => Icons.cloud_rounded,
    45 || 48 => Icons.foggy,
    51 || 53 || 55 || 56 || 57 => Icons.grain_rounded,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => Icons.water_drop_rounded,
    71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit_rounded,
    95 || 96 || 99 => Icons.thunderstorm_rounded,
    _ => Icons.cloud_queue_rounded,
  };

  Color get color => switch (weatherCode) {
    0 => const Color(0xFFF59E0B),
    71 || 73 || 75 || 77 || 85 || 86 => const Color(0xFF2563EB),
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => const Color(0xFF0284C7),
    95 || 96 || 99 => const Color(0xFF7C3AED),
    _ => const Color(0xFF0891B2),
  };

  bool get isRainy => const {
    51,
    53,
    55,
    56,
    57,
    61,
    63,
    65,
    66,
    67,
    80,
    81,
    82,
    95,
    96,
    99,
  }.contains(weatherCode);

  bool get isSnowy => const {71, 73, 75, 77, 85, 86}.contains(weatherCode);

  bool get hasPedestrianWeatherWarning =>
      isRainy || isSnowy || weatherCode == 45 || weatherCode == 48;

  String? get pedestrianAdvice {
    if (isSnowy) {
      return 'Пешеходам: возможны снег и скользкие тропинки — выбирай очищенный маршрут.';
    }
    if (isRainy) {
      return 'Пешеходам: тропинки могут быть мокрыми и скользкими — иди осторожно.';
    }
    if (weatherCode == 45 || weatherCode == 48) {
      return 'Пешеходам: видимость снижена — переходи дороги особенно внимательно.';
    }
    return null;
  }
}
