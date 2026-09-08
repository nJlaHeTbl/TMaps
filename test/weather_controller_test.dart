import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/weather_snapshot.dart';
import 'package:tmaps/services/weather_controller.dart';

const taldykorgan = LatLng(45.0156, 78.3731);
const astana = LatLng(51.1694, 71.4491);
final observedAt = DateTime(2026, 9, 8, 14);

WeatherSnapshot snapshot(LatLng position, {double temperature = 18}) =>
    WeatherSnapshot(
      position: position,
      cityName: position == astana ? 'Астана' : 'Талдыкорган',
      temperature: temperature,
      apparentTemperature: temperature,
      weatherCode: 61,
      windSpeed: 8,
      precipitation: 1,
      minimumTemperature: 10,
      maximumTemperature: 20,
      precipitationProbability: 70,
      updatedAt: observedAt,
    );

void main() {
  test('a slow previous city cannot replace the latest map weather', () async {
    final first = Completer<WeatherSnapshot>();
    final second = Completer<WeatherSnapshot>();
    final controller = WeatherController(
      fetch: (position) =>
          position == taldykorgan ? first.future : second.future,
      now: () => observedAt,
    );
    addTearDown(controller.dispose);

    final firstLoad = controller.load(taldykorgan);
    final secondLoad = controller.load(astana);
    second.complete(snapshot(astana));
    await secondLoad;
    expect(controller.weather!.cityName, 'Астана');
    first.complete(snapshot(taldykorgan));
    await firstLoad;
    expect(controller.weather!.cityName, 'Астана');
    expect(controller.isLoading, isFalse);
  });

  test('old weather is hidden while loading another city', () async {
    final next = Completer<WeatherSnapshot>();
    final controller = WeatherController(
      fetch: (position) async =>
          position == taldykorgan ? snapshot(taldykorgan) : next.future,
      now: () => observedAt,
    );
    addTearDown(controller.dispose);
    await controller.load(taldykorgan);
    final loading = controller.load(astana);
    expect(controller.weather, isNull);
    expect(controller.isLoading, isTrue);
    next.complete(snapshot(astana));
    await loading;
    expect(controller.weather!.position, astana);
  });

  test(
    'returning to cached city invalidates a pending other-city request',
    () async {
      final next = Completer<WeatherSnapshot>();
      var calls = 0;
      final controller = WeatherController(
        fetch: (position) async {
          calls++;
          return position == taldykorgan ? snapshot(taldykorgan) : next.future;
        },
        now: () => observedAt,
      );
      addTearDown(controller.dispose);
      await controller.load(taldykorgan);
      final loading = controller.load(astana);
      await controller.load(taldykorgan);
      expect(controller.weather!.position, taldykorgan);
      expect(controller.isLoading, isFalse);
      next.complete(snapshot(astana));
      await loading;
      expect(controller.weather!.position, taldykorgan);
      expect(calls, 2);
    },
  );

  test(
    'failure for the current city is not hidden by an older result',
    () async {
      final first = Completer<WeatherSnapshot>();
      final second = Completer<WeatherSnapshot>();
      final controller = WeatherController(
        fetch: (position) =>
            position == taldykorgan ? first.future : second.future,
        now: () => observedAt,
      );
      addTearDown(controller.dispose);
      final firstLoad = controller.load(taldykorgan);
      final secondLoad = controller.load(astana);
      second.completeError(Exception('offline'));
      await secondLoad;
      first.complete(snapshot(taldykorgan));
      await firstLoad;
      expect(controller.hasError, isTrue);
      expect(controller.weather, isNull);
      expect(controller.isLoading, isFalse);
    },
  );

  test('duplicate position shares its in-flight request', () async {
    final response = Completer<WeatherSnapshot>();
    var calls = 0;
    final controller = WeatherController(
      fetch: (_) {
        calls++;
        return response.future;
      },
    );
    addTearDown(controller.dispose);
    final first = controller.load(taldykorgan);
    final repeated = controller.load(taldykorgan);
    expect(identical(first, repeated), isTrue);
    expect(calls, 1);
    response.complete(snapshot(taldykorgan));
    await Future.wait([first, repeated]);
  });

  test(
    'manual refresh bypasses cache and notifies open weather views',
    () async {
      var calls = 0;
      final controller = WeatherController(
        fetch: (_) async =>
            snapshot(taldykorgan, temperature: 18 + calls++ * 1.0),
        now: () => observedAt,
      );
      addTearDown(controller.dispose);
      final visibleTemperatures = <double?>[];
      controller.addListener(() {
        visibleTemperatures.add(controller.weather?.temperature);
      });
      await controller.load(taldykorgan);
      await controller.load(taldykorgan);
      expect(calls, 1);
      await controller.load(taldykorgan, force: true);
      expect(calls, 2);
      expect(controller.weather!.temperature, 19);
      expect(visibleTemperatures.last, 19);
    },
  );

  test('expired weather is fetched again', () async {
    var now = observedAt;
    var calls = 0;
    final controller = WeatherController(
      fetch: (_) async {
        calls++;
        return snapshot(taldykorgan);
      },
      now: () => now,
    );
    addTearDown(controller.dispose);
    await controller.load(taldykorgan);
    now = now.add(const Duration(minutes: 16));
    await controller.load(taldykorgan);
    expect(calls, 2);
  });

  test(
    'a response arriving after disposal does not notify listeners',
    () async {
      final response = Completer<WeatherSnapshot>();
      final controller = WeatherController(fetch: (_) => response.future);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final loading = controller.load(taldykorgan);
      controller.dispose();
      response.complete(snapshot(taldykorgan));
      await loading;
      expect(notifications, 1);
    },
  );
}
