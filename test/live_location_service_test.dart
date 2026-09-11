import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tmaps/services/live_location_service.dart';

final observedAt = DateTime.utc(2026, 9, 9, 12);

Position fix({DateTime? at, double latitude = 45.0156}) => Position(
  latitude: latitude,
  longitude: 78.3731,
  timestamp: at ?? observedAt,
  accuracy: 12,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakeLocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Future<LocationPermission> Function()? permissionCheck;
  Future<Position> Function(LocationSettings?)? read;
  Position? cached;
  int permissionRequests = 0;
  int cacheRequests = 0;
  int cancelledWatches = 0;
  final settings = <LocationSettings?>[];
  final watches = <StreamController<Position>>[];
  Stream<Position> Function()? watchOverride;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async =>
      permissionCheck == null ? permission : permissionCheck!();

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission = LocationPermission.whileInUse;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    settings.add(locationSettings);
    return read?.call(locationSettings) ?? Future.value(fix());
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    cacheRequests++;
    return cached;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    if (watchOverride != null) return watchOverride!();
    final controller = StreamController<Position>(
      sync: true,
      onCancel: () => cancelledWatches++,
    );
    watches.add(controller);
    return controller.stream;
  }

  Future<void> dispose() async {
    for (final watch in watches) {
      await watch.close();
    }
  }
}

LiveLocationService serviceFor(
  FakeLocationPlatform platform, {
  bool web = true,
}) {
  final service = LiveLocationService(
    platform: platform,
    isWeb: web,
    now: () => observedAt,
  );
  addTearDown(() async {
    await service.dispose();
    await platform.dispose();
  });
  return service;
}

void main() {
  test(
    'an empty watch updates state after startup instead of staying ready',
    () async {
      final platform = FakeLocationPlatform()
        ..watchOverride = () => const Stream<Position>.empty();
      final service = serviceFor(platform);
      await service.start(requestPermission: true);
      await Future<void>.delayed(Duration.zero);
      expect(service.state, LocationAccessState.unavailable);
    },
  );

  test(
    'a new watch permission error is visible after startup completes',
    () async {
      final platform = FakeLocationPlatform()
        ..watchOverride = () =>
            Stream<Position>.error(const PermissionDeniedException('revoked'));
      final service = serviceFor(platform);
      await service.start(requestPermission: true);
      await Future<void>.delayed(Duration.zero);
      expect(service.state, LocationAccessState.deniedForever);
    },
  );

  for (final permission in [
    LocationPermission.denied,
    LocationPermission.unableToDetermine,
    LocationPermission.deniedForever,
  ]) {
    test('passive startup does not prompt for $permission', () async {
      final platform = FakeLocationPlatform()..permission = permission;
      final service = serviceFor(platform);

      final result = await service.start(requestPermission: false);

      expect(
        result.state,
        permission == LocationPermission.deniedForever
            ? LocationAccessState.deniedForever
            : LocationAccessState.permissionNeeded,
      );
      expect(platform.permissionRequests, 0);
      expect(platform.settings, isEmpty);
      expect(platform.watches, isEmpty);
    });
  }

  test('simultaneous taps share the position request and one watch', () async {
    final position = Completer<Position>();
    final platform = FakeLocationPlatform()..read = (_) => position.future;
    final service = serviceFor(platform);

    final first = service.start(requestPermission: true);
    final second = service.start(requestPermission: true);
    expect(identical(first, second), isTrue);
    position.complete(fix());
    expect((await first).state, LocationAccessState.ready);
    expect((await second).position, fix());
    expect(platform.settings, hasLength(1));
    expect(platform.watches, hasLength(1));
  });

  test('a tap during passive checking still requests consent once', () async {
    final check = Completer<LocationPermission>();
    final platform = FakeLocationPlatform()
      ..permissionCheck = () => check.future;
    final service = serviceFor(platform);

    final passive = service.start(requestPermission: false);
    final firstTap = service.start(requestPermission: true);
    final secondTap = service.start(requestPermission: true);
    check.complete(LocationPermission.denied);

    expect((await passive).state, LocationAccessState.permissionNeeded);
    expect((await firstTap).state, LocationAccessState.ready);
    expect((await secondTap).state, LocationAccessState.ready);
    expect(platform.settings, hasLength(1));
    expect(platform.permissionRequests, 0); // Browser prompts via position API.
    expect(platform.watches, hasLength(1));
  });

  test('Safari without Permissions API can locate on tap and resume', () async {
    final platform = FakeLocationPlatform()
      ..permissionCheck = () =>
          Future.error(UnsupportedError('Permissions API'));
    final service = serviceFor(platform);

    expect(
      (await service.start(requestPermission: false)).state,
      LocationAccessState.permissionNeeded,
    );
    expect(platform.settings, isEmpty);
    expect(
      (await service.start(requestPermission: true)).state,
      LocationAccessState.ready,
    );
    expect(
      (await service.start(requestPermission: false)).state,
      LocationAccessState.ready,
    );
    expect(platform.watches, hasLength(2));
    expect(platform.cancelledWatches, 1);
    expect(platform.permissionRequests, 0);
  });

  testWidgets('a hung precise web request falls back after 20 seconds', (
    tester,
  ) async {
    final hung = Completer<Position>();
    final platform = FakeLocationPlatform()
      ..read = (settings) => settings!.accuracy == LocationAccuracy.medium
          ? Future.value(fix(latitude: 45.02))
          : hung.future;
    final service = serviceFor(platform);
    LocationStartResult? result;
    final pending = service
        .start(requestPermission: true)
        .then((value) => result = value);

    await tester.pump();
    await tester.pump(const Duration(seconds: 19));
    expect(platform.settings, hasLength(1));
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 1));
    await pending;
    expect(result!.state, LocationAccessState.ready);
    expect(result!.position!.latitude, 45.02);
    expect(platform.settings, hasLength(2));
    expect(
      (platform.settings.last! as WebSettings).maximumAge,
      const Duration(seconds: 30),
    );

    // A late result from the timed-out browser request cannot overwrite it.
    hung.complete(fix(latitude: 40));
    await tester.pump();
    expect(result!.position!.latitude, 45.02);
    expect(platform.watches, hasLength(1));
  });

  testWidgets('both hung requests end with an error, not hours of waiting', (
    tester,
  ) async {
    final hung = Completer<Position>();
    final platform = FakeLocationPlatform()..read = (_) => hung.future;
    final service = serviceFor(platform);
    LocationStartResult? result;
    final pending = service
        .start(requestPermission: true)
        .then((value) => result = value);

    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(platform.settings, hasLength(2));
    await tester.pump(const Duration(seconds: 25));
    await pending;
    expect(result!.state, LocationAccessState.unavailable);
    expect(platform.watches, isEmpty);
    hung.complete(fix());
    await tester.pump();
    expect(platform.watches, isEmpty);
  });

  test('temporary watch errors are visible and a new fix recovers', () async {
    final platform = FakeLocationPlatform();
    final service = serviceFor(platform);
    final states = <LocationAccessState>[];
    final positions = <Position>[];
    service.states.listen(states.add);
    service.positions.listen(positions.add);
    await service.start(requestPermission: true);

    platform.watches.single.addError(
      const PositionUpdateException('signal lost'),
    );
    expect(states.last, LocationAccessState.unavailable);
    platform.watches.single.add(fix(latitude: 45.02));

    expect(states, [
      LocationAccessState.ready,
      LocationAccessState.unavailable,
      LocationAccessState.ready,
    ]);
    expect(positions.single.latitude, 45.02);
  });

  test('ended watch reports unavailable and restarts on resume', () async {
    final platform = FakeLocationPlatform();
    final service = serviceFor(platform);
    final states = <LocationAccessState>[];
    service.states.listen(states.add);
    await service.start(requestPermission: true);
    await platform.watches.single.close();
    expect(states.last, LocationAccessState.unavailable);

    expect(
      (await service.start(requestPermission: false)).state,
      LocationAccessState.ready,
    );
    expect(platform.watches, hasLength(2));
    expect(states.last, LocationAccessState.ready);
  });

  test(
    'permission denial never falls back to a cached ready position',
    () async {
      final platform = FakeLocationPlatform()..cached = fix();
      final service = serviceFor(platform, web: false);
      await service.start(requestPermission: true);
      platform.read = (_) =>
          Future.error(const PermissionDeniedException('blocked'));

      final result = await service.start(requestPermission: true);
      expect(result.state, LocationAccessState.permissionNeeded);
      expect(result.position, isNull);
      expect(platform.cacheRequests, 0);
      expect(platform.watches, hasLength(1));
      expect(platform.cancelledWatches, 1);
    },
  );

  test('browser permission denial tells the UI access is blocked', () async {
    final platform = FakeLocationPlatform()
      ..permission = LocationPermission.denied
      ..read = (_) => Future.error(const PermissionDeniedException('blocked'));
    final service = serviceFor(platform);

    final result = await service.start(requestPermission: true);
    expect(result.state, LocationAccessState.deniedForever);
    expect(platform.settings, hasLength(1));
    expect(platform.watches, isEmpty);
  });

  test(
    'revoked browser permission stops tracking without another prompt',
    () async {
      final platform = FakeLocationPlatform();
      final service = serviceFor(platform);
      final states = <LocationAccessState>[];
      service.states.listen(states.add);
      await service.start(requestPermission: true);
      platform.watches.single.addError(
        const PermissionDeniedException('revoked'),
      );
      expect(states.last, LocationAccessState.deniedForever);
      expect(platform.cancelledWatches, 1);
      platform.permission = LocationPermission.denied;

      expect(
        (await service.start(requestPermission: false)).state,
        LocationAccessState.permissionNeeded,
      );
      expect(platform.settings, hasLength(1));
      expect(platform.permissionRequests, 0);
    },
  );

  test(
    'disabled location services are not shown as a generic signal error',
    () async {
      final platform = FakeLocationPlatform()
        ..read = (_) => Future.error(const LocationServiceDisabledException());
      final service = serviceFor(platform);
      expect(
        (await service.start(requestPermission: true)).state,
        LocationAccessState.servicesDisabled,
      );
      expect(platform.settings, hasLength(1));
    },
  );

  test('old native cache is rejected but a recent fix is usable', () async {
    final platform = FakeLocationPlatform()
      ..cached = fix(at: observedAt.subtract(const Duration(hours: 2)))
      ..read = (_) => Future.error(const PositionUpdateException('no signal'));
    final service = serviceFor(platform, web: false);
    expect(
      (await service.start(requestPermission: true)).state,
      LocationAccessState.unavailable,
    );
    expect(platform.watches, isEmpty);

    platform.cached = fix(at: observedAt.subtract(const Duration(seconds: 15)));
    expect(
      (await service.start(requestPermission: true)).state,
      LocationAccessState.ready,
    );
    expect(platform.watches, hasLength(1));
  });

  test('invalid, stale and out-of-order watch fixes are ignored', () async {
    final platform = FakeLocationPlatform();
    final service = serviceFor(platform);
    final positions = <Position>[];
    service.positions.listen(positions.add);
    await service.start(requestPermission: true);
    final watch = platform.watches.single;
    watch.add(fix(latitude: double.nan));
    watch.add(fix(latitude: 91));
    watch.add(fix(at: observedAt.subtract(const Duration(hours: 2))));
    watch.add(fix(at: observedAt.add(const Duration(hours: 2))));
    watch.add(fix(at: observedAt.subtract(const Duration(seconds: 1))));
    expect(positions, isEmpty);

    watch.add(fix(latitude: 45.02));
    expect(positions.single.latitude, 45.02);
  });

  test(
    'resuming does not disconnect the watch while waiting for a fix',
    () async {
      final next = Completer<Position>();
      final platform = FakeLocationPlatform();
      final service = serviceFor(platform);
      await service.start(requestPermission: true);
      platform.read = (_) => next.future;
      final resumed = service.start(requestPermission: false);
      expect(platform.cancelledWatches, 0);
      platform.watches.single.add(
        fix(at: observedAt.add(const Duration(seconds: 1)), latitude: 45.03),
      );
      next.complete(fix());

      final result = await resumed;
      expect(result.position!.latitude, 45.03);
      expect(platform.cancelledWatches, 1);
      expect(platform.watches, hasLength(2));
    },
  );

  test('dispose during a request cannot start a late subscription', () async {
    final next = Completer<Position>();
    final entered = Completer<void>();
    final platform = FakeLocationPlatform()
      ..read = (_) {
        entered.complete();
        return next.future;
      };
    final service = serviceFor(platform);
    final pending = service.start(requestPermission: true);
    await entered.future;
    await service.dispose();
    next.complete(fix());
    expect((await pending).state, LocationAccessState.unavailable);
    expect(platform.watches, isEmpty);
    expect(
      (await service.start(requestPermission: true)).state,
      LocationAccessState.unavailable,
    );
    expect(platform.settings, hasLength(1));
  });

  test(
    'native explicit consent still uses the platform permission API',
    () async {
      final platform = FakeLocationPlatform()
        ..permission = LocationPermission.denied;
      final service = serviceFor(platform, web: false);
      expect(
        (await service.start(requestPermission: true)).state,
        LocationAccessState.ready,
      );
      expect(platform.permissionRequests, 1);
      expect(platform.watches, hasLength(1));
    },
  );
}
