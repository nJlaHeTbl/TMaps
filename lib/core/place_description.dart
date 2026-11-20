import '../l10n/app_localizations.dart';
import 'place_info.dart';

abstract final class PlaceDescription {
  static String build(Map<String, dynamic> place, AppLocalizations l10n) {
    String tr(String text) => l10n.translate(text);
    final hasToilet = PlaceInfo.hasToilet(place);
    final sentences = <String>['${tr(PlaceInfo.kindLabel(place))}.'];
    if (PlaceInfo.isVenue(place) &&
        PlaceInfo.effectiveValue(place, 'has_toilet') != true) {
      sentences.add(tr('Туалет не подтверждён.'));
    } else if (hasToilet) {
      sentences.add(
        tr(
          !PlaceInfo.feeKnown(place)
              ? 'Стоимость не указана.'
              : PlaceInfo.feeStatus(place) == true
              ? 'Бесплатный туалет.'
              : 'Платный туалет.',
        ),
      );
    }
    final access = PlaceInfo.effectiveValue(place, 'access_type')?.toString();
    final accessText = switch (access) {
      'public' || 'yes' => 'Доступ для всех.',
      'customers' || 'customer' => 'Доступ только для клиентов.',
      'destination' => 'Доступ для посетителей.',
      'private' || 'no' => 'Свободного доступа нет.',
      _ => null,
    };
    if (accessText != null) sentences.add(tr(accessText));
    final hours = PlaceInfo.effectiveValue(
      place,
      'opening_hours',
    )?.toString().trim();
    if (hours != null && hours.isNotEmpty) {
      sentences.add(
        hours == '24/7'
            ? tr('Круглосуточно.')
            : l10n.translate('Часы работы: {hours}.', {'hours': hours}),
      );
    }
    if (hasToilet) {
      for (final field in [
        ('has_paper', 'Бумага есть.', 'Бумаги нет.'),
        ('has_soap', 'Мыло есть.', 'Мыла нет.'),
        (
          'wheelchair_accessible',
          'Доступен для коляски.',
          'Не доступен для коляски.',
        ),
      ]) {
        final raw =
            PlaceInfo.effectiveValue(place, field.$1) ??
            (field.$1 == 'wheelchair_accessible' ? place['wheelchair'] : null);
        final value = switch (raw?.toString().toLowerCase()) {
          'true' || 'yes' || '1' => true,
          'false' || 'no' || '0' => false,
          _ => null,
        };
        if (value != null) sentences.add(tr(value ? field.$2 : field.$3));
      }
    }
    return sentences.join(' ');
  }
}
