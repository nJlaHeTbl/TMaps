import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  static const fallbackLocale = Locale('ru');
  static const supportedLocales = <Locale>[
    fallbackLocale,
    Locale('kk'),
    Locale('en'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(fallbackLocale);
  }

  static Locale resolveLocale(Locale? locale) {
    if (locale == null) return fallbackLocale;
    return supportedLocales.firstWhere(
      (supported) => supported.languageCode == locale.languageCode,
      orElse: () => fallbackLocale,
    );
  }

  String translate(
    String source, [
    Map<String, Object?> parameters = const <String, Object?>{},
  ]) {
    final languageCode = resolveLocale(locale).languageCode;
    final translations = _translations[languageCode];

    if (translations != null) {
      final directTranslation = translations[source];
      if (directTranslation != null) {
        return _interpolate(directTranslation, parameters);
      }

      for (final entry in translations.entries) {
        if (!entry.key.contains('{')) continue;
        final inferredParameters = _matchTemplate(entry.key, source);
        if (inferredParameters != null) {
          return _interpolate(entry.value, inferredParameters);
        }
      }
    }

    return _interpolate(source, parameters);
  }
}

extension AppLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.translate(data),
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(
    AppLocalizations(AppLocalizations.resolveLocale(locale)),
  );

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

String _interpolate(String value, Map<String, Object?> parameters) {
  var result = value;
  for (final entry in parameters.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
  }
  return result;
}

Map<String, Object?>? _matchTemplate(String template, String source) {
  final tokenPattern = RegExp(r'\{([a-zA-Z][a-zA-Z0-9_]*)\}');
  final matches = tokenPattern.allMatches(template).toList(growable: false);
  if (matches.isEmpty) return null;

  final parameterNames = <String>[];
  final pattern = StringBuffer('^');
  var previousEnd = 0;
  for (final match in matches) {
    pattern.write(RegExp.escape(template.substring(previousEnd, match.start)));
    pattern.write('(.+?)');
    parameterNames.add(match.group(1)!);
    previousEnd = match.end;
  }
  pattern
    ..write(RegExp.escape(template.substring(previousEnd)))
    ..write(r'$');

  final sourceMatch = RegExp(pattern.toString()).firstMatch(source);
  if (sourceMatch == null) return null;
  return <String, Object?>{
    for (var index = 0; index < parameterNames.length; index++)
      parameterNames[index]: sourceMatch.group(index + 1),
  };
}

const _translations = <String, Map<String, String>>{
  'en': _englishTranslations,
  'kk': _kazakhTranslations,
};

const _englishTranslations = <String, String>{
  'Пеший маршрут': 'Walking route',
  'Строим пеший маршрут…': 'Finding a walking route…',
  'Обновляем пеший маршрут…': 'Updating walking route…',
  'Вы отошли от маршрута': 'You have left the route',
  'Маршрут на паузе: нет GPS': 'Route paused: no GPS signal',
  'Маршрут на паузе: неточный GPS': 'Route paused: low GPS accuracy',
  'Не удалось построить маршрут': 'Could not find a route',
  'Не удалось обновить маршрут': 'Could not update the route',
  'Верни сигнал GPS, чтобы обновить путь':
      'Restore your GPS signal to update the route',
  'Ждём более точные координаты': 'Waiting for a more accurate location',
  'Проверь интернет и повтори попытку':
      'Check your internet connection and try again',
  'Проверяем отклонение от пути': 'Checking whether you have left the route',
  'Обновить маршрут': 'Refresh route',
  'Убрать маршрут': 'Clear route',
  'Предупреждений рядом с маршрутом: {count}':
      'Warnings near the route: {count}',
  'Настройки приложения': 'App settings',
  'Язык': 'Language',
  'Как в системе': 'Use system language',
  'Оформление': 'Appearance',
  'Как на телефоне': 'Use device setting',
  'Светлая тема': 'Light theme',
  'Тёмная тема': 'Dark theme',
  'Установить TMaps': 'Install TMaps',
  'Общественные туалеты': 'Public toilets',
  'Добавленные туалеты': 'Community-added toilets',
  'Кафе и еда': 'Cafés & food',
  'Заведения': 'Venues',
  'Зарядка электромобилей': 'EV charging',
  'Пользователь TMaps': 'TMaps user',
  'Пешеходам: возможны снег и скользкие тропинки — выбирай очищенный маршрут.':
      'For pedestrians: expect snow and slippery paths — choose a cleared route.',
  'Пешеходам: тропинки могут быть мокрыми и скользкими — иди осторожно.':
      'For pedestrians: paths may be wet and slippery — walk carefully.',
  'Пешеходам: видимость снижена — переходи дороги особенно внимательно.':
      'For pedestrians: visibility is reduced — take extra care when crossing roads.',
  'Обновлено {count} дн. назад': 'Updated {count} days ago',
  'Обновлено {count} нед. назад': 'Updated {count} weeks ago',
  'Обновлено {count} мес. назад': 'Updated {count} months ago',
  'Обновлено {count} г. назад': 'Updated {count} years ago',
  'Астана': 'Astana',
  'Алматы': 'Almaty',
  'Шымкент': 'Shymkent',
  'Талдыкорган': 'Taldykorgan',
  'Караганда': 'Karaganda',
  'Актобе': 'Aktobe',
  'Тараз': 'Taraz',
  'Павлодар': 'Pavlodar',
  'Өскемен': 'Oskemen',
  'Семей': 'Semey',
  'Атырау': 'Atyrau',
  'Костанай': 'Kostanay',
  'Кызылорда': 'Kyzylorda',
  'Уральск': 'Oral',
  'Петропавловск': 'Petropavl',
  'Туркистан': 'Turkistan',
  'Актау': 'Aktau',
  'Кокшетау': 'Kokshetau',
  'Жезказган': 'Zhezkazgan',
  'Конаев': 'Konaev',
  'Текели': 'Tekeli',
  'Экибастуз': 'Ekibastuz',
  'Темиртау': 'Temirtau',
  'Рудный': 'Rudny',
  'Байконур': 'Baikonur',
  'Администратор не ответил за 24 часа. Заявка стала нейтральной: люди рядом могут проверить, существует ли это место. Для публикации нужны независимые подтверждения.':
      'The administrator did not respond within 24 hours. The submission is now neutral: people nearby can verify whether the place exists. Independent confirmations are required before publication.',
  'В спутниковом режиме используются снимки Esri, а названия городов остаются поверх карты.':
      'Satellite mode uses Esri imagery while city names remain visible over the map.',
  'Выбери, что происходит на этом участке. Данные временные и обновляются людьми рядом.':
      'Choose what is happening here. Reports are temporary and updated by people nearby.',
  'Отметь точку на тропинке или дороге. Предупреждение будет временным и исчезнет автоматически.':
      'Mark a point on a path or road. The warning is temporary and will disappear automatically.',
  'Выбирай сразу несколько категорий — например, туалеты и питьевую воду.':
      'Select several categories at once — for example, toilets and drinking water.',
  'Заявка отправлена. Пока точку видишь только ты на этом устройстве; после одобрения она появится у всех.':
      'Submission sent. For now, only you can see this place on this device; everyone will see it after approval.',
  'Нажми зелёный плюс, выбери точку и отправь её на проверку.':
      'Tap the green plus, choose a location, and submit it for review.',
  'Название, вода, АЗС, кафе, туалет…':
      'Name, water, gas station, café, toilet…',
  'Категория {label}: {state}': 'Category {label}: {state}',
  'Нет': 'No',
  'Передвинь карту или немного отдали её': 'Move the map or zoom out a little',
  'Подожди 5 минут перед новой заявкой на перенос этой точки':
      'Wait 5 minutes before submitting another location correction',
  'Подожди 5 минут перед следующим обновлением этой точки':
      'Wait 5 minutes before the next update for this place',
  'Покажем только точки в этой области':
      'Only places in this area will be shown',
  'Показываем опубликованные точки. Для воды — только места, отмеченные как питьевые.':
      'Published places are shown. For water, only points marked as safe to drink are included.',
  'После установки карта будет открываться с главного экрана как обычное приложение.':
      'Once installed, the map will open from your home screen like a regular app.',
  'Построить маршрут для проверки': 'Build a route to verify',
  'Приблизь нужный город': 'Zoom in on the city you need',
  'Рядом пока нет подтверждённых мест. Можно приблизить карту или добавить новую точку.':
      'There are no confirmed places nearby yet. Zoom in on the map or add a new place.',
  'Сначала заявку видишь только ты. Через 24 часа без ответа она станет нейтральной и появится у людей рядом для проверки.':
      'At first, only you can see the submission. If there is no response within 24 hours, it becomes neutral and appears to people nearby for verification.',
  'Туалет, кафе, организация, вода или зарядка — выбери точку рядом с собой либо на карте.':
      'Toilet, café, organization, water, or charging — choose your current location or a point on the map.',
  'Шаблон поставит 3 звезды, плохое состояние, отсутствие бумаги и мыла. Всё можно изменить ниже.':
      'The preset sets 3 stars, poor condition, and no paper or soap. You can change everything below.',
  'Это твоя заявка. Чтобы проверка была честной, подтвердить её должен другой человек со своего телефона.':
      'This is your submission. For a fair review, another person must confirm it from their phone.',
  '🆘 Сигнал «нужна бумага» виден людям рядом в течение 45 минут':
      '🆘 The “paper needed” alert is visible to people nearby for 45 minutes',
  'Все': 'All',
  'Все места': 'All places',
  'Все туалеты': 'All toilets',
  'Туалеты': 'Toilets',
  'Туалет': 'Toilet',
  'Общественный туалет': 'Public toilet',
  'Уличный / парковый': 'Street / park toilet',
  'Кафе': 'Café',
  'Кафе или ресторан': 'Café or restaurant',
  'Организация': 'Organization',
  'Заведение или организация': 'Venue or organization',
  'АЗС': 'Gas station',
  'Автозаправка': 'Gas station',
  'Автозаправочная станция': 'Gas station',
  'Вода': 'Water',
  'Питьевая вода': 'Drinking water',
  'Точка питьевой воды': 'Drinking water point',
  'Источник питьевой воды': 'Drinking water source',
  'Источник воды': 'Water source',
  'Точка набора воды': 'Water refill point',
  'Питьевой фонтанчик': 'Drinking fountain',
  'Родник': 'Spring',
  'Скважина или колодец': 'Borehole or well',
  'Уличная колонка': 'Street water pump',
  'Автомат для набора воды': 'Water refill machine',
  'Телефон': 'Phone',
  'Зарядка': 'Charging',
  'Зарядка телефона': 'Phone charging',
  'Зарядить телефон': 'Charge a phone',
  'Зарядка мобильных устройств': 'Mobile device charging',
  'Электро': 'EV',
  'Электрозарядка': 'EV charging',
  'Электрозарядная станция': 'EV charging station',
  'Электрозарядные станции': 'EV charging stations',
  'Зарядка электромобиля': 'Electric vehicle charging',
  'Дороги': 'Paths',
  'Добавить место': 'Add a place',
  'Новая точка': 'New place',
  'Новый туалет': 'New toilet',
  'Новое кафе': 'New café',
  'Новая организация': 'New organization',
  'Новая АЗС': 'New gas station',
  'Отмена': 'Cancel',
  'Продолжить': 'Continue',
  'Применить': 'Apply',
  'Закрыть': 'Close',
  'Показать всё': 'Show all',
  'Выбрать на карте': 'Choose on map',
  'Выбрать эту точку': 'Choose this point',
  'Отправить место': 'Submit place',
  'Отправить на проверку': 'Submit for review',
  'Опубликовать обновление': 'Publish update',
  'Опубликовать предупреждение': 'Publish warning',
  'Обновить информацию': 'Update information',
  'Обновить информацию или оставить отзыв':
      'Update information or leave feedback',
  'Исправить положение на карте': 'Correct map position',
  'Сохранить место': 'Save place',
  'Убрать из избранного': 'Remove from favorites',
  'Скопировать ссылку на место': 'Copy place link',
  'Приблизить карту': 'Zoom in',
  'Отдалить карту': 'Zoom out',
  'Предыдущие категории': 'Previous categories',
  'Ещё категории': 'More categories',
  'Избранное': 'Favorites',
  'Сохранённые места': 'Saved places',
  'Мои заявки': 'My submissions',
  'Заявка #{submissionId} отправлена. Ты уже видишь её на карте, остальные — после проверки.':
      'Submission #{submissionId} was sent. You can already see it on the map; everyone else will see it after review.',
  'Поиск места': 'Search for a place',
  'Найти место': 'Find a place',
  'Очистить поиск': 'Clear search',
  'Нужно сейчас': 'Needed now',
  'Нужно сейчас: туалет, вода или зарядка':
      'Needed now: toilet, water, or charging',
  'Самые близкие полезные места': 'Closest useful places',
  'Фильтры': 'Filters',
  'Что показать': 'What to show',
  'Только бесплатные': 'Free only',
  'Скрыть платные и без цены': 'Hide paid places and places without a price',
  'Доступно для коляски': 'Wheelchair accessible',
  'Только места с подтверждённым доступом': 'Only places with confirmed access',
  'Добавленные пользователями': 'Community-added',
  'Скрыть автоматически загруженные точки':
      'Hide automatically imported places',
  'Туалеты в кафе, АЗС и организациях':
      'Toilets in cafés, gas stations, and organizations',
  'Места с доступом для клиентов или посетителей':
      'Places available to customers or visitors',
  'Точки зарядки мобильных устройств': 'Mobile device charging points',
  'Зарядка для электромобилей': 'Electric vehicle charging',
  'Бесплатно': 'Free',
  'Бесплатный': 'Free',
  'Платно': 'Paid',
  'Платный': 'Paid',
  'Стоимость': 'Price',
  'Стоимость туалета': 'Toilet fee',
  'Стоимость воды': 'Water price',
  'Стоимость уточняется': 'Price to be confirmed',
  'Не указано': 'Not specified',
  'Не знаю': "I don't know",
  'неизвестно': 'unknown',
  'Не проверено': 'Not verified',
  'Не подтверждён': 'Unconfirmed',
  'Подтверждено': 'Confirmed',
  'Ожидает проверки': 'Awaiting review',
  'Одобрено и опубликовано': 'Approved and published',
  'Нужно уточнение': 'More information needed',
  'Нужна проверка людьми рядом': 'Needs verification by people nearby',
  'Есть': 'Yes',
  'нет': 'no',
  'Не нашли': 'Could not find it',
  'Не нашёл': "Couldn't find it",
  'Место есть': 'Place is there',
  'Подтвердили': 'Confirmed',
  'Всем': 'Everyone',
  'Для всех': 'Open to everyone',
  'Для клиентов': 'For customers',
  'Только клиентам': 'Customers only',
  'Обычно пускают': 'Usually allowed',
  'Обычно доступно': 'Usually accessible',
  'Для посетителей': 'For visitors',
  'Только посетителям': 'Visitors only',
  'Уточните на месте': 'Check on site',
  'Доступ': 'Access',
  'Кому можно зайти': 'Who can enter',
  'Доступ для коляски': 'Wheelchair access',
  'Для коляски': 'Wheelchair accessible',
  'Есть туалет': 'Toilet available',
  'Туалетная бумага': 'Toilet paper',
  'Бумага': 'Paper',
  'Мыло': 'Soap',
  'Можно зарядить телефон': 'Phone charging available',
  'Что есть внутри': 'Amenities',
  'Что есть на месте': 'Available here',
  'Можно пить': 'Safe to drink',
  'Не для питья': 'Not for drinking',
  'Набрать в тару': 'Fill a container',
  'Для питья': 'Drinking suitability',
  'Чистота': 'Cleanliness',
  'Состояние': 'Condition',
  'Общая оценка': 'Overall rating',
  'Текущая оценка': 'Current rating',
  'Хорошее': 'Good',
  'Среднее': 'Fair',
  'Плохое': 'Poor',
  '🟢  Хорошее': '🟢  Good',
  '🟡  Среднее': '🟡  Fair',
  '🔴  Плохое': '🔴  Poor',
  'Тип точки': 'Place type',
  'Тип туалета': 'Toilet type',
  'Категория': 'Category',
  'Название места': 'Place name',
  'Название или тип точки': 'Place name or type',
  'Комментарий': 'Comment',
  'Комментарий — необязательно': 'Comment — optional',
  'Отзыв или уточнение': 'Feedback or correction',
  'Имя': 'Name',
  'Как тебя называть?': 'What should we call you?',
  'Как называется это место?': 'What is this place called?',
  'Например: Мирас': 'For example: Miras',
  'Например: Библиотека': 'For example: Library',
  'Например: Кофейня у парка': 'For example: Café by the park',
  'Например: находится внутри ТЦ': 'For example: inside the shopping mall',
  'Например: бумага есть, вход со двора':
      'For example: paper available, courtyard entrance',
  'Например: розетка у стойки, работает круглосуточно':
      'For example: outlet by the counter, available 24/7',
  'Например: тропинка у моста полностью во льду':
      'For example: the path by the bridge is completely icy',
  'Напиши название места или организации':
      'Enter the place or organization name',
  'Сначала выбери категорию': 'Choose a category first',
  'Сначала выбери тип места: туалет, кафе, организацию или другое':
      'First choose a place type: toilet, café, organization, or other',
  'Нажми, что именно ты добавляешь. Так кафе не попадёт в туалеты.':
      'Choose what you are adding so a café is not listed as a toilet.',
  'Точка появится на карте после быстрой проверки.':
      'The place will appear on the map after a quick review.',
  'Обновление будет видно всем пользователям TMaps.':
      'The update will be visible to all TMaps users.',
  'Фильтры карты': 'Map filters',
  'Вид карты': 'Map view',
  'Слой карты': 'Map layer',
  'Обычная': 'Standard',
  'Обычный': 'Standard',
  'Спутник': 'Satellite',
  'Спутниковая карта': 'Satellite map',
  'Улицы и дома': 'Streets and buildings',
  'Снимки местности': 'Satellite imagery',
  'Переключай слой — точки и маршрут останутся на месте':
      'Switch layers without losing places or your route',
  'Источник данных карты': 'Map data source',
  'Источники спутниковой карты': 'Satellite imagery sources',
  'WC — ближайший туалет': 'WC — nearest toilet',
  'Ближайший туалет': 'Nearest toilet',
  'Моё местоположение': 'My location',
  'Я нахожусь здесь': 'I am here',
  'Рядом со мной': 'Near me',
  'Использовать текущее местоположение': 'Use current location',
  'GPS возьмёт координаты автоматически':
      'GPS will get the coordinates automatically',
  'GPS не включён': 'GPS is off',
  'Определяем местоположение…': 'Finding your location…',
  'Проверь геопозицию': 'Check your location settings',
  'Включи GPS на телефоне и повтори попытку':
      'Turn on GPS on your phone and try again',
  'Нажми и разреши геопозицию в браузере':
      'Tap and allow location access in your browser',
  'Нажми «Включить GPS» и разреши доступ к геопозиции':
      'Tap “Turn on GPS” and allow location access',
  'Разреши геопозицию для TMaps в настройках телефона':
      'Allow location access for TMaps in your phone settings',
  'Доступ заблокирован — нажми, чтобы исправить':
      'Access is blocked — tap to fix it',
  'Геопозиция работает': 'Location is working',
  'Нет координат — проверь разрешение браузера':
      'No coordinates — check browser permission',
  'Не удалось получить координаты. Проверь GPS и интернет':
      'Could not get coordinates. Check GPS and your internet connection',
  'Поможем включить GPS': 'Let’s turn on GPS',
  'Разреши доступ к геопозиции': 'Allow location access',
  'Проверить GPS': 'Check GPS',
  'Chrome или Android': 'Chrome or Android',
  'iPhone или Safari': 'iPhone or Safari',
  'Вернись в TMaps': 'Return to TMaps',
  'Открой настройки телефона': 'Open phone settings',
  'Включи точное местоположение': 'Turn on precise location',
  'Разреши приложению TMaps доступ к геопозиции.':
      'Allow the TMaps app to access your location.',
  'Проверь разрешение на геопозицию и повтори попытку.':
      'Check location permission and try again.',
  'Так синяя точка и расстояние до туалета будут точнее.':
      'This makes the blue dot and distance to the toilet more accurate.',
  'TMaps работает, но браузер заблокировал передачу координат этому сайту.':
      'TMaps is working, but the browser blocked location access for this site.',
  'Предупредить о дороге': 'Report a path issue',
  'Где проблема?': 'Where is the issue?',
  'Проблема на дороге': 'Path issue',
  'Отметить этот участок': 'Mark this section',
  'Пешеходная обстановка': 'Walking conditions',
  'Гололёд': 'Ice',
  'Ремонтные работы': 'Roadworks',
  'Снег или не расчищено': 'Snow or uncleared path',
  'Вода или подтопление': 'Water or flooding',
  'Препятствие на пути': 'Obstacle on path',
  'Проход закрыт': 'Path closed',
  'Проход открыт': 'Path open',
  'Скользкий участок — иди осторожно': 'Slippery section — walk carefully',
  'На пути идут ремонтные работы': 'Roadworks are underway',
  'Тропинка занесена или плохо расчищена':
      'The path is snow-covered or poorly cleared',
  'Проход затоплен или покрыт водой':
      'The path is flooded or covered with water',
  'На тропинке есть помеха для прохода': 'There is an obstacle on the path',
  'Пешеходный проход временно недоступен':
      'The pedestrian path is temporarily closed',
  'Участок проверен — пройти можно': 'Section checked — the path is open',
  'Гололёд, ремонт, снег или закрытый проход':
      'Ice, roadworks, snow, or a closed path',
  'Можно сообщить об участке вдали от себя':
      'You can report a section away from your location',
  'Наведи центр карты или удерживай нужное место':
      'Center the map or press and hold the right place',
  'Двигай карту — метка останется по центру':
      'Move the map — the marker will stay centered',
  'Предупреждение опубликовано и исчезнет автоматически':
      'Warning published; it will disappear automatically',
  'Погода рядом': 'Nearby weather',
  'Погода на карте': 'Map weather',
  'Погода · повторить': 'Weather · retry',
  'Погода по центру карты · данные Open-Meteo':
      'Weather at map center · Open-Meteo data',
  'Обновить погоду': 'Refresh weather',
  'Обновляю погоду…': 'Updating weather…',
  'Ощущается': 'Feels like',
  'Мин / макс': 'Min / max',
  'Вероятность осадков': 'Chance of precipitation',
  'Ветер': 'Wind',
  'Ясно': 'Clear',
  'Переменная облачность': 'Partly cloudy',
  'Пасмурно': 'Overcast',
  'Туман': 'Fog',
  'Морось': 'Drizzle',
  'Дождь': 'Rain',
  'Ливень': 'Heavy rain',
  'Снег': 'Snow',
  'Снегопад': 'Heavy snow',
  'Гроза': 'Thunderstorm',
  'Погода временно недоступна': 'Weather is temporarily unavailable',
  'Пока заявок нет': 'No submissions yet',
  'Точки, отправленные с этого устройства': 'Places submitted from this device',
  'Моя заявка · ожидает проверки': 'My submission · awaiting review',
  'Нейтральная заявка · нужна проверка рядом':
      'Community submission · needs nearby verification',
  'Добавлено пользователем TMaps': 'Added by a TMaps user',
  'Свою заявку должен подтвердить другой человек':
      'Someone else must confirm your submission',
  'Точка актуальна?': 'Is this place still accurate?',
  'Спасибо! Информация о месте обновлена':
      'Thank you! Place information has been updated',
  'Спасибо! Место подтверждено и опубликовано':
      'Thank you! The place has been confirmed and published',
  'Спасибо! Отметили, что место нужно проверить':
      'Thank you! The place has been flagged for review',
  'Спасибо! Ты подтвердил, что место актуально':
      'Thank you! You confirmed that the place is accurate',
  'Ссылка на место скопирована — отправь её другу':
      'Place link copied — send it to a friend',
  'Не удалось скопировать ссылку': 'Could not copy the link',
  'Рядом пока нет подтверждённых полезных мест':
      'There are no confirmed useful places nearby yet',
  'На карте пока нет туалетов': 'There are no toilets on the map yet',
  'Избранное пока пусто': 'Favorites are empty',
  'Открой любое место на карте и нажми на значок закладки':
      'Open any place on the map and tap the bookmark icon',
  'Добро пожаловать в TMaps': 'Welcome to TMaps',
  'Место сохранено в избранное': 'Place saved to favorites',
  'Место удалено из избранного': 'Place removed from favorites',
  'Расстояние по прямой': 'Straight-line distance',
  'Последний отзыв': 'Latest review',
  'Дата добавления точки': 'Date added',
  'Дата не указана': 'Date not specified',
  'Обновлено сегодня': 'Updated today',
  'Обновлено вчера': 'Updated yesterday',
  'Проверь место перед поездкой': 'Check the place before your trip',
  'Проверено командой TMaps': 'Verified by the TMaps team',
  'Последнее уточнение от человека': 'Latest community update',
  'Координаты уточнены сообществом': 'Coordinates corrected by the community',
  'Источник даты неизвестен': 'Date source unknown',
  'Свежесть исходной открытой базы': 'Freshness of the source open dataset',
  '{count} сохранено на этом устройстве': '{count} saved on this device',
  '{count} мест • все категории': '{count} places • all categories',
  '{count} мест • {scope}': '{count} places • {scope}',
  '{count} мест рядом — приблизить': '{count} nearby places — zoom in',
  '{count} мест рядом. Нажмите, чтобы приблизить':
      '{count} nearby places. Tap to zoom in',
  '{count} мест рядом': '{count} nearby places',
  '{count} категории': '{count} categories',
  '{count} предупреждения рядом с маршрутом': '{count} warnings near the route',
  '{label} рядом с маршрутом': '{label} near the route',
  'Дороги · {count}': 'Paths · {count}',
  'Мои заявки: {count}': 'My submissions: {count}',
  'Мои заявки · {count}': 'My submissions · {count}',
  'Избранное: {count}': 'Favorites: {count}',
  'Показано: {count}': 'Showing: {count}',
  '{count} точки по Казахстану': '{count} places across Kazakhstan',
  '{count} м': '{count} m',
  '{distance} км': '{distance} km',
  '{hours} ч {minutes} мин': '{hours} hr {minutes} min',
  '{hours} ч': '{hours} hr',
  '{minutes} мин': '{minutes} min',
  'Пешком · {duration}': 'Walking · {duration}',
  'Да · {count}': 'Yes · {count}',
  'Нет на месте · {count}': 'Not there · {count}',
  'Отзывы и обновления: {count} · Добавить':
      'Reviews and updates: {count} · Add',
  'Сообщил: {username}. Проверяй обстановку на месте — она может быстро измениться.':
      'Reported by {username}. Check conditions on site — they can change quickly.',
  'Не удалось отправить заявку: {error}': 'Could not submit the place: {error}',
  'Не удалось отправить перенос: {error}':
      'Could not submit the correction: {error}',
  'Не удалось отправить предупреждение: {error}':
      'Could not publish the warning: {error}',
  'Не удалось отправить сигнал помощи: {error}':
      'Could not send the help request: {error}',
  'Не удалось сохранить обновление: {error}':
      'Could not save the update: {error}',
  'Не удалось сохранить оценку: {error}': 'Could not save the rating: {error}',
  'Не удалось сохранить проверку: {error}':
      'Could not save the verification: {error}',
  'Не удалось сохранить выбранный слой карты':
      'Could not save the selected map layer',
  'Ошибка маршрута: {error}': 'Route error: {error}',
  '❌ Не удалось построить маршрут: {error}':
      '❌ Could not build a route: {error}',
};

const _kazakhTranslations = <String, String>{
  'Пеший маршрут': 'Жаяу жүру бағыты',
  'Строим пеший маршрут…': 'Жаяу жүру бағыты ізделуде…',
  'Обновляем пеший маршрут…': 'Жаяу жүру бағыты жаңартылуда…',
  'Вы отошли от маршрута': 'Бағыттан ауытқыдыңыз',
  'Маршрут на паузе: нет GPS': 'Бағыт кідіртілді: GPS сигналы жоқ',
  'Маршрут на паузе: неточный GPS': 'Бағыт кідіртілді: GPS дәлдігі төмен',
  'Не удалось построить маршрут': 'Бағыт табылмады',
  'Не удалось обновить маршрут': 'Бағытты жаңарту мүмкін болмады',
  'Верни сигнал GPS, чтобы обновить путь':
      'Бағытты жаңарту үшін GPS сигналын қалпына келтіріңіз',
  'Ждём более точные координаты': 'Дәлірек координаттар күтілуде',
  'Проверь интернет и повтори попытку':
      'Интернет байланысын тексеріп, қайталап көріңіз',
  'Проверяем отклонение от пути': 'Бағыттан ауытқу тексерілуде',
  'Обновить маршрут': 'Бағытты жаңарту',
  'Убрать маршрут': 'Бағытты алып тастау',
  'Предупреждений рядом с маршрутом: {count}':
      'Бағыт маңындағы ескертулер: {count}',
  'Настройки приложения': 'Қолданба баптаулары',
  'Язык': 'Тіл',
  'Как в системе': 'Жүйедегідей',
  'Оформление': 'Безендіру',
  'Как на телефоне': 'Телефондағыдай',
  'Светлая тема': 'Ашық тақырып',
  'Тёмная тема': 'Қараңғы тақырып',
  'Установить TMaps': 'TMaps қолданбасын орнату',
  'Общественные туалеты': 'Қоғамдық дәретханалар',
  'Добавленные туалеты': 'Қолданушылар қосқан дәретханалар',
  'Кафе и еда': 'Кафе және тамақ',
  'Заведения': 'Мекемелер',
  'Зарядка электромобилей': 'Электромобиль қуаттау',
  'Пользователь TMaps': 'TMaps пайдаланушысы',
  'Пешеходам: возможны снег и скользкие тропинки — выбирай очищенный маршрут.':
      'Жаяу жүргіншілерге: қар мен тайғақ соқпақтар болуы мүмкін — тазаланған бағытты таңдаңыз.',
  'Пешеходам: тропинки могут быть мокрыми и скользкими — иди осторожно.':
      'Жаяу жүргіншілерге: соқпақтар дымқыл әрі тайғақ болуы мүмкін — абайлап жүріңіз.',
  'Пешеходам: видимость снижена — переходи дороги особенно внимательно.':
      'Жаяу жүргіншілерге: көріну нашарлаған — жолдан өткенде аса мұқият болыңыз.',
  'Обновлено {count} дн. назад': '{count} күн бұрын жаңартылды',
  'Обновлено {count} нед. назад': '{count} апта бұрын жаңартылды',
  'Обновлено {count} мес. назад': '{count} ай бұрын жаңартылды',
  'Обновлено {count} г. назад': '{count} жыл бұрын жаңартылды',
  'Астана': 'Астана',
  'Алматы': 'Алматы',
  'Шымкент': 'Шымкент',
  'Талдыкорган': 'Талдықорған',
  'Караганда': 'Қарағанды',
  'Актобе': 'Ақтөбе',
  'Тараз': 'Тараз',
  'Павлодар': 'Павлодар',
  'Өскемен': 'Өскемен',
  'Семей': 'Семей',
  'Атырау': 'Атырау',
  'Костанай': 'Қостанай',
  'Кызылорда': 'Қызылорда',
  'Уральск': 'Орал',
  'Петропавловск': 'Петропавл',
  'Туркистан': 'Түркістан',
  'Актау': 'Ақтау',
  'Кокшетау': 'Көкшетау',
  'Жезказган': 'Жезқазған',
  'Конаев': 'Қонаев',
  'Текели': 'Текелі',
  'Экибастуз': 'Екібастұз',
  'Темиртау': 'Теміртау',
  'Рудный': 'Рудный',
  'Байконур': 'Байқоңыр',
  'Администратор не ответил за 24 часа. Заявка стала нейтральной: люди рядом могут проверить, существует ли это место. Для публикации нужны независимые подтверждения.':
      'Әкімші 24 сағат ішінде жауап бермеді. Өтінім бейтарап күйге өтті: маңайдағы адамдар бұл орынның бар-жоғын тексере алады. Жариялау үшін тәуелсіз растаулар қажет.',
  'В спутниковом режиме используются снимки Esri, а названия городов остаются поверх карты.':
      'Спутниктік режимде Esri суреттері қолданылады, ал қала атаулары картада көрініп тұрады.',
  'Выбери, что происходит на этом участке. Данные временные и обновляются людьми рядом.':
      'Бұл жерде не болып жатқанын таңдаңыз. Мәліметтер уақытша және оларды маңайдағы адамдар жаңартады.',
  'Отметь точку на тропинке или дороге. Предупреждение будет временным и исчезнет автоматически.':
      'Соқпақтағы немесе жолдағы нүктені белгілеңіз. Ескерту уақытша болады және автоматты түрде жоғалады.',
  'Выбирай сразу несколько категорий — например, туалеты и питьевую воду.':
      'Бірнеше санатты қатар таңдаңыз — мысалы, дәретханалар мен ауызсу.',
  'Заявка отправлена. Пока точку видишь только ты на этом устройстве; после одобрения она появится у всех.':
      'Өтінім жіберілді. Әзірге бұл орынды осы құрылғыда тек сіз көресіз; мақұлданғаннан кейін ол барлығына көрінеді.',
  'Нажми зелёный плюс, выбери точку и отправь её на проверку.':
      'Жасыл плюс белгісін басып, орынды таңдаңыз да тексеруге жіберіңіз.',
  'Название, вода, АЗС, кафе, туалет…': 'Атауы, су, ЖҚС, кафе, дәретхана…',
  'Категория {label}: {state}': '{label} санаты: {state}',
  'Нет': 'Жоқ',
  'Передвинь карту или немного отдали её':
      'Картаны жылжытыңыз немесе сәл кішірейтіңіз',
  'Подожди 5 минут перед новой заявкой на перенос этой точки':
      'Орынды түзетуге жаңа өтінім жібермес бұрын 5 минут күтіңіз',
  'Подожди 5 минут перед следующим обновлением этой точки':
      'Бұл орынды қайта жаңартпас бұрын 5 минут күтіңіз',
  'Покажем только точки в этой области':
      'Тек осы аймақтағы орындар көрсетіледі',
  'Показываем опубликованные точки. Для воды — только места, отмеченные как питьевые.':
      'Жарияланған орындар көрсетіледі. Су санатында тек ішуге жарамды деп белгіленген орындар бар.',
  'После установки карта будет открываться с главного экрана как обычное приложение.':
      'Орнатылғаннан кейін карта негізгі экраннан кәдімгі қолданба сияқты ашылады.',
  'Построить маршрут для проверки': 'Тексеру үшін бағыт құру',
  'Приблизь нужный город': 'Қажетті қаланы үлкейтіңіз',
  'Рядом пока нет подтверждённых мест. Можно приблизить карту или добавить новую точку.':
      'Маңайда әзірге расталған орындар жоқ. Картаны үлкейтуге немесе жаңа орын қосуға болады.',
  'Сначала заявку видишь только ты. Через 24 часа без ответа она станет нейтральной и появится у людей рядом для проверки.':
      'Алдымен өтінімді тек сіз көресіз. 24 сағат ішінде жауап болмаса, ол бейтарап күйге өтіп, маңайдағы адамдарға тексеру үшін көрінеді.',
  'Туалет, кафе, организация, вода или зарядка — выбери точку рядом с собой либо на карте.':
      'Дәретхана, кафе, ұйым, су немесе қуаттау орны — өз орныңызды не картадағы нүктені таңдаңыз.',
  'Шаблон поставит 3 звезды, плохое состояние, отсутствие бумаги и мыла. Всё можно изменить ниже.':
      'Үлгі 3 жұлдыз, нашар күй, қағаз бен сабын жоқ деп белгілейді. Төменде бәрін өзгертуге болады.',
  'Это твоя заявка. Чтобы проверка была честной, подтвердить её должен другой человек со своего телефона.':
      'Бұл сіздің өтініміңіз. Тексеру әділ болуы үшін оны басқа адам өз телефонынан растауы керек.',
  '🆘 Сигнал «нужна бумага» виден людям рядом в течение 45 минут':
      '🆘 «Қағаз қажет» сигналы маңайдағы адамдарға 45 минут бойы көрінеді',
  'Все': 'Барлығы',
  'Все места': 'Барлық орындар',
  'Все туалеты': 'Барлық дәретханалар',
  'Туалеты': 'Дәретханалар',
  'Туалет': 'Дәретхана',
  'Общественный туалет': 'Қоғамдық дәретхана',
  'Уличный / парковый': 'Көше / саябақ дәретханасы',
  'Кафе': 'Кафе',
  'Кафе или ресторан': 'Кафе немесе мейрамхана',
  'Организация': 'Ұйым',
  'Заведение или организация': 'Мекеме немесе ұйым',
  'АЗС': 'ЖҚС',
  'Автозаправка': 'Жанармай құю бекеті',
  'Автозаправочная станция': 'Жанармай құю бекеті',
  'Вода': 'Су',
  'Питьевая вода': 'Ауызсу',
  'Точка питьевой воды': 'Ауызсу нүктесі',
  'Источник питьевой воды': 'Ауызсу көзі',
  'Источник воды': 'Су көзі',
  'Точка набора воды': 'Су құю нүктесі',
  'Питьевой фонтанчик': 'Ауызсу бұрқағы',
  'Родник': 'Бұлақ',
  'Скважина или колодец': 'Ұңғыма немесе құдық',
  'Уличная колонка': 'Көше су бағанасы',
  'Автомат для набора воды': 'Су құю автоматы',
  'Телефон': 'Телефон',
  'Зарядка': 'Қуаттау',
  'Зарядка телефона': 'Телефонды қуаттау',
  'Зарядить телефон': 'Телефонды қуаттау',
  'Зарядка мобильных устройств': 'Мобильді құрылғыларды қуаттау',
  'Электро': 'Электр',
  'Электрозарядка': 'Электр қуаттау',
  'Электрозарядная станция': 'Электр қуаттау станциясы',
  'Электрозарядные станции': 'Электр қуаттау станциялары',
  'Зарядка электромобиля': 'Электр көлігін қуаттау',
  'Дороги': 'Жолдар',
  'Добавить место': 'Орын қосу',
  'Новая точка': 'Жаңа орын',
  'Новый туалет': 'Жаңа дәретхана',
  'Новое кафе': 'Жаңа кафе',
  'Новая организация': 'Жаңа ұйым',
  'Новая АЗС': 'Жаңа ЖҚС',
  'Отмена': 'Бас тарту',
  'Продолжить': 'Жалғастыру',
  'Применить': 'Қолдану',
  'Закрыть': 'Жабу',
  'Показать всё': 'Барлығын көрсету',
  'Выбрать на карте': 'Картадан таңдау',
  'Выбрать эту точку': 'Осы нүктені таңдау',
  'Отправить место': 'Орынды жіберу',
  'Отправить на проверку': 'Тексеруге жіберу',
  'Опубликовать обновление': 'Жаңартуды жариялау',
  'Опубликовать предупреждение': 'Ескертуді жариялау',
  'Обновить информацию': 'Ақпаратты жаңарту',
  'Обновить информацию или оставить отзыв':
      'Ақпаратты жаңарту немесе пікір қалдыру',
  'Исправить положение на карте': 'Картадағы орнын түзету',
  'Сохранить место': 'Орынды сақтау',
  'Убрать из избранного': 'Таңдаулылардан алып тастау',
  'Скопировать ссылку на место': 'Орын сілтемесін көшіру',
  'Приблизить карту': 'Картаны үлкейту',
  'Отдалить карту': 'Картаны кішірейту',
  'Предыдущие категории': 'Алдыңғы санаттар',
  'Ещё категории': 'Қосымша санаттар',
  'Избранное': 'Таңдаулылар',
  'Сохранённые места': 'Сақталған орындар',
  'Мои заявки': 'Менің өтінімдерім',
  'Заявка #{submissionId} отправлена. Ты уже видишь её на карте, остальные — после проверки.':
      '№{submissionId} өтінім жіберілді. Сіз оны картадан көре аласыз, ал басқалар тексерілгеннен кейін көреді.',
  'Поиск места': 'Орын іздеу',
  'Найти место': 'Орын табу',
  'Очистить поиск': 'Іздеуді тазарту',
  'Нужно сейчас': 'Қазір керек',
  'Нужно сейчас: туалет, вода или зарядка':
      'Қазір керек: дәретхана, су немесе қуаттау',
  'Самые близкие полезные места': 'Ең жақын пайдалы орындар',
  'Фильтры': 'Сүзгілер',
  'Фильтры карты': 'Карта сүзгілері',
  'Что показать': 'Нені көрсету керек',
  'Только бесплатные': 'Тек тегін',
  'Скрыть платные и без цены':
      'Ақылы және бағасы көрсетілмеген орындарды жасыру',
  'Доступно для коляски': 'Арбамен кіруге болады',
  'Только места с подтверждённым доступом':
      'Тек қолжетімділігі расталған орындар',
  'Добавленные пользователями': 'Пайдаланушылар қосқан',
  'Скрыть автоматически загруженные точки':
      'Автоматты түрде жүктелген орындарды жасыру',
  'Туалеты в кафе, АЗС и организациях':
      'Кафе, ЖҚС және ұйымдардағы дәретханалар',
  'Места с доступом для клиентов или посетителей':
      'Клиенттерге немесе келушілерге қолжетімді орындар',
  'Точки зарядки мобильных устройств':
      'Мобильді құрылғыларды қуаттау нүктелері',
  'Зарядка для электромобилей': 'Электр көліктерін қуаттау',
  'Бесплатно': 'Тегін',
  'Бесплатный': 'Тегін',
  'Платно': 'Ақылы',
  'Платный': 'Ақылы',
  'Стоимость': 'Бағасы',
  'Стоимость туалета': 'Дәретхана бағасы',
  'Стоимость воды': 'Су бағасы',
  'Стоимость уточняется': 'Бағасы нақтылануда',
  'Не указано': 'Көрсетілмеген',
  'Не знаю': 'Білмеймін',
  'неизвестно': 'белгісіз',
  'Не проверено': 'Тексерілмеген',
  'Не подтверждён': 'Расталмаған',
  'Подтверждено': 'Расталған',
  'Ожидает проверки': 'Тексеруді күтуде',
  'Одобрено и опубликовано': 'Мақұлданып, жарияланды',
  'Нужно уточнение': 'Нақтылау қажет',
  'Нужна проверка людьми рядом': 'Жақын маңдағы адамдар тексеруі керек',
  'Есть': 'Бар',
  'нет': 'жоқ',
  'Не нашли': 'Табылмады',
  'Не нашёл': 'Таппадым',
  'Место есть': 'Орын бар',
  'Подтвердили': 'Растады',
  'Всем': 'Барлығына',
  'Для всех': 'Барлығына ашық',
  'Для клиентов': 'Клиенттерге',
  'Только клиентам': 'Тек клиенттерге',
  'Обычно пускают': 'Әдетте кіргізеді',
  'Обычно доступно': 'Әдетте қолжетімді',
  'Для посетителей': 'Келушілерге',
  'Только посетителям': 'Тек келушілерге',
  'Уточните на месте': 'Орнында нақтылаңыз',
  'Доступ': 'Қолжетімділік',
  'Кому можно зайти': 'Кім кіре алады',
  'Доступ для коляски': 'Арбамен кіру мүмкіндігі',
  'Для коляски': 'Арбаға қолжетімді',
  'Есть туалет': 'Дәретхана бар',
  'Туалетная бумага': 'Дәретхана қағазы',
  'Бумага': 'Қағаз',
  'Мыло': 'Сабын',
  'Можно зарядить телефон': 'Телефонды қуаттауға болады',
  'Что есть внутри': 'Ішінде не бар',
  'Что есть на месте': 'Орнында не бар',
  'Можно пить': 'Ішуге болады',
  'Не для питья': 'Ішуге жарамсыз',
  'Набрать в тару': 'Ыдысқа құю',
  'Для питья': 'Ішуге жарамдылығы',
  'Чистота': 'Тазалық',
  'Состояние': 'Жағдайы',
  'Общая оценка': 'Жалпы баға',
  'Текущая оценка': 'Қазіргі баға',
  'Хорошее': 'Жақсы',
  'Среднее': 'Орташа',
  'Плохое': 'Нашар',
  '🟢  Хорошее': '🟢  Жақсы',
  '🟡  Среднее': '🟡  Орташа',
  '🔴  Плохое': '🔴  Нашар',
  'Тип точки': 'Орын түрі',
  'Тип туалета': 'Дәретхана түрі',
  'Категория': 'Санат',
  'Название места': 'Орын атауы',
  'Название или тип точки': 'Орын атауы немесе түрі',
  'Комментарий': 'Пікір',
  'Комментарий — необязательно': 'Пікір — міндетті емес',
  'Отзыв или уточнение': 'Пікір немесе нақтылау',
  'Имя': 'Аты',
  'Как тебя называть?': 'Сізді қалай атаймыз?',
  'Как называется это место?': 'Бұл орын қалай аталады?',
  'Например: Мирас': 'Мысалы: Мирас',
  'Например: Библиотека': 'Мысалы: Кітапхана',
  'Например: Кофейня у парка': 'Мысалы: Саябақ жанындағы кофехана',
  'Например: находится внутри ТЦ': 'Мысалы: сауда орталығының ішінде',
  'Например: бумага есть, вход со двора':
      'Мысалы: қағаз бар, аула жақтан кіреді',
  'Например: розетка у стойки, работает круглосуточно':
      'Мысалы: розетка үстел жанында, тәулік бойы жұмыс істейді',
  'Например: тропинка у моста полностью во льду':
      'Мысалы: көпір жанындағы соқпақты түгел мұз басқан',
  'Напиши название места или организации':
      'Орынның немесе ұйымның атауын жазыңыз',
  'Сначала выбери категорию': 'Алдымен санатты таңдаңыз',
  'Сначала выбери тип места: туалет, кафе, организацию или другое':
      'Алдымен орын түрін таңдаңыз: дәретхана, кафе, ұйым немесе басқа',
  'Нажми, что именно ты добавляешь. Так кафе не попадёт в туалеты.':
      'Нақты не қосатыныңызды таңдаңыз. Сонда кафе дәретханаларға кірмейді.',
  'Точка появится на карте после быстрой проверки.':
      'Орын қысқа тексеруден кейін картада пайда болады.',
  'Обновление будет видно всем пользователям TMaps.':
      'Жаңарту барлық TMaps пайдаланушысына көрінеді.',
  'Вид карты': 'Карта көрінісі',
  'Слой карты': 'Карта қабаты',
  'Обычная': 'Қалыпты',
  'Обычный': 'Қалыпты',
  'Спутник': 'Спутник',
  'Спутниковая карта': 'Спутниктік карта',
  'Улицы и дома': 'Көшелер мен үйлер',
  'Снимки местности': 'Жер бедерінің суреттері',
  'Переключай слой — точки и маршрут останутся на месте':
      'Қабатты ауыстырсаңыз, орындар мен бағыт сақталады',
  'Источник данных карты': 'Карта деректерінің көзі',
  'Источники спутниковой карты': 'Спутниктік карта көздері',
  'WC — ближайший туалет': 'WC — ең жақын дәретхана',
  'Ближайший туалет': 'Ең жақын дәретхана',
  'Моё местоположение': 'Менің орналасқан жерім',
  'Я нахожусь здесь': 'Мен осындамын',
  'Рядом со мной': 'Маған жақын',
  'Использовать текущее местоположение': 'Қазіргі орынды пайдалану',
  'GPS возьмёт координаты автоматически':
      'GPS координаттарды автоматты түрде анықтайды',
  'GPS не включён': 'GPS қосылмаған',
  'Определяем местоположение…': 'Орналасқан жеріңіз анықталуда…',
  'Проверь геопозицию': 'Геолокацияны тексеріңіз',
  'Включи GPS на телефоне и повтори попытку':
      'Телефондағы GPS-ті қосып, қайталап көріңіз',
  'Нажми и разреши геопозицию в браузере':
      'Басып, браузерде орналасқан жерге рұқсат беріңіз',
  'Нажми «Включить GPS» и разреши доступ к геопозиции':
      '«GPS-ті қосу» түймесін басып, орналасқан жерге рұқсат беріңіз',
  'Разреши геопозицию для TMaps в настройках телефона':
      'Телефон баптауларында TMaps үшін орналасқан жерге рұқсат беріңіз',
  'Доступ заблокирован — нажми, чтобы исправить':
      'Рұқсат бұғатталған — түзету үшін басыңыз',
  'Геопозиция работает': 'Орналасқан жер анықталды',
  'Нет координат — проверь разрешение браузера':
      'Координаттар жоқ — браузер рұқсатын тексеріңіз',
  'Не удалось получить координаты. Проверь GPS и интернет':
      'Координаттар алынбады. GPS пен интернетті тексеріңіз',
  'Поможем включить GPS': 'GPS-ті қосуға көмектесеміз',
  'Разреши доступ к геопозиции': 'Орналасқан жерге рұқсат беріңіз',
  'Проверить GPS': 'GPS-ті тексеру',
  'Chrome или Android': 'Chrome немесе Android',
  'iPhone или Safari': 'iPhone немесе Safari',
  'Вернись в TMaps': 'TMaps-қа оралыңыз',
  'Открой настройки телефона': 'Телефон баптауларын ашыңыз',
  'Включи точное местоположение': 'Нақты орналасқан жерді қосыңыз',
  'Разреши приложению TMaps доступ к геопозиции.':
      'TMaps қолданбасына орналасқан жерге рұқсат беріңіз.',
  'Проверь разрешение на геопозицию и повтори попытку.':
      'Орналасқан жер рұқсатын тексеріп, қайталап көріңіз.',
  'Так синяя точка и расстояние до туалета будут точнее.':
      'Сонда көк нүкте мен дәретханаға дейінгі қашықтық дәлірек болады.',
  'TMaps работает, но браузер заблокировал передачу координат этому сайту.':
      'TMaps жұмыс істеп тұр, бірақ браузер бұл сайтқа координаттарды беруге тыйым салды.',
  'Предупредить о дороге': 'Жол туралы ескерту',
  'Где проблема?': 'Мәселе қай жерде?',
  'Проблема на дороге': 'Жолдағы мәселе',
  'Отметить этот участок': 'Осы бөлікті белгілеу',
  'Пешеходная обстановка': 'Жаяу жүргінші жолының жағдайы',
  'Гололёд': 'Көктайғақ',
  'Ремонтные работы': 'Жөндеу жұмыстары',
  'Снег или не расчищено': 'Қар немесе тазаланбаған',
  'Вода или подтопление': 'Су немесе су басу',
  'Препятствие на пути': 'Жолдағы кедергі',
  'Проход закрыт': 'Өткел жабық',
  'Проход открыт': 'Өткел ашық',
  'Скользкий участок — иди осторожно': 'Тайғақ жер — абайлап жүріңіз',
  'На пути идут ремонтные работы': 'Жолда жөндеу жұмыстары жүріп жатыр',
  'Тропинка занесена или плохо расчищена':
      'Соқпақты қар басқан немесе нашар тазаланған',
  'Проход затоплен или покрыт водой': 'Өткелді су басқан',
  'На тропинке есть помеха для прохода': 'Соқпақта өтуге кедергі бар',
  'Пешеходный проход временно недоступен':
      'Жаяу жүргіншілер өткелі уақытша жабық',
  'Участок проверен — пройти можно': 'Бөлік тексерілді — өтуге болады',
  'Гололёд, ремонт, снег или закрытый проход':
      'Көктайғақ, жөндеу, қар немесе жабық өткел',
  'Можно сообщить об участке вдали от себя':
      'Өзіңізден алыс жердегі мәселе туралы хабарлауға болады',
  'Наведи центр карты или удерживай нужное место':
      'Карта ортасын бағыттаңыз немесе қажетті орынды басып тұрыңыз',
  'Двигай карту — метка останется по центру':
      'Картаны жылжытыңыз — белгі ортада қалады',
  'Предупреждение опубликовано и исчезнет автоматически':
      'Ескерту жарияланды және автоматты түрде жойылады',
  'Погода рядом': 'Маңайдағы ауа райы',
  'Погода на карте': 'Картадағы ауа райы',
  'Погода · повторить': 'Ауа райы · қайталау',
  'Погода по центру карты · данные Open-Meteo':
      'Карта ортасындағы ауа райы · Open-Meteo деректері',
  'Обновить погоду': 'Ауа райын жаңарту',
  'Обновляю погоду…': 'Ауа райы жаңартылуда…',
  'Ощущается': 'Сезілуі',
  'Мин / макс': 'Мин / макс',
  'Вероятность осадков': 'Жауын-шашын ықтималдығы',
  'Ветер': 'Жел',
  'Ясно': 'Ашық',
  'Переменная облачность': 'Ала бұлтты',
  'Пасмурно': 'Бұлтты',
  'Туман': 'Тұман',
  'Морось': 'Сіркіреме жаңбыр',
  'Дождь': 'Жаңбыр',
  'Ливень': 'Нөсер',
  'Снег': 'Қар',
  'Снегопад': 'Қалың қар',
  'Гроза': 'Найзағай',
  'Погода временно недоступна': 'Ауа райы уақытша қолжетімсіз',
  'Пока заявок нет': 'Әзірге өтінімдер жоқ',
  'Точки, отправленные с этого устройства': 'Осы құрылғыдан жіберілген орындар',
  'Моя заявка · ожидает проверки': 'Менің өтінімім · тексеруді күтуде',
  'Нейтральная заявка · нужна проверка рядом':
      'Қоғамдық өтінім · маңайдағы адамдар тексеруі керек',
  'Добавлено пользователем TMaps': 'TMaps пайдаланушысы қосқан',
  'Свою заявку должен подтвердить другой человек':
      'Өтініміңізді басқа адам растауы керек',
  'Точка актуальна?': 'Орын туралы ақпарат өзекті ме?',
  'Спасибо! Информация о месте обновлена':
      'Рақмет! Орын туралы ақпарат жаңартылды',
  'Спасибо! Место подтверждено и опубликовано':
      'Рақмет! Орын расталып, жарияланды',
  'Спасибо! Отметили, что место нужно проверить':
      'Рақмет! Орын тексерілуі керек деп белгіленді',
  'Спасибо! Ты подтвердил, что место актуально':
      'Рақмет! Орын туралы ақпараттың өзекті екенін растадыңыз',
  'Ссылка на место скопирована — отправь её другу':
      'Орын сілтемесі көшірілді — досыңызға жіберіңіз',
  'Не удалось скопировать ссылку': 'Сілтемені көшіру мүмкін болмады',
  'Рядом пока нет подтверждённых полезных мест':
      'Маңайда әзірге расталған пайдалы орындар жоқ',
  'На карте пока нет туалетов': 'Картада әзірге дәретханалар жоқ',
  'Избранное пока пусто': 'Таңдаулылар әзірге бос',
  'Открой любое место на карте и нажми на значок закладки':
      'Картадан кез келген орынды ашып, бетбелгі белгішесін басыңыз',
  'Добро пожаловать в TMaps': 'TMaps-қа қош келдіңіз',
  'Место сохранено в избранное': 'Орын таңдаулыларға сақталды',
  'Место удалено из избранного': 'Орын таңдаулылардан алынды',
  'Расстояние по прямой': 'Түзу сызықпен қашықтық',
  'Последний отзыв': 'Соңғы пікір',
  'Дата добавления точки': 'Орынның қосылған күні',
  'Дата не указана': 'Күні көрсетілмеген',
  'Обновлено сегодня': 'Бүгін жаңартылды',
  'Обновлено вчера': 'Кеше жаңартылды',
  'Проверь место перед поездкой': 'Бармас бұрын орынды тексеріңіз',
  'Проверено командой TMaps': 'TMaps командасы тексерген',
  'Последнее уточнение от человека': 'Адамның соңғы нақтылауы',
  'Координаты уточнены сообществом': 'Координаттарды қауымдастық түзетті',
  'Источник даты неизвестен': 'Күн дереккөзі белгісіз',
  'Свежесть исходной открытой базы':
      'Бастапқы ашық дерекқордың жаңартылғандығы',
  '{count} сохранено на этом устройстве':
      'Осы құрылғыда {count} орын сақталған',
  '{count} мест • все категории': '{count} орын • барлық санат',
  '{count} мест • {scope}': '{count} орын • {scope}',
  '{count} мест рядом — приблизить': 'Маңайда {count} орын бар — үлкейту',
  '{count} мест рядом. Нажмите, чтобы приблизить':
      'Маңайда {count} орын бар. Үлкейту үшін басыңыз',
  '{count} мест рядом': 'Маңайда {count} орын',
  '{count} категории': '{count} санат',
  '{count} предупреждения рядом с маршрутом':
      'Бағыт маңында {count} ескерту бар',
  '{label} рядом с маршрутом': 'Бағыт маңында: {label}',
  'Дороги · {count}': 'Жолдар · {count}',
  'Мои заявки: {count}': 'Менің өтінімдерім: {count}',
  'Мои заявки · {count}': 'Менің өтінімдерім · {count}',
  'Избранное: {count}': 'Таңдаулылар: {count}',
  'Показано: {count}': 'Көрсетілгені: {count}',
  '{count} точки по Казахстану': 'Қазақстан бойынша {count} орын',
  '{count} м': '{count} м',
  '{distance} км': '{distance} км',
  '{hours} ч {minutes} мин': '{hours} сағ {minutes} мин',
  '{hours} ч': '{hours} сағ',
  '{minutes} мин': '{minutes} мин',
  'Пешком · {duration}': 'Жаяу · {duration}',
  'Да · {count}': 'Иә · {count}',
  'Нет на месте · {count}': 'Орнында жоқ · {count}',
  'Отзывы и обновления: {count} · Добавить':
      'Пікірлер мен жаңартулар: {count} · Қосу',
  'Сообщил: {username}. Проверяй обстановку на месте — она может быстро измениться.':
      'Хабарлаған: {username}. Жағдайды орнында тексеріңіз — ол тез өзгеруі мүмкін.',
  'Не удалось отправить заявку: {error}':
      'Өтінімді жіберу мүмкін болмады: {error}',
  'Не удалось отправить перенос: {error}':
      'Орынды түзету өтінімін жіберу мүмкін болмады: {error}',
  'Не удалось отправить предупреждение: {error}':
      'Ескертуді жариялау мүмкін болмады: {error}',
  'Не удалось отправить сигнал помощи: {error}':
      'Көмек сұрауын жіберу мүмкін болмады: {error}',
  'Не удалось сохранить обновление: {error}':
      'Жаңартуды сақтау мүмкін болмады: {error}',
  'Не удалось сохранить оценку: {error}':
      'Бағаны сақтау мүмкін болмады: {error}',
  'Не удалось сохранить проверку: {error}':
      'Тексеру нәтижесін сақтау мүмкін болмады: {error}',
  'Не удалось сохранить выбранный слой карты':
      'Таңдалған карта қабатын сақтау мүмкін болмады',
  'Ошибка маршрута: {error}': 'Бағыт қатесі: {error}',
  '❌ Не удалось построить маршрут: {error}':
      '❌ Бағытты құру мүмкін болмады: {error}',
};
