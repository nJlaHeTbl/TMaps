import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/widgets/location_help_sheet.dart';

void main() {
  testWidgets('shows browser-specific GPS recovery steps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationHelpSheet(
            isWeb: true,
            permissionBlocked: true,
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Разреши доступ к геопозиции'), findsOneWidget);
    expect(find.text('Chrome или Android'), findsOneWidget);
    expect(find.text('iPhone или Safari'), findsOneWidget);
    expect(find.text('Проверить GPS'), findsOneWidget);
  });

  testWidgets('retries location after closing the help sheet', (tester) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => LocationHelpSheet(
                  isWeb: true,
                  permissionBlocked: false,
                  onRetry: () => retried = true,
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Проверить GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проверить GPS'));
    await tester.pumpAndSettle();

    expect(retried, isTrue);
    expect(find.text('Поможем включить GPS'), findsNothing);
  });
}
