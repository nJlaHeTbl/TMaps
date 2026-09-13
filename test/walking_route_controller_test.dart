import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/services/route_service.dart';
import 'package:tmaps/services/walking_route_controller.dart';

const start = LatLng(45, 78);
const end = LatLng(45.01, 78);
const outside = LatLng(45.004, 78.002);
RouteResult route([LatLng from = start, LatLng to = end]) =>
    RouteResult(points: [from, to], distance: 1100, duration: 900);

void main() {
  late DateTime now;
  late WalkingRouteController controller;
  late List<Completer<RouteResult>> replies;
  late List<LatLng> starts;
  setUp(() {
    now = DateTime(2026, 9, 12, 12);
    replies = [];
    starts = [];
    controller = WalkingRouteController(
      now: () => now,
      fetch: ({required from, required to}) {
        starts.add(from);
        final reply = Completer<RouteResult>();
        replies.add(reply);
        return reply.future;
      },
    );
  });
  tearDown(() => controller.dispose());

  Future<void> initialRoute() async {
    final pending = controller.build(from: start, to: end, accuracy: 5);
    replies.last.complete(route());
    expect(await pending, isTrue);
  }

  void fix(LatLng point, {int seconds = 1, double accuracy = 5}) {
    now = now.add(Duration(seconds: seconds));
    controller.observePosition(point, accuracy: accuracy, observedAt: now);
  }

  Future<void> flush() async => Future<void>.delayed(Duration.zero);

  test('GPS movement never rewrites provider geometry', () async {
    await initialRoute();
    fix(const LatLng(45.0003, 78));
    expect(controller.route!.points, [start, end]);
    expect(() => controller.route!.points[0] = outside, throwsUnsupportedError);
    expect(starts, [start]);
  });
  test('the latest destination wins over a late response', () async {
    final first = controller.build(from: start, to: end, accuracy: 5);
    final second = controller.build(from: start, to: outside, accuracy: 5);
    replies[1].complete(route(start, outside));
    expect(await second, isTrue);
    replies[0].complete(route());
    expect(await first, isFalse);
    expect(controller.destination, outside);
    expect(controller.route!.points.last, outside);
  });
  test('cancelled requests cannot resurrect a route', () async {
    final pending = controller.build(from: start, to: end, accuracy: 5);
    controller.clear();
    replies.single.complete(route());
    expect(await pending, isFalse);
    expect(controller.status, WalkingRouteStatus.idle);
    expect(controller.route, isNull);
  });
  test('one GPS spike is not enough to reroute', () async {
    await initialRoute();
    fix(outside, seconds: 31);
    expect(controller.status, WalkingRouteStatus.offRoute);
    fix(start, seconds: 4);
    expect(controller.status, WalkingRouteStatus.ready);
    expect(replies, hasLength(1));
  });
  test(
    'sustained deviation reroutes once and preserves the previous line',
    () async {
      await initialRoute();
      fix(outside, seconds: 31);
      fix(outside, seconds: 3);
      expect(controller.status, WalkingRouteStatus.rerouting);
      expect(starts, [start, outside]);
      expect(controller.route!.points, [start, end]);
      fix(outside, seconds: 3);
      expect(replies, hasLength(2));
      replies.last.complete(route(outside));
      await flush();
      expect(controller.status, WalkingRouteStatus.ready);
      expect(controller.route!.points.first, outside);
    },
  );
  test(
    'failed refresh keeps the route and enforces automatic cooldown',
    () async {
      await initialRoute();
      fix(outside, seconds: 31);
      fix(outside, seconds: 3);
      replies.last.completeError(StateError('network down'));
      await flush();
      expect(controller.status, WalkingRouteStatus.failed);
      expect(controller.route!.points, [start, end]);
      fix(outside, seconds: 1);
      expect(replies, hasLength(2));
      fix(outside, seconds: 29);
      expect(replies, hasLength(3));
      replies.last.complete(route(outside));
      await flush();
    },
  );
  test('progress on the path refreshes estimates after 100 metres', () async {
    await initialRoute();
    fix(const LatLng(45.001, 78), seconds: 31);
    expect(replies, hasLength(2));
    replies.last.complete(route(const LatLng(45.001, 78)));
    await flush();
    expect(controller.route!.points.first, const LatLng(45.001, 78));
  });
  test(
    'coarse GPS pauses routing and does not send uncertain coordinates',
    () async {
      await initialRoute();
      fix(outside, seconds: 31, accuracy: 150);
      fix(outside, seconds: 4, accuracy: 150);
      expect(controller.status, WalkingRouteStatus.impreciseLocation);
      expect(await controller.retry(), isFalse);
      expect(replies, hasLength(1));
      fix(start);
      expect(controller.status, WalkingRouteStatus.ready);
    },
  );
  test(
    'coarse initial fix waits for precision before the first request',
    () async {
      expect(
        await controller.build(from: start, to: end, accuracy: 200),
        isFalse,
      );
      expect(controller.status, WalkingRouteStatus.impreciseLocation);
      expect(replies, isEmpty);
      fix(start);
      final pending = controller.retry();
      replies.single.complete(route());
      expect(await pending, isTrue);
    },
  );
  test(
    'losing GPS during a request cannot show a fresh route status',
    () async {
      final pending = controller.build(from: start, to: end, accuracy: 5);
      controller.setLocationAvailable(false);
      replies.single.complete(route());
      await pending;
      expect(controller.status, WalkingRouteStatus.locationUnavailable);
      expect(await controller.retry(), isFalse);
      fix(start);
      expect(controller.status, WalkingRouteStatus.ready);
    },
  );
  test('stale, future and out-of-order fixes are ignored', () async {
    await initialRoute();
    fix(start, seconds: 35);
    for (final timestamp in [
      now.subtract(const Duration(seconds: 1)),
      now.subtract(const Duration(minutes: 2)),
      now.add(const Duration(minutes: 2)),
    ]) {
      controller.observePosition(outside, accuracy: 5, observedAt: timestamp);
    }
    expect(controller.status, WalkingRouteStatus.ready);
    expect(replies, hasLength(1));
  });
  test('manual retries share an in-flight request', () async {
    final pending = controller.build(from: start, to: end, accuracy: 5);
    replies.single.completeError(StateError('offline'));
    expect(await pending, isFalse);
    final retry1 = controller.retry();
    final retry2 = controller.retry();
    expect(replies, hasLength(2));
    replies.last.complete(route());
    expect(await retry1, isTrue);
    expect(await retry2, isTrue);
  });
  test('coarse replacement invalidates the old destination request', () async {
    final pending = controller.build(from: start, to: end, accuracy: 5);
    await controller.build(from: start, to: outside, accuracy: 200);
    replies.single.complete(route());
    expect(await pending, isFalse);
    expect(controller.route, isNull);
    expect(controller.destination, outside);
    expect(controller.status, WalkingRouteStatus.impreciseLocation);
  });
  test('disposed controllers ignore late replies and do not notify', () async {
    final response = Completer<RouteResult>();
    final disposable = WalkingRouteController(
      fetch: ({required from, required to}) => response.future,
    );
    final pending = disposable.build(from: start, to: end, accuracy: 5);
    var notifications = 0;
    disposable.addListener(() => notifications++);
    disposable.dispose();
    response.complete(route());
    expect(await pending, isFalse);
    expect(notifications, 0);
  });
  testWidgets('silent GPS expires even without another position event', (
    tester,
  ) async {
    await initialRoute();
    now = now.add(const Duration(seconds: 70));
    await tester.pump(const Duration(seconds: 70));
    expect(controller.status, WalkingRouteStatus.locationUnavailable);
    controller.clear();
  });
  testWidgets(
    'a stalled provider times out without discarding the destination',
    (tester) async {
      final pending = controller.build(from: start, to: end, accuracy: 5);
      await tester.pump(const Duration(seconds: 21));
      expect(await pending, isFalse);
      expect(controller.status, WalkingRouteStatus.failed);
      expect(controller.destination, end);
      replies.single.complete(route());
      await tester.pump();
      expect(controller.route, isNull);
      controller.clear();
    },
  );
}
