import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/weather_snapshot.dart';
import 'package:tmaps/services/weather_service.dart';

void main() {
  test('loads current weather for the map center', () async {
    final service = WeatherService(
      client: MockClient((request) async {
        expect(request.url.host, 'api.open-meteo.com');
        expect(request.url.queryParameters['forecast_days'], '1');
        expect(request.url.queryParameters['timezone'], 'auto');
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 18.4,
              'apparent_temperature': 17.2,
              'precipitation': 0,
              'weather_code': 2,
              'wind_speed_10m': 11.5,
            },
            'daily': {
              'temperature_2m_max': [23.1],
              'temperature_2m_min': [10.2],
              'precipitation_probability_max': [15],
            },
          }),
          200,
        );
      }),
    );

    final weather = await service.fetch(const LatLng(45.0156, 78.3731));

    expect(weather.cityName, 'Талдыкорган');
    expect(weather.temperature, 18.4);
    expect(weather.condition, 'Переменная облачность');
    expect(weather.precipitationProbability, 15);
  });

  test('uses the nearest known Kazakhstan city name', () {
    expect(WeatherService.cityNameFor(const LatLng(51.16, 71.45)), 'Астана');
    expect(WeatherService.cityNameFor(const LatLng(43.24, 76.90)), 'Алматы');
  });

  test('describes pedestrian risks for rain, snow and fog', () {
    WeatherSnapshot snapshot(int weatherCode) => WeatherSnapshot(
      position: const LatLng(45.0156, 78.3731),
      cityName: 'Талдыкорган',
      temperature: 10,
      apparentTemperature: 8,
      weatherCode: weatherCode,
      windSpeed: 6,
      precipitation: 1,
      minimumTemperature: 5,
      maximumTemperature: 12,
      precipitationProbability: 70,
      updatedAt: DateTime(2026, 8, 31),
    );

    expect(snapshot(61).isRainy, isTrue);
    expect(snapshot(61).pedestrianAdvice, contains('скользкими'));
    expect(snapshot(71).isSnowy, isTrue);
    expect(snapshot(71).pedestrianAdvice, contains('очищенный маршрут'));
    expect(snapshot(45).hasPedestrianWeatherWarning, isTrue);
    expect(snapshot(45).pedestrianAdvice, contains('видимость'));
    expect(snapshot(0).pedestrianAdvice, isNull);
  });
}
