import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _overpassUrls = [
  'https://overpass.private.coffee/api/interpreter',
  'https://overpass-api.de/api/interpreter',
  'https://z.overpass-api.de/api/interpreter',
];
const _outputPath = 'assets/data/kazakhstan_toilets.json';

const _query = '''
[out:json][timeout:180];
area["ISO3166-1"="KZ"][admin_level=2]->.kz;
nwr["amenity"="toilets"](area.kz);
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
  final toilets = <Map<String, dynamic>>[];

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
    final fee = tags['fee']?.toString().toLowerCase();
    final feeKnown = fee == 'yes' || fee == 'no';

    toilets.add({
      'lat': latitude.toDouble(),
      'lng': longitude.toDouble(),
      'username': 'OpenStreetMap',
      'is_free': fee == 'no',
      'fee_known': feeKnown,
      'cleanliness': 0,
      'condition': 'Не указано',
      'comment': name ?? 'Общественный туалет',
      'source': 'openstreetmap',
      'source_id': '$type/$id',
      'source_url': 'https://www.openstreetmap.org/$type/$id',
      'wheelchair': tags['wheelchair'],
      'opening_hours': tags['opening_hours'],
    });
  }

  toilets.sort((a, b) {
    final latitude = (a['lat'] as double).compareTo(b['lat'] as double);
    return latitude != 0
        ? latitude
        : (a['lng'] as double).compareTo(b['lng'] as double);
  });

  final output = const JsonEncoder.withIndent('  ').convert({
    'source': 'OpenStreetMap contributors',
    'license': 'ODbL 1.0',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'count': toilets.length,
    'toilets': toilets,
  });

  await File(_outputPath).writeAsString('$output\n');
  stdout.writeln('Saved ${toilets.length} toilets to $_outputPath');
}

String? _firstText(Map<String, dynamic> tags, List<String> keys) {
  for (final key in keys) {
    final value = tags[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
