import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmaps/services/theme_preference_service.dart';

void main() {
  const service = ThemePreferenceService();

  test('по умолчанию следует теме устройства', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await service.load(), ThemeMode.system);
  });

  test('сохраняет выбранную тему', () async {
    SharedPreferences.setMockInitialValues({});
    await service.save(ThemeMode.dark);
    expect(await service.load(), ThemeMode.dark);
  });
}
