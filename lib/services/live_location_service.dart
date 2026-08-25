import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum LocationAccessState {
  ready,
  permissionNeeded,
  deniedForever,
  servicesDisabled,
  unavailable,
}

class LocationStartResult {
  const LocationStartResult(this.state, {this.position});

  final LocationAccessState state;
  final Position? position;
}

class LiveLocationService {
  final _positions = StreamController<Position>.broadcast(sync: true);
  StreamSubscription<Position>? _subscription;

  Stream<Position> get positions => _positions.stream;

  Future<LocationStartResult> start({required bool requestPermission}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationStartResult(LocationAccessState.servicesDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if ((permission == LocationPermission.denied ||
              permission == LocationPermission.unableToDetermine) &&
          requestPermission) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationStartResult(LocationAccessState.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return const LocationStartResult(LocationAccessState.permissionNeeded);
      }

      Position? firstPosition;
      if (!kIsWeb) {
        try {
          firstPosition = await Geolocator.getLastKnownPosition();
        } on Object catch (error) {
          debugPrint('Last known location unavailable: $error');
        }
      }
      try {
        firstPosition = await Geolocator.getCurrentPosition(
          locationSettings: _currentLocationSettings(),
        );
      } on TimeoutException {
        // A last-known fix is useful while the live stream warms up.
      }

      await _subscription?.cancel();
      _subscription =
          Geolocator.getPositionStream(
            locationSettings: _streamLocationSettings(),
          ).listen(
            _positions.add,
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Live location stream error: $error');
            },
          );

      return LocationStartResult(
        LocationAccessState.ready,
        position: firstPosition,
      );
    } on Object catch (error) {
      debugPrint('Location startup error: $error');
      return const LocationStartResult(LocationAccessState.unavailable);
    }
  }

  LocationSettings _currentLocationSettings() {
    if (kIsWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        maximumAge: const Duration(seconds: 30),
        timeLimit: const Duration(seconds: 20),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 20),
    );
  }

  LocationSettings _streamLocationSettings() {
    if (kIsWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        maximumAge: Duration.zero,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _positions.close();
  }
}
