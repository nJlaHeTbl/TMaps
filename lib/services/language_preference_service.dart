import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { system, russian, kazakh, english }

extension AppLanguageLocale on AppLanguage {
  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.russian => const Locale('ru'),
    AppLanguage.kazakh => const Locale('kk'),
    AppLanguage.english => const Locale('en'),
  };
}

class LanguagePreferenceService {
  const LanguagePreferenceService();

  static const _storageKey = 'app_language';

  Future<AppLanguage> load() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_storageKey)) {
      'russian' => AppLanguage.russian,
      'kazakh' => AppLanguage.kazakh,
      'english' => AppLanguage.english,
      _ => AppLanguage.system,
    };
  }

  Future<void> save(AppLanguage language) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, language.name);
  }
}
