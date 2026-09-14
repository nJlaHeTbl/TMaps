import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/presentation/app_motion.dart';

Widget host(Widget child, {bool reduced = false, bool accessible = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          accessibleNavigation: accessible,
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('entrance fades once, then stays settled across rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(host(const MotionEntrance(child: Text('First'))));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    await tester.pump(const Duration(milliseconds: 100));
    final halfway = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(halfway, greaterThan(0));
    expect(halfway, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    await tester.pumpWidget(
      host(const MotionEntrance(child: Text('Updated GPS'))),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  for (final accessible in [false, true]) {
    testWidgets('reduced motion is immediate (accessible=$accessible)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const MotionEntrance(child: Text('Visible')),
          reduced: !accessible,
          accessible: accessible,
        ),
      );
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(find.text('Visible'), findsOneWidget);
      await tester.pumpWidget(
        host(
          const MotionSwitcher(child: Text('Old', key: ValueKey('old'))),
          reduced: !accessible,
          accessible: accessible,
        ),
      );
      await tester.pumpWidget(
        host(
          const MotionSwitcher(child: Text('New', key: ValueKey('new'))),
          reduced: !accessible,
          accessible: accessible,
        ),
      );
      expect(find.text('Old'), findsNothing);
      expect(find.text('New'), findsOneWidget);
    });
  }

  testWidgets(
    'dismissal blocks pointer and keyboard access before fading out',
    (tester) async {
      var taps = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        host(
          MotionSwitcher(
            child: TextButton(
              key: const ValueKey('cancelled'),
              focusNode: focus,
              onPressed: () => taps++,
              child: const Text('Cancelled route'),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(host(const MotionSwitcher(child: null)));
      await tester.pump();
      expect(find.text('Cancelled route'), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('cancelled')),
        warnIfMissed: false,
      );
      expect(taps, 0);
      expect(
        find.ancestor(
          of: find.text('Cancelled route'),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancelled route'), findsNothing);
    },
  );

  testWidgets('a rapid close and reopen ends on the latest child', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const MotionSwitcher(child: Text('A', key: ValueKey('a')))),
    );
    await tester.pumpWidget(host(const MotionSwitcher(child: null)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(
      host(const MotionSwitcher(child: Text('B', key: ValueKey('b')))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(
      host(const MotionSwitcher(child: Text('C', key: ValueKey('c')))),
    );
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
    expect(find.text('C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'turning reduced motion on mid-transition removes the old child',
    (tester) async {
      await tester.pumpWidget(
        host(const MotionSwitcher(child: Text('A', key: ValueKey('a')))),
      );
      await tester.pumpWidget(
        host(const MotionSwitcher(child: Text('B', key: ValueKey('b')))),
      );
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpWidget(
        host(
          const MotionSwitcher(child: Text('B', key: ValueKey('b'))),
          reduced: true,
        ),
      );
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unchanged keyed state does not create outgoing copies', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const MotionSwitcher(child: Text('One', key: ValueKey('same')))),
    );
    await tester.pumpWidget(
      host(const MotionSwitcher(child: Text('Two', key: ValueKey('same')))),
    );
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsOneWidget);
  });

  testWidgets('entrance does not rebuild its content on every frame', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      host(
        MotionEntrance(
          child: Builder(
            builder: (_) {
              builds++;
              return const Text('Static content');
            },
          ),
        ),
      ),
    );
    final initial = builds;
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(builds, initial);
  });
}
