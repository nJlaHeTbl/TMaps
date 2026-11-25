import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../l10n/app_localizations.dart';

/// Opens the static privacy page (`web/privacy.html`) in the app's language.
abstract final class PrivacyPolicyLink {
  static Uri uriFor(Locale locale) {
    final language = AppLocalizations.resolveLocale(locale).languageCode;
    return Uri.parse(
      AppConfig.publicAppUrl,
    ).resolve('privacy.html').replace(queryParameters: {'lang': language});
  }

  static Future<bool> open(Locale locale) async {
    try {
      return await launchUrl(
        uriFor(locale),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } on Object {
      return false;
    }
  }
}
