import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/presentation/app_motion.dart';
import 'package:tmaps/widgets/place_search_sheet.dart';

void main() {
  final places = List.generate(
    12,
    (index) => <String, dynamic>{
      'id': index + 1,
      'name': 'Cafe $index',
      'place_kind': 'cafe',
      'has_toilet': false,
      'lat': 45.0 + index * .001,
      'lng': 78.0,
    },
  );

  testWidgets('outgoing search results cannot select a stale place', (
    tester,
  ) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => PlaceSearchSheet(
                    places: places,
                    origin: const LatLng(45, 78),
                    autofocus: false,
                  ),
                );
              },
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    expect(find.text('Cafe 0'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'no such cafe');
    await tester.pump();
    // Previous results still paint during the fade, but must be inert.
    expect(find.text('Cafe 0'), findsOneWidget);
    await tester.tap(find.text('Cafe 0'), warnIfMissed: false);
    expect(selected, isNull);
    expect(find.byType(PlaceSearchSheet), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Cafe 0'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Cafe 1');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(ListView), matching: find.text('Cafe 1')),
    );
    await tester.pumpAndSettle();
    expect(selected?['id'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the first six result cards use entrance animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceSearchSheet(
            places: places,
            origin: const LatLng(45, 78),
            autofocus: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MotionEntrance).evaluate().length, lessThanOrEqualTo(6));
    expect(find.byType(MotionEntrance).evaluate().length, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
