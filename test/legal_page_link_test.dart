import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/services/legal_page_link.dart';

void main() {
  test('legal links open the page in the app language', () {
    expect(
      LegalPageLink.uriFor(LegalPage.privacy, const Locale('kk')).toString(),
      'https://njlahetbl.github.io/TMaps/privacy.html?lang=kk',
    );
    expect(
      LegalPageLink.uriFor(
        LegalPage.terms,
        const Locale('en', 'US'),
      ).toString(),
      'https://njlahetbl.github.io/TMaps/terms.html?lang=en',
    );
    // Unsupported languages fall back to the app's default language.
    expect(
      LegalPageLink.uriFor(
        LegalPage.privacy,
        const Locale('de'),
      ).queryParameters['lang'],
      'ru',
    );
  });

  test('every legal page ships with all three languages', () {
    for (final page in LegalPage.values) {
      final html = File('web/${page.fileName}').readAsStringSync();
      for (final language in ['ru', 'kk', 'en']) {
        expect(
          html,
          contains('data-lang-block="$language"'),
          reason: '${page.fileName} $language',
        );
      }
    }
  });
}
