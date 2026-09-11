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
  LiveLocationService({
    GeolocatorPlatform? platform,
    this.isWeb = kIsWeb,
    DateTime Function()? now,
  }) : _platform = platform ?? GeolocatorPlatform.instance,
       _now = now ?? DateTime.now;

  final GeolocatorPlatform _platform;
  final bool isWeb;
  final DateTime Function() _now;
  final _positions = StreamController<Position>.broadcast(sync: true);
  final _states = StreamController<LocationAccessState>.broadcast(sync: true);
  StreamSubscription<Position>? _subscription;
  Future<LocationStartResult>? _starting;
  bool _requestingPermission = false;
  bool _hasGrantedPermission = false;
  bool _disposed = false;
  int _watchGeneration = 0;
  Position? _lastPosition;
  LocationAccessState _state = LocationAccessState.permissionNeeded;

  Stream<Position> get positions => _positions.stream;
  Stream<LocationAccessState> get states => _states.stream;
  LocationAccessState get state => _state;

  Future<LocationStartResult> start({required bool requestPermission}) {
    if (_disposed) {
      return Future.value(
        const LocationStartResult(LocationAccessState.unavailable),
      );
    }
    final pending = _starting;
    if (pending != null) {
      // A tap during the passive startup check must still request consent,
      // but simultaneous explicit taps must share the same browser request.
      if (requestPermission && !_requestingPermission) {
        return pending.then(
          (result) => result.state == LocationAccessState.permissionNeeded
              ? start(requestPermission: true)
              : result,
        );
      }
      return pending;
    }

    _requestingPermission = requestPermission;
    late final Future<LocationStartResult> operation;
    operation = _start(requestPermission: requestPermission)
        .then((result) {
          if (_disposed) {
            return const LocationStartResult(LocationAccessState.unavailable);
          }
          // A watch can fail immediately after the first fix. Do not let the
          // startup result overwrite the more recent stream error in the UI.
          if (result.state == LocationAccessState.ready &&
              _state != LocationAccessState.ready) {
            return LocationStartResult(_state);
          }
          return result;
        })
        .whenComplete(() {
          if (identical(_starting, operation)) _starting = null;
        });
    _starting = operation;
    return operation;
  }

  Future<LocationStartResult> _start({required bool requestPermission}) async {
    try {
      if (!await _platform.isLocationServiceEnabled().timeout(
        const Duration(seconds: 5),
      )) {
        await _stopWatching();
        return _finish(LocationAccessState.servicesDisabled);
      }
      if (_disposed) return _finish(LocationAccessState.unavailable);

      var permission = await _checkPermission();
      if (_disposed) return _finish(LocationAccessState.unavailable);
      if (permission == LocationPermission.deniedForever) {
        _hasGrantedPermission = false;
        await _stopWatching();
        return _finish(LocationAccessState.deniedForever);
      }

      Position? firstPosition;
      final needsConsent =
          permission == LocationPermission.denied ||
          (permission == LocationPermission.unableToDetermine &&
              !(isWeb && _hasGrantedPermission));
      if (needsConsent) {
        _hasGrantedPermission = false;
        if (!requestPermission) {
          await _stopWatching();
          return _finish(LocationAccessState.permissionNeeded);
        }
        if (isWeb) {
          // Safari may have geolocation without the Permissions API.
          // Only an explicit user action starts the first browser prompt.
          firstPosition = await _currentPosition(_webFallbackSettings());
          permission = LocationPermission.whileInUse;
        } else {
          permission = await _platform.requestPermission().timeout(
            const Duration(seconds: 30),
          );
        }
      }
      if (_disposed) return _finish(LocationAccessState.unavailable);
      if (permission == LocationPermission.deniedForever) {
        await _stopWatching();
        return _finish(LocationAccessState.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          (permission == LocationPermission.unableToDetermine &&
              !(isWeb && _hasGrantedPermission))) {
        await _stopWatching();
        return _finish(LocationAccessState.permissionNeeded);
      }
      _hasGrantedPermission = true;

      firstPosition ??= await _readCurrentPosition();
      if (_disposed) return _finish(LocationAccessState.unavailable);

      final latest = _lastPosition;
      if (latest != null &&
          _isUsable(latest) &&
          (firstPosition == null ||
              latest.timestamp.isAfter(firstPosition.timestamp))) {
        firstPosition = latest;
      }
      if (firstPosition == null && !isWeb) {
        try {
          final cached = await _platform.getLastKnownPosition().timeout(
            const Duration(seconds: 3),
          );
          if (cached != null && _isUsable(cached)) firstPosition = cached;
        } on PermissionDeniedException {
          rethrow;
        } on LocationServiceDisabledException {
          rethrow;
        } on Object catch (error) {
          debugPrint('Last known location unavailable: $error');
        }
      }
      if (_disposed || firstPosition == null || !_isUsable(firstPosition)) {
        return _finish(LocationAccessState.unavailable);
      }

      // Keep the existing watch alive while acquiring a replacement fix.
      await _stopWatching();
      if (_disposed) return _finish(LocationAccessState.unavailable);
      _lastPosition = firstPosition;
      final generation = _watchGeneration;
      _subscription = _platform
          .getPositionStream(locationSettings: _streamLocationSettings())
          .listen(
            (position) {
              if (_disposed ||
                  generation != _watchGeneration ||
                  !_isUsable(position) ||
                  position.timestamp.isBefore(_lastPosition!.timestamp)) {
                return;
              }
              _lastPosition = position;
              _setState(LocationAccessState.ready);
              _positions.add(position);
            },
            onError: (Object error, StackTrace stackTrace) {
              if (_disposed || generation != _watchGeneration) return;
              final state = _errorState(error);
              _setState(state);
              if (state == LocationAccessState.deniedForever ||
                  state == LocationAccessState.permissionNeeded ||
                  state == LocationAccessState.servicesDisabled) {
                _hasGrantedPermission = false;
                unawaited(_stopWatching());
              }
            },
            onDone: () {
              if (_disposed || generation != _watchGeneration) return;
              _subscription = null;
              _setState(LocationAccessState.unavailable);
            },
          );
      return _finish(LocationAccessState.ready, position: _lastPosition);
    } on Object catch (error) {
      debugPrint('Location startup error: $error');
      final state = _errorState(error);
      if (state != LocationAccessState.unavailable) {
        _hasGrantedPermission = false;
        await _stopWatching();
      }
      return _finish(state);
    }
  }

  Future<LocationPermission> _checkPermission() async {
    try {
      return await _platform.checkPermission().timeout(
        const Duration(seconds: 5),
      );
    } on Object {
      if (!isWeb) rethrow;
      return LocationPermission.unableToDetermine;
    }
  }

  LocationAccessState _errorState(Object error) {
    if (error is PermissionDeniedException) {
      return isWeb
          ? LocationAccessState.deniedForever
          : LocationAccessState.permissionNeeded;
    }
    if (error is LocationServiceDisabledException) {
      return LocationAccessState.servicesDisabled;
    }
    return LocationAccessState.unavailable;
  }

  void _setState(LocationAccessState state) {
    if (_disposed || _state == state) return;
    _state = state;
    _states.add(state);
  }

  LocationStartResult _finish(LocationAccessState state, {Position? position}) {
    if (_disposed) {
      return const LocationStartResult(LocationAccessState.unavailable);
    }
    _setState(state);
    return LocationStartResult(state, position: position);
  }

  bool _isUsable(Position position) {
    final age = _now().difference(position.timestamp);
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.abs() <= 180 &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        age <= const Duration(minutes: 1) &&
        age >= const Duration(minutes: -1);
  }

  Future<Position?> _currentPosition(LocationSettings settings) async {
    // geolocator_web 4.1.4 passes microseconds to the browser's millisecond
    // timeout. Bound the Future independently; do not rely on that option.
    final position = await _platform
        .getCurrentPosition(locationSettings: settings)
        .timeout(settings.timeLimit ?? const Duration(seconds: 20));
    return !_disposed && _isUsable(position) ? position : null;
  }

  Future<Position?> _readCurrentPosition() async {
    try {
      final position = await _currentPosition(_currentLocationSettings());
      if (position != null) return position;
    } on PermissionDeniedException {
      rethrow;
    } on LocationServiceDisabledException {
      rethrow;
    } on Object catch (error) {
      debugPrint('Current location unavailable: $error');
    }
    if (isWeb && !_disposed) {
      try {
        return await _currentPosition(_webFallbackSettings());
      } on PermissionDeniedException {
        rethrow;
      } on LocationServiceDisabledException {
        rethrow;
      } on Object catch (error) {
        debugPrint('Fallback web location unavailable: $error');
      }
    }
    return null;
  }

  LocationSettings _currentLocationSettings() {
    if (isWeb) {
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
    if (isWeb) {
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

  WebSettings _webFallbackSettings() => WebSettings(
    accuracy: LocationAccuracy.medium,
    distanceFilter: 0,
    maximumAge: const Duration(seconds: 30),
    timeLimit: const Duration(seconds: 25),
  );

  Future<void> _stopWatching() async {
    _watchGeneration++;
    final previous = _subscription;
    _subscription = null;
    await previous?.cancel();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopWatching();
    await _positions.close();
    await _states.close();
  }
}
