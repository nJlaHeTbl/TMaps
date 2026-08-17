enum PlaceKind {
  publicToilet,
  communityToilet,
  cafe,
  fuel,
  organization,
  phoneCharging,
  evCharging,
  water,
}

class PlaceInfo {
  PlaceInfo._();

  static PlaceKind kindOf(Map<String, dynamic> place) {
    return switch (place['place_kind']?.toString()) {
      'community_toilet' => PlaceKind.communityToilet,
      'cafe' => PlaceKind.cafe,
      'fuel' => PlaceKind.fuel,
      'organization' => PlaceKind.organization,
      'phone_charging' => PlaceKind.phoneCharging,
      'ev_charging' => PlaceKind.evCharging,
      'water' => PlaceKind.water,
      _ => PlaceKind.publicToilet,
    };
  }

  static bool hasToilet(Map<String, dynamic> place) {
    final kind = kindOf(place);
    final reportedValue = effectiveValue(place, 'has_toilet');
    return reportedValue == true ||
        (reportedValue != false &&
            kind != PlaceKind.phoneCharging &&
            kind != PlaceKind.evCharging &&
            kind != PlaceKind.water);
  }

  static bool isVenue(Map<String, dynamic> place) {
    final kind = kindOf(place);
    return kind == PlaceKind.cafe ||
        kind == PlaceKind.fuel ||
        kind == PlaceKind.organization;
  }

  static String valueOfKind(PlaceKind kind) {
    return switch (kind) {
      PlaceKind.publicToilet => 'public_toilet',
      PlaceKind.communityToilet => 'community_toilet',
      PlaceKind.cafe => 'cafe',
      PlaceKind.fuel => 'fuel',
      PlaceKind.organization => 'organization',
      PlaceKind.phoneCharging => 'phone_charging',
      PlaceKind.evCharging => 'ev_charging',
      PlaceKind.water => 'water',
    };
  }

  static String keyOf(Map<String, dynamic> place) {
    final existing = place['place_key']?.toString();
    if (existing != null && existing.isNotEmpty) return existing;

    if (place['source'] == 'openstreetmap') {
      return 'osm:${place['source_id']}';
    }

    return 'community:${place['id'] ?? '${place['lat']}:${place['lng']}'}';
  }

  static String titleOf(Map<String, dynamic> place) {
    final name = place['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;

    return switch (kindOf(place)) {
      PlaceKind.cafe => 'Кафе или ресторан',
      PlaceKind.fuel => 'Автозаправка',
      PlaceKind.organization => 'Заведение или организация',
      PlaceKind.phoneCharging => 'Зарядка телефона',
      PlaceKind.evCharging => 'Зарядка электромобиля',
      PlaceKind.water => waterTypeLabel(place),
      _ => 'Туалет',
    };
  }

  static String kindLabel(Map<String, dynamic> place) {
    return switch (kindOf(place)) {
      PlaceKind.cafe => 'Кафе или ресторан',
      PlaceKind.fuel => 'Автозаправочная станция',
      PlaceKind.organization => 'Организация',
      PlaceKind.phoneCharging => 'Зарядка мобильных устройств',
      PlaceKind.evCharging => 'Электрозарядная станция',
      PlaceKind.water => 'Источник воды',
      PlaceKind.communityToilet => 'Добавлено пользователем TMaps',
      PlaceKind.publicToilet => 'Общественный туалет',
    };
  }

  static String accessLabel(Map<String, dynamic> place) {
    return switch (effectiveValue(place, 'access_type')?.toString()) {
      'public' || 'yes' => 'Для всех',
      'customers' || 'customer' => 'Для клиентов',
      'permissive' => 'Обычно доступно',
      'destination' => 'Для посетителей',
      _ => 'Уточните на месте',
    };
  }

  static bool? drinkingWater(Map<String, dynamic> place) {
    final value = effectiveValue(place, 'drinking_water');
    if (value is bool) return value;
    return switch (value?.toString().toLowerCase()) {
      'yes' || 'true' || '1' => true,
      'no' || 'false' || '0' => false,
      _ => null,
    };
  }

  static String waterTypeLabel(Map<String, dynamic> place) {
    return switch (effectiveValue(place, 'water_type')?.toString()) {
      'vending_machine' => 'Автомат для набора воды',
      'water_well' => 'Скважина или колодец',
      'water_tap' => 'Уличная колонка',
      'drinking_fountain' => 'Питьевой фонтанчик',
      'spring' => 'Родник',
      'water_point' => 'Точка набора воды',
      _ => 'Источник питьевой воды',
    };
  }

  static Map<String, dynamic>? latestReport(Map<String, dynamic> place) {
    final value = place['latest_report'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static dynamic effectiveValue(Map<String, dynamic> place, String key) {
    return latestReport(place)?[key] ?? place[key];
  }

  static int reportCount(Map<String, dynamic> place) {
    return (place['report_count'] as num?)?.toInt() ?? 0;
  }
}
