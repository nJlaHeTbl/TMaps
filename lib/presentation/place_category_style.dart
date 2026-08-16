import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/place_info.dart';

extension PlaceKindStyle on PlaceKind {
  String get shortLabel => switch (this) {
    PlaceKind.publicToilet => 'Обществ.',
    PlaceKind.communityToilet => 'От людей',
    PlaceKind.cafe => 'Еда',
    PlaceKind.fuel => 'АЗС',
    PlaceKind.organization => 'Места',
    PlaceKind.phoneCharging => 'Телефон',
    PlaceKind.evCharging => 'Электро',
  };

  IconData get icon => switch (this) {
    PlaceKind.publicToilet => Icons.wc_rounded,
    PlaceKind.communityToilet => Icons.groups_rounded,
    PlaceKind.cafe => Icons.ramen_dining_rounded,
    PlaceKind.fuel => Icons.local_gas_station_rounded,
    PlaceKind.organization => Icons.storefront_rounded,
    PlaceKind.phoneCharging => Icons.battery_charging_full_rounded,
    PlaceKind.evCharging => Icons.ev_station_rounded,
  };

  Color get color => switch (this) {
    PlaceKind.publicToilet => AppPalette.emerald,
    PlaceKind.communityToilet => AppPalette.pink,
    PlaceKind.cafe => AppPalette.coral,
    PlaceKind.fuel => AppPalette.violet,
    PlaceKind.organization => const Color(0xFF0F766E),
    PlaceKind.phoneCharging => AppPalette.sky,
    PlaceKind.evCharging => AppPalette.aqua,
  };
}
