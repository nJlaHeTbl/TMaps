import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/l10n/app_localizations.dart';
import 'package:tmaps/services/place_photo_service.dart';
import 'package:tmaps/widgets/place_overview.dart';

class FakePhotos extends PlacePhotoService {
  FakePhotos({this.fail = false});
  bool fail;
  int calls = 0;
  @override
  Future<PlacePhoto?> load(Map<String, dynamic> place) async {
    calls++;
    if (fail) throw Exception('offline');
    return null;
  }
}

void main() {
  testWidgets(
    'description and empty photo fit a small phone in all languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: PlaceOverview(
                  place: const {'place_kind': 'public_toilet'},
                  photoService: FakePhotos(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(const AppLocalizations(Locale('ru')).translate('О месте')),
          locale.languageCode == 'ru' ? findsOneWidget : findsNothing,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('failed metadata is retryable and never hides the description', (
    tester,
  ) async {
    final photos = FakePhotos(fail: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceOverview(
            place: const {'place_kind': 'public_toilet'},
            photoService: photos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Фото не загрузилось'), findsOneWidget);
    expect(find.textContaining('Стоимость не указана'), findsOneWidget);
    photos.fail = false;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(photos.calls, 2);
    expect(find.text('Фотографии пока нет'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
