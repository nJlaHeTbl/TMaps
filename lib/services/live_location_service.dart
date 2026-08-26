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
  const LocationStartResult(this.state, {this.position})
    : assert(
        state != LocationAccessState.ready || position != null,
        'A ready location result must contain a position',
      );

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

      Position? firstPosition;
      var permission = await Geolocator.checkPermission();
      if ((permission == LocationPermission.denied ||
              permission == LocationPermission.unableToDetermine) &&
          requestPermission) {
        if (kIsWeb) {
          firstPosition = await _requestWebPosition();
          if (firstPosition != null) {
            permission = LocationPermission.whileInUse;
          } else {
            permission = await Geolocator.checkPermission();
          }
        } else {
          permission = await Geolocator.requestPermission();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationStartResult(LocationAccessState.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return const LocationStartResult(LocationAccessState.permissionNeeded);
      }

      await _subscription?.cancel();

      Position? lastKnownPosition;
      if (!kIsWeb) {
        try {
          lastKnownPosition = await Geolocator.getLastKnownPosition();
        } on Object catch (error) {
          debugPrint('Last known location unavailable: $error');
        }
      }
      firstPosition ??= await _readCurrentPosition();
      firstPosition ??= lastKnownPosition;

      if (firstPosition == null) {
        return const LocationStartResult(LocationAccessState.unavailable);
      }

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

  Future<Position?> _requestWebPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _webFallbackSettings(),
      );
    } on TimeoutException {
      debugPrint('Web permission location request timed out');
    } on Object catch (error) {
      debugPrint('Web permission location request unavailable: $error');
    }
    return null;
  }

  Future<Position?> _readCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _currentLocationSettings(),
      );
    } on TimeoutException {
      debugPrint('Current location request timed out');
    } on Object catch (error) {
      debugPrint('Current location unavailable: $error');
    }

    if (kIsWeb) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: _webFallbackSettings(),
        );
      } on TimeoutException {
        debugPrint('Fallback web location request timed out');
      } on Object catch (error) {
        debugPrint('Fallback web location unavailable: $error');
      }
    }
    return null;
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

  WebSettings _webFallbackSettings() {
    return WebSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 0,
      maximumAge: Duration(minutes: 5),
      timeLimit: Duration(seconds: 25),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _positions.close();
  }
}
