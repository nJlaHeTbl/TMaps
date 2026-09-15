import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/presentation/app_motion.dart';
import 'package:tmaps/widgets/app_bottom_sheet.dart';

class _SheetObserver extends NavigatorObserver {
  late ModalBottomSheetRoute<int> sheet;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute<int>) sheet = route;
  }
}

Widget _host({
  required _SheetObserver observer,
  required ValueChanged<int?> onResult,
  bool reduced = false,
  bool accessible = false,
  bool customAppearance = false,
}) => MaterialApp(
  navigatorObservers: [observer],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(disableAnimations: reduced, accessibleNavigation: accessible),
    child: child!,
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final result = await showAppBottomSheet<int>(
              context: context,
              backgroundColor: customAppearance ? Colors.teal : null,
              shape: customAppearance
                  ? const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    )
                  : null,
              clipBehavior: customAppearance ? Clip.antiAlias : null,
              isScrollControlled: customAppearance,
              showDragHandle: customAppearance,
              builder: (sheetContext) => SizedBox(
                height: 180,
                width: double.infinity,
                child: Column(
                  children: [
                    const Text('Sheet content'),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(42),
                      child: const Text('Choose'),
                    ),
                  ],
                ),
              ),
            );
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('sheet animates in and out and preserves a typed selection', (
    tester,
  ) async {
    final observer = _SheetObserver();
    int? result;
    await tester.pumpWidget(
      _host(observer: observer, onResult: (value) => result = value),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(observer.sheet.transitionDuration, AppMotion.panel);
    expect(observer.sheet.reverseTransitionDuration, AppMotion.quick);
    await tester.pump(const Duration(milliseconds: 80));
    expect(observer.sheet.animation!.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(observer.sheet.animation!.value, 1);

    await tester.tap(find.text('Choose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(observer.sheet.animation!.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(result, 42);
    expect(find.text('Sheet content'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final accessible in [false, true]) {
    testWidgets('sheet has no motion (accessible=$accessible)', (tester) async {
      final observer = _SheetObserver();
      int? result;
      await tester.pumpWidget(
        _host(
          observer: observer,
          onResult: (value) => result = value,
          reduced: !accessible,
          accessible: accessible,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(observer.sheet.transitionDuration, Duration.zero);
      expect(observer.sheet.reverseTransitionDuration, Duration.zero);
      expect(observer.sheet.animation!.value, 1);
      await tester.tap(find.text('Choose'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Sheet content'), findsNothing);
      expect(result, 42);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('back and barrier dismissal return null; reopening still works', (
    tester,
  ) async {
    final results = <int?>[];
    await tester.pumpWidget(
      _host(observer: _SheetObserver(), onResult: results.add),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(results, [null]);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(results, [null, null]);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(results, [null, null, 42]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping down dismisses without choosing a result', (
    tester,
  ) async {
    final results = <int?>[];
    await tester.pumpWidget(
      _host(observer: _SheetObserver(), onResult: results.add),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(BottomSheet), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom appearance and sizing are forwarded unchanged', (
    tester,
  ) async {
    final observer = _SheetObserver();
    await tester.pumpWidget(
      _host(observer: observer, onResult: (_) {}, customAppearance: true),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, Colors.teal);
    expect(sheet.clipBehavior, Clip.antiAlias);
    expect(sheet.showDragHandle, isTrue);
    expect(
      sheet.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
    expect(observer.sheet.isScrollControlled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
