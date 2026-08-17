import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _overpassUrls = [
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://overpass-api.de/api/interpreter',
  'https://z.overpass-api.de/api/interpreter',
];
const _outputPath = 'assets/data/kazakhstan_toilets.json';

const _query = '''
[out:json][timeout:180];
area["ISO3166-1"="KZ"][admin_level=2]->.kz;
(
  nwr["amenity"="toilets"]["access"!~"^(private|no)\$"](area.kz);
  nwr["toilets"="yes"]["toilets:access"!~"^(private|no)\$"](area.kz);
  nwr["amenity"="device_charging_station"]["access"!~"^(private|no)\$"](area.kz);
  nwr["amenity"="charging_station"]["access"!~"^(private|no)\$"](area.kz);
  nwr["socket:device:USB-A"]["socket:device:USB-A"!~"^(no|0)\$"]["access"!~"^(private|no)\$"](area.kz);
  nwr["socket:device:USB-C"]["socket:device:USB-C"!~"^(no|0)\$"]["access"!~"^(private|no)\$"](area.kz);
  nwr["socket:device:Lightning"]["socket:device:Lightning"!~"^(no|0)\$"]["access"!~"^(private|no)\$"](area.kz);
  node["amenity"="drinking_water"]["access"!~"^(private|no)\$"](area.kz);
  node["amenity"="vending_machine"]["vending"~"(^|;)(water|drinking_water)(;|\$)"]["access"!~"^(private|no)\$"](area.kz);
  node["man_made"="water_well"]["drinking_water"!="no"]["access"!~"^(private|no)\$"](area.kz);
  node["man_made"="water_tap"]["drinking_water"!="no"]["access"!~"^(private|no)\$"](area.kz);
  node["man_made"="drinking_fountain"]["access"!~"^(private|no)\$"](area.kz);
  node["natural"="spring"]["drinking_water"="yes"]["access"!~"^(private|no)\$"](area.kz);
  node["amenity"="water_point"]["drinking_water"="yes"]["access"!~"^(private|no)\$"](area.kz);
  nwr["amenity"~"^(cafe|restaurant|fast_food|food_court|pub|bar)\$"](44.80,78.10,45.25,78.65);
);
out center tags;
''';

Future<void> main() async {
  stdout.writeln('Downloading public toilets from OpenStreetMap...');

  http.Response? response;

  for (final url in _overpassUrls) {
    stdout.writeln('Trying $url');

    try {
      final candidate = await http
          .post(
            Uri.parse(url),
            headers: const {
              'User-Agent': 'TMaps/1.0 (OpenStreetMap data import)',
            },
            body: {'data': _query},
          )
          .timeout(const Duration(minutes: 4));

      if (candidate.statusCode == 200) {
        response = candidate;
        break;
      }

      stderr.writeln('$url returned HTTP ${candidate.statusCode}.');
    } on Object catch (error) {
      stderr.writeln('$url failed: $error');
    }
  }

  if (response == null) {
    stderr.writeln('All Overpass servers failed. Try again later.');
    exitCode = 1;
    return;
  }

  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  final elements = payload['elements'] as List<dynamic>;
  final placesBySource = <String, Map<String, dynamic>>{};

  for (final rawElement in elements) {
    final element = rawElement as Map<String, dynamic>;
    final tags = Map<String, dynamic>.from(
      element['tags'] as Map? ?? const <String, dynamic>{},
    );
    final center = element['center'] as Map<String, dynamic>?;
    final latitude = (element['lat'] ?? center?['lat']) as num?;
    final longitude = (element['lon'] ?? center?['lon']) as num?;

    if (latitude == null || longitude == null) continue;

    final type = element['type'] as String;
    final id = element['id'].toString();
    final name = _firstText(tags, ['name:ru', 'name:kk', 'name']);
    final amenity = tags['amenity']?.toString();
    final manMade = tags['man_made']?.toString();
    final isDedicatedToilet = amenity == 'toilets';
    final isEvCharging = amenity == 'charging_station';
    final hasToilet = isDedicatedToilet || tags['toilets'] == 'yes';
    final hasPhoneCharging =
        amenity == 'device_charging_station' ||
        _isAvailable(tags['socket:device:USB-A']) ||
        _isAvailable(tags['socket:device:USB-C']) ||
        _isAvailable(tags['socket:device:Lightning']);
    final isPhoneChargingPlace =
        hasPhoneCharging && !hasToilet && !isEvCharging;
    final waterType = _waterType(tags);
    final isWaterPlace = waterType != null;
    final drinkingWater = _drinkingWater(tags, waterType);
    final placeKind = _placeKind(
      tags,
      isPhoneChargingPlace,
      isDedicatedToilet,
      isEvCharging,
      isWaterPlace,
    );
    final feeKey = hasToilet && !isDedicatedToilet ? 'toilets:fee' : 'fee';
    final fee = tags[feeKey]?.toString().toLowerCase();
    final isWaterVending = waterType == 'vending_machine';
    final freeDrinkingWater =
        amenity == 'drinking_water' || manMade == 'drinking_fountain';
    final feeKnown =
        fee == 'yes' || fee == 'no' || isWaterVending || freeDrinkingWater;
    final isFree = fee == 'no' || (freeDrinkingWater && fee != 'yes');
    final sourceId = '$type/$id';
    final accessType =
        isPhoneChargingPlace ||
            isDedicatedToilet ||
            isEvCharging ||
            isWaterPlace
        ? tags['access']?.toString()
        : tags['toilets:access']?.toString();
    final fallbackName = isWaterPlace
        ? _waterTypeLabel(waterType)
        : isEvCharging
        ? 'Электрозарядная станция'
        : isPhoneChargingPlace
        ? 'Зарядка телефона'
        : isDedicatedToilet
        ? 'Общественный туалет'
        : hasToilet
        ? _placeKindLabel(placeKind)
        : 'Туалет пока не подтверждён';

    placesBySource[sourceId] = {
      'lat': latitude.toDouble(),
      'lng': longitude.toDouble(),
      'username': 'OpenStreetMap',
      'name': name,
      'place_kind': placeKind,
      'has_toilet': hasToilet,
      'access_type': accessType ?? (isDedicatedToilet ? 'public' : 'unknown'),
      'is_free': isFree,
      'fee_known': feeKnown,
      'cleanliness': 0,
      'condition': 'Не указано',
      'comment': name ?? fallbackName,
      'source': 'openstreetmap',
      'source_id': sourceId,
      'source_url': 'https://www.openstreetmap.org/$type/$id',
      'wheelchair': tags['toilets:wheelchair'] ?? tags['wheelchair'],
      'opening_hours': tags['opening_hours'],
      'has_paper': tags['toilets:paper_supplied'],
      'has_soap': tags['handwashing:soap'],
      'phone_charging': hasPhoneCharging,
      'ev_charging': isEvCharging,
      'drinking_water': drinkingWater,
      'water_type': waterType,
      'water_refill': _waterRefill(tags, waterType),
      'pump': tags['pump'],
      'socket_usb_a': tags['socket:device:USB-A'],
      'socket_usb_c': tags['socket:device:USB-C'],
      'socket_lightning': tags['socket:device:Lightning'],
    };
  }

  final places = placesBySource.values.toList();

  places.sort((a, b) {
    final latitude = (a['lat'] as double).compareTo(b['lat'] as double);
    return latitude != 0
        ? latitude
        : (a['lng'] as double).compareTo(b['lng'] as double);
  });

  final output = const JsonEncoder.withIndent('  ').convert({
    'source': 'OpenStreetMap contributors',
    'license': 'ODbL 1.0',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'count': places.length,
    'places': places,
  });

  await File(_outputPath).writeAsString('$output\n');
  stdout.writeln('Saved ${places.length} places to $_outputPath');
}

String _placeKind(
  Map<String, dynamic> tags,
  bool isPhoneCharging,
  bool isDedicatedToilet,
  bool isEvCharging,
  bool isWater,
) {
  if (isWater) return 'water';
  if (isEvCharging) return 'ev_charging';
  if (isPhoneCharging) return 'phone_charging';
  if (isDedicatedToilet) return 'public_toilet';

  return switch (tags['amenity']?.toString()) {
    'cafe' ||
    'restaurant' ||
    'fast_food' ||
    'food_court' ||
    'pub' ||
    'bar' => 'cafe',
    'fuel' => 'fuel',
    _ => 'organization',
  };
}

String? _waterType(Map<String, dynamic> tags) {
  final amenity = tags['amenity']?.toString();
  final manMade = tags['man_made']?.toString();
  final vending = tags['vending']
      ?.toString()
      .split(';')
      .map((value) => value.trim())
      .toSet();

  if (amenity == 'vending_machine' &&
      (vending?.contains('water') == true ||
          vending?.contains('drinking_water') == true)) {
    return 'vending_machine';
  }
  if (manMade == 'water_well') return 'water_well';
  if (manMade == 'water_tap') return 'water_tap';
  if (manMade == 'drinking_fountain') return 'drinking_fountain';
  if (tags['natural'] == 'spring') return 'spring';
  if (amenity == 'water_point') return 'water_point';
  if (amenity == 'drinking_water') return 'drinking_water';
  return null;
}

bool? _drinkingWater(Map<String, dynamic> tags, String? waterType) {
  final tagged = tags['drinking_water']?.toString().toLowerCase();
  if (tagged == 'yes') return true;
  if (tagged == 'no') return false;
  if (waterType == 'vending_machine' ||
      waterType == 'drinking_fountain' ||
      tags['amenity'] == 'drinking_water') {
    return true;
  }
  return null;
}

bool? _waterRefill(Map<String, dynamic> tags, String? waterType) {
  final bottle = tags['bottle']?.toString().toLowerCase();
  if (bottle == 'yes') return true;
  if (bottle == 'no') return false;
  return switch (waterType) {
    'vending_machine' ||
    'water_well' ||
    'water_tap' ||
    'water_point' ||
    'spring' => true,
    _ => null,
  };
}

String _waterTypeLabel(String? waterType) {
  return switch (waterType) {
    'vending_machine' => 'Автомат для набора воды',
    'water_well' => 'Скважина или колодец',
    'water_tap' => 'Уличная колонка',
    'drinking_fountain' => 'Питьевой фонтанчик',
    'spring' => 'Родник',
    'water_point' => 'Точка набора воды',
    _ => 'Источник питьевой воды',
  };
}

String _placeKindLabel(String placeKind) {
  return switch (placeKind) {
    'cafe' => 'Кафе с туалетом',
    'fuel' => 'АЗС с туалетом',
    'ev_charging' => 'Электрозарядная станция',
    _ => 'Организация с туалетом',
  };
}

bool _isAvailable(dynamic value) {
  final normalized = value?.toString().toLowerCase();
  return normalized != null && normalized != 'no' && normalized != '0';
}

String? _firstText(Map<String, dynamic> tags, List<String> keys) {
  for (final key in keys) {
    final value = tags[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
