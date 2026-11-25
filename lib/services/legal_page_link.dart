import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../l10n/app_localizations.dart';

/// Static legal pages published next to the app (`web/*.html`).
enum LegalPage {
  privacy('privacy.html'),
  terms('terms.html');

  const LegalPage(this.fileName);

  final String fileName;
}

/// Opens a legal page in the app's language.
abstract final class LegalPageLink {
  static Uri uriFor(LegalPage page, Locale locale) {
    final language = AppLocalizations.resolveLocale(locale).languageCode;
    return Uri.parse(
      AppConfig.publicAppUrl,
    ).resolve(page.fileName).replace(queryParameters: {'lang': language});
  }

  static Future<bool> open(LegalPage page, Locale locale) async {
    try {
      return await launchUrl(
        uriFor(page, locale),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } on Object {
      return false;
    }
  }
}
