import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/route_geometry.dart';
import 'route_service.dart';

enum WalkingRouteStatus {
  idle,
  locating,
  loading,
  ready,
  rerouting,
  offRoute,
  locationUnavailable,
  impreciseLocation,
  failed,
}

class WalkingRouteController extends ChangeNotifier {
  WalkingRouteController({required this.fetch, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Future<RouteResult> Function({required LatLng from, required LatLng to})
  fetch;
  final DateTime Function() _now;
  static const automaticRequestInterval = Duration(seconds: 30);
  static const maximumAccuracy = 50.0;

  RouteResult? _route;
  LatLng? _destination;
  LatLng? _lastPosition;
  LatLng? _routedFrom;
  DateTime? _lastFixAt;
  DateTime? _lastRequestAt;
  DateTime? _offRouteSince;
  double _accuracy = double.infinity;
  bool _locationAvailable = false;
  bool _loading = false;
  bool _failed = false;
  bool _offRoute = false;
  bool _disposed = false;
  int _generation = 0;
  Future<bool>? _activeRequest;
  Timer? _freshnessTimer;

  RouteResult? get route => _route;
  LatLng? get destination => _destination;
  bool get isLoading => _loading;

  bool get _freshFix =>
      _lastFixAt != null &&
      _now().difference(_lastFixAt!) <= const Duration(minutes: 1) &&
      _now().difference(_lastFixAt!) >= const Duration(minutes: -1);
  bool get _canTrack =>
      _locationAvailable &&
      _freshFix &&
      _accuracy.isFinite &&
      _accuracy >= 0 &&
      _accuracy <= maximumAccuracy;

  WalkingRouteStatus get status {
    if (_destination == null) return WalkingRouteStatus.idle;
    if (!_locationAvailable || !_freshFix) {
      return WalkingRouteStatus.locationUnavailable;
    }
    if (!_canTrack) return WalkingRouteStatus.impreciseLocation;
    if (_loading) {
      return _route == null
          ? WalkingRouteStatus.loading
          : WalkingRouteStatus.rerouting;
    }
    if (_failed) return WalkingRouteStatus.failed;
    if (_offRoute) return WalkingRouteStatus.offRoute;
    return WalkingRouteStatus.ready;
  }

  Future<bool> build({
    required LatLng from,
    required LatLng to,
    required double accuracy,
    DateTime? observedAt,
  }) {
    if (_disposed) return Future.value(false);
    _generation++;
    _loading = false;
    _activeRequest = null;
    _failed = false;
    _destination = to;
    _route = null;
    _routedFrom = null;
    _offRoute = false;
    _offRouteSince = null;
    _lastPosition = from;
    _lastFixAt = observedAt ?? _now();
    _accuracy = accuracy;
    _locationAvailable = true;
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_freshFix) setLocationAvailable(false);
    });
    if (!_canTrack) {
      notifyListeners();
      return Future.value(false);
    }
    return _request(from, to);
  }

  /// A cancelled route or a newly selected destination invalidates late replies.
  Future<bool> _request(LatLng from, LatLng to) {
    final generation = ++_generation;
    _loading = true;
    _failed = false;
    _lastRequestAt = _now();
    notifyListeners();
    return _activeRequest = _load(from, to, generation);
  }

  Future<bool> _load(LatLng from, LatLng to, int generation) async {
    try {
      final result = await fetch(
        from: from,
        to: to,
      ).timeout(const Duration(seconds: 20));
      if (_disposed || generation != _generation) return false;
      // Never mutate provider geometry to join it to a GPS fix through buildings.
      _route = RouteResult(
        points: List.unmodifiable(result.points),
        distance: result.distance,
        duration: result.duration,
      );
      _routedFrom = from;
      _offRouteSince = null;
      _offRoute =
          _lastPosition != null &&
          _canTrack &&
          distanceToWalkingRoute(_lastPosition!, _route!.points) >
              max(40, _accuracy * 2);
      return true;
    } catch (_) {
      if (!_disposed && generation == _generation) _failed = true;
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        _activeRequest = null;
        notifyListeners();
      }
    }
  }

  void setLocationAvailable(bool available) {
    if (_disposed || _locationAvailable == available) return;
    _locationAvailable = available;
    if (!available) _offRouteSince = null;
    if (_destination != null) notifyListeners();
  }

  void observePosition(
    LatLng point, {
    required double accuracy,
    required DateTime observedAt,
  }) {
    if (_disposed ||
        !point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180 ||
        !accuracy.isFinite ||
        accuracy < 0) {
      return;
    }
    final age = _now().difference(observedAt);
    if (age > const Duration(minutes: 1) ||
        age < const Duration(minutes: -1) ||
        (_lastFixAt != null && !observedAt.isAfter(_lastFixAt!))) {
      return;
    }

    final previousStatus = status;
    _lastPosition = point;
    _lastFixAt = observedAt;
    _accuracy = accuracy;
    _locationAvailable = true;
    final route = _route;
    if (!_canTrack || _loading) {
      _offRouteSince = null;
      if (_destination != null && status != previousStatus) notifyListeners();
      return;
    }
    if (route == null) {
      // A first coarse fix may become precise while the user is waiting.
      if (_destination != null && !_failed) {
        unawaited(_request(point, _destination!));
      } else if (_destination != null && status != previousStatus) {
        notifyListeners();
      }
      return;
    }

    _offRoute =
        distanceToWalkingRoute(point, route.points) > max(40, accuracy * 2);
    if (_offRoute) {
      _offRouteSince ??= observedAt;
    } else {
      _offRouteSince = null;
    }
    final stableDeviation =
        _offRouteSince != null &&
        observedAt.difference(_offRouteSince!) >= const Duration(seconds: 3);
    final progressed =
        !_offRoute &&
        _routedFrom != null &&
        const Distance()(_routedFrom!, point) >= 100;
    final cooledDown =
        _lastRequestAt == null ||
        _now().difference(_lastRequestAt!) >= automaticRequestInterval;

    // At most one automatic request per 30 s, even when the server fails.
    if (cooledDown && (stableDeviation || progressed)) {
      unawaited(_request(point, _destination!));
    } else if (status != previousStatus) {
      notifyListeners();
    }
  }

  Future<bool> retry() {
    if (_disposed ||
        _destination == null ||
        _lastPosition == null ||
        !_canTrack) {
      return Future.value(false);
    }
    if (_loading) return _activeRequest ?? Future.value(false);
    return _request(_lastPosition!, _destination!);
  }

  void clear() {
    if (_disposed) return;
    _freshnessTimer?.cancel();
    _generation++;
    _destination = null;
    _route = null;
    _routedFrom = null;
    _offRouteSince = null;
    _offRoute = false;
    _failed = false;
    _loading = false;
    _activeRequest = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _freshnessTimer?.cancel();
    _generation++;
    super.dispose();
  }
}
