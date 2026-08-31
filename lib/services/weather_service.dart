import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/weather_snapshot.dart';

class WeatherService {
  WeatherService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<WeatherSnapshot> fetch(LatLng position) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': position.latitude.toStringAsFixed(4),
      'longitude': position.longitude.toStringAsFixed(4),
      'current':
          'temperature_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m',
      'daily':
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    http.Response? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) break;
      if (response.statusCode < 500 && response.statusCode != 429) break;
      if (attempt == 0) await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (response == null || response.statusCode != 200) {
      throw Exception('Погода временно недоступна');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>?;
    final daily = data['daily'] as Map<String, dynamic>?;
    if (current == null || daily == null) {
      throw const FormatException('Неполные данные погоды');
    }

    return WeatherSnapshot(
      position: position,
      cityName: cityNameFor(position),
      temperature: _number(current['temperature_2m']),
      apparentTemperature: _number(current['apparent_temperature']),
      weatherCode: _number(current['weather_code']).round(),
      windSpeed: _number(current['wind_speed_10m']),
      precipitation: _number(current['precipitation']),
      minimumTemperature: _firstNumber(daily['temperature_2m_min']),
      maximumTemperature: _firstNumber(daily['temperature_2m_max']),
      precipitationProbability: _firstNumber(
        daily['precipitation_probability_max'],
      ).round(),
      updatedAt: DateTime.now(),
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    throw const FormatException('Неверные данные погоды');
  }

  static double _firstNumber(dynamic value) {
    if (value is List && value.isNotEmpty) return _number(value.first);
    throw const FormatException('Неверный прогноз погоды');
  }

  static String cityNameFor(LatLng position) {
    const distance = Distance();
    var nearestName = 'Погода на карте';
    var nearestMeters = double.infinity;
    for (final city in _kazakhstanCities) {
      final meters = distance(position, city.position);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestName = city.name;
      }
    }
    return nearestMeters <= 90000 ? nearestName : 'Погода на карте';
  }
}

class _WeatherCity {
  const _WeatherCity(this.name, this.position);

  final String name;
  final LatLng position;
}

const _kazakhstanCities = <_WeatherCity>[
  _WeatherCity('Астана', LatLng(51.1694, 71.4491)),
  _WeatherCity('Алматы', LatLng(43.2389, 76.8897)),
  _WeatherCity('Шымкент', LatLng(42.3155, 69.5869)),
  _WeatherCity('Талдыкорган', LatLng(45.0156, 78.3731)),
  _WeatherCity('Караганда', LatLng(49.8064, 73.0855)),
  _WeatherCity('Актобе', LatLng(50.2839, 57.1670)),
  _WeatherCity('Тараз', LatLng(42.9000, 71.3667)),
  _WeatherCity('Павлодар', LatLng(52.2873, 76.9674)),
  _WeatherCity('Өскемен', LatLng(49.9483, 82.6275)),
  _WeatherCity('Семей', LatLng(50.4111, 80.2275)),
  _WeatherCity('Атырау', LatLng(47.0945, 51.9238)),
  _WeatherCity('Костанай', LatLng(53.2144, 63.6246)),
  _WeatherCity('Кызылорда', LatLng(44.8488, 65.4823)),
  _WeatherCity('Уральск', LatLng(51.2278, 51.3865)),
  _WeatherCity('Петропавловск', LatLng(54.8753, 69.1628)),
  _WeatherCity('Туркистан', LatLng(43.2973, 68.2518)),
  _WeatherCity('Актау', LatLng(43.6532, 51.1975)),
  _WeatherCity('Кокшетау', LatLng(53.2836, 69.3778)),
  _WeatherCity('Жезказган', LatLng(47.8043, 67.7144)),
  _WeatherCity('Конаев', LatLng(43.8653, 77.0603)),
  _WeatherCity('Текели', LatLng(44.8308, 78.8239)),
  _WeatherCity('Экибастуз', LatLng(51.7237, 75.3229)),
  _WeatherCity('Темиртау', LatLng(50.0549, 72.9646)),
  _WeatherCity('Рудный', LatLng(52.9729, 63.1168)),
  _WeatherCity('Байконур', LatLng(45.6167, 63.3167)),
];
