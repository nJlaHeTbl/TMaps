import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/services/privacy_policy_link.dart';

void main() {
  test('privacy link opens the page in the app language', () {
    expect(
      PrivacyPolicyLink.uriFor(const Locale('kk')).toString(),
      'https://njlahetbl.github.io/TMaps/privacy.html?lang=kk',
    );
    expect(
      PrivacyPolicyLink.uriFor(const Locale('en', 'US')).toString(),
      'https://njlahetbl.github.io/TMaps/privacy.html?lang=en',
    );
    // Unsupported languages fall back to the app's default language.
    expect(
      PrivacyPolicyLink.uriFor(const Locale('de')).queryParameters['lang'],
      'ru',
    );
  });

  test('privacy page ships with all three languages', () {
    final page = File('web/privacy.html').readAsStringSync();
    for (final language in ['ru', 'kk', 'en']) {
      expect(page, contains('data-lang-block="$language"'));
    }
  });
}
