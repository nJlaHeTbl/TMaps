import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/place_description.dart';
import 'package:tmaps/l10n/app_localizations.dart';

void main() {
  const ru = AppLocalizations(Locale('ru'));
  test('unknown fee and amenities are not invented', () {
    final text = PlaceDescription.build({
      'place_kind': 'public_toilet',
      'is_free': false,
      'fee_known': false,
    }, ru);
    expect(text, contains('Стоимость не указана'));
    expect(text, isNot(contains('Платный')));
    expect(text, isNot(contains('Бумага есть')));
    expect(text, isNot(contains('Мыло есть')));
  });
  test('latest report wins and explicit absences are described', () {
    final text = PlaceDescription.build({
      'place_kind': 'public_toilet',
      'is_free': true,
      'fee_known': true,
      'has_paper': true,
      'opening_hours': '24/7',
      'latest_report': {'is_free': false, 'has_paper': false, 'has_soap': true},
    }, ru);
    expect(text, contains('Платный туалет'));
    expect(text, contains('Круглосуточно'));
    expect(text, contains('Бумаги нет'));
    expect(text, contains('Мыло есть'));
    expect(text, isNot(contains('Бесплатный')));
  });
  test('a cafe without a toilet is not described as a toilet', () {
    final text = PlaceDescription.build({
      'place_kind': 'cafe',
      'has_toilet': false,
      'is_free': true,
    }, ru);
    expect(text, contains('Туалет не подтверждён'));
    expect(text, isNot(contains('Бесплатный туалет')));
  });
  test('description is translated including interpolated hours', () {
    const place = {
      'place_kind': 'public_toilet',
      'opening_hours': '09:00–18:00',
    };
    final en = PlaceDescription.build(
      place,
      const AppLocalizations(Locale('en')),
    );
    final kk = PlaceDescription.build(
      place,
      const AppLocalizations(Locale('kk')),
    );
    expect(en, contains('Opening hours: 09:00–18:00'));
    expect(en, isNot(matches(RegExp('[А-Яа-я]'))));
    expect(kk, contains('Жұмыс уақыты: 09:00–18:00'));
  });
}
