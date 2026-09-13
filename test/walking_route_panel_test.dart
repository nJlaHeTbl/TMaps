import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tmaps/core/pedestrian_alert.dart';
import 'package:tmaps/l10n/app_localizations.dart';
import 'package:tmaps/services/walking_route_controller.dart';
import 'package:tmaps/widgets/walking_route_panel.dart';

void main() {
  Widget app({
    required WalkingRouteStatus status,
    String language = 'ru',
    Brightness brightness = Brightness.light,
    VoidCallback? retry,
    VoidCallback? close,
    List<PedestrianAlert> alerts = const [],
  }) => MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: brightness,
      ),
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 296,
          child: WalkingRoutePanel(
            status: status,
            distance: '150 м',
            duration: '2 мин',
            alerts: alerts,
            onClose: close ?? () {},
            onRetry: retry,
          ),
        ),
      ),
    ),
  );

  testWidgets('cancel works while loading and refresh is hidden', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      app(status: WalkingRouteStatus.loading, close: () => cancelled = true),
    );
    await tester.pump();
    expect(find.text('Строим пеший маршрут…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Обновить маршрут'), findsNothing);
    await tester.tap(find.byTooltip('Убрать маршрут'));
    expect(cancelled, isTrue);
  });
  testWidgets('failed routes offer retry and keep approximate estimates', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      app(
        status: WalkingRouteStatus.failed,
        language: 'en',
        retry: () => retried = true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not update the route'), findsOneWidget);
    expect(find.text('≈ 150 m · 2 min'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh route'));
    expect(retried, isTrue);
  });
  for (final language in ['ru', 'kk', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'GPS and hazard warnings fit narrow $language $brightness layout',
        (tester) async {
          await tester.pumpWidget(
            app(
              status: WalkingRouteStatus.impreciseLocation,
              language: language,
              brightness: brightness,
              alerts: [
                PedestrianAlert(
                  id: 1,
                  position: const LatLng(45, 78),
                  type: PedestrianAlertType.ice,
                  username: 'Test',
                  description: null,
                  createdAt: DateTime(2026),
                  expiresAt: DateTime(2027),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('≈ 150'), findsOneWidget);
          final l10n = AppLocalizations(Locale(language));
          expect(
            find.text(l10n.translate('Маршрут на паузе: неточный GPS')),
            findsOneWidget,
          );
          expect(
            find.text(
              l10n.translate('{label} рядом с маршрутом', {
                'label': l10n.translate(PedestrianAlertType.ice.label),
              }),
            ),
            findsOneWidget,
          );
        },
      );
    }
  }
}
