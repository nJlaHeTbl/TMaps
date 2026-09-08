import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/weather_snapshot.dart';

/// Keeps weather tied to the latest map position, even when requests finish
/// out of order.
class WeatherController extends ChangeNotifier {
  WeatherController({
    required this.fetch,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<WeatherSnapshot> Function(LatLng) fetch;
  final DateTime Function() _now;

  WeatherSnapshot? _weather;
  WeatherSnapshot? _cachedWeather;
  LatLng? _activePosition;
  Future<void>? _activeRequest;
  int _generation = 0;
  bool _disposed = false;
  bool _isLoading = false;
  bool _hasError = false;

  WeatherSnapshot? get weather => _weather;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;

  Future<void> load(LatLng position, {bool force = false}) {
    if (_disposed) return Future<void>.value();
    if (!force && _isLoading && _activePosition == position) {
      return _activeRequest ?? Future<void>.value();
    }

    final generation = ++_generation;
    final cached = _cachedWeather;
    final nearby =
        cached != null && const Distance()(cached.position, position) < 15000;
    final age = cached == null ? null : _now().difference(cached.updatedAt);
    final fresh =
        age != null && !age.isNegative && age < const Duration(minutes: 15);
    if (!force && nearby && fresh) {
      _weather = cached;
      _isLoading = false;
      _hasError = false;
      _activePosition = null;
      _activeRequest = null;
      notifyListeners();
      return Future<void>.value();
    }

    // Do not show another city's weather or rain animation during a new load.
    _weather = nearby ? cached : null;
    _isLoading = true;
    _hasError = false;
    _activePosition = position;
    notifyListeners();
    return _activeRequest = _load(position, generation);
  }

  Future<void> _load(LatLng position, int generation) async {
    try {
      final result = await fetch(position);
      if (_disposed || generation != _generation) return;
      _weather = result;
      _cachedWeather = result;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _hasError = true;
    } finally {
      if (!_disposed && generation == _generation) {
        _isLoading = false;
        _activePosition = null;
        _activeRequest = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
