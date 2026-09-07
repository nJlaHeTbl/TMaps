import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmaps/l10n/app_localizations.dart';
import 'package:tmaps/services/language_preference_service.dart';

void main() {
  const service = LanguagePreferenceService();

  test('по умолчанию следует языку устройства', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await service.load(), AppLanguage.system);
  });

  test('сохраняет каждый выбранный язык', () async {
    for (final language in const [
      AppLanguage.russian,
      AppLanguage.kazakh,
      AppLanguage.english,
      AppLanguage.system,
    ]) {
      SharedPreferences.setMockInitialValues({});
      await service.save(language);

      expect(await service.load(), language);
    }
  });

  test(
    'неизвестное сохранённое значение безопасно включает системный язык',
    () async {
      SharedPreferences.setMockInitialValues({'app_language': 'de'});

      expect(await service.load(), AppLanguage.system);
    },
  );

  test('переводит статический и шаблонный текст', () {
    const english = AppLocalizations(Locale('en'));
    const kazakh = AppLocalizations(Locale('kk'));

    expect(english.translate('Туалеты'), 'Toilets');
    expect(kazakh.translate('Туалеты'), 'Дәретханалар');
    expect(english.translate('Мои заявки: 4'), 'My submissions: 4');
    expect(kazakh.translate('Мои заявки: 4'), 'Менің өтінімдерім: 4');
  });

  test(
    'определяет поддерживаемый системный язык и использует русский запасным',
    () {
      expect(
        AppLocalizations.resolveLocale(const Locale('en', 'US')),
        const Locale('en'),
      );
      expect(
        AppLocalizations.resolveLocale(const Locale('kk', 'KZ')),
        const Locale('kk'),
      );
      expect(
        AppLocalizations.resolveLocale(const Locale('de', 'DE')),
        const Locale('ru'),
      );
      expect(AppLocalizations.resolveLocale(null), const Locale('ru'));
    },
  );

  testWidgets('LocalizedText использует выбранный язык MaterialApp', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: LocalizedText('Добро пожаловать в TMaps')),
      ),
    );

    expect(find.text('Welcome to TMaps'), findsOneWidget);
    expect(find.text('Добро пожаловать в TMaps'), findsNothing);
  });
}
