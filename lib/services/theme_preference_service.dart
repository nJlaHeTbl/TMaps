import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferenceService {
  const ThemePreferenceService();

  static const _storageKey = 'theme_mode';

  Future<ThemeMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_storageKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> save(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, mode.name);
  }
}
