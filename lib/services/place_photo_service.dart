import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacePhoto {
  const PlacePhoto({
    required this.url,
    required this.sourceUrl,
    required this.author,
    required this.license,
  });
  final Uri url;
  final Uri sourceUrl;
  final String author;
  final String license;

  Uri get licenseUrl {
    if (license.startsWith('CC BY-SA ')) {
      return Uri.parse(
        'https://creativecommons.org/licenses/by-sa/${license.split(' ').last}/',
      );
    }
    if (license.startsWith('CC BY ')) {
      return Uri.parse(
        'https://creativecommons.org/licenses/by/${license.split(' ').last}/',
      );
    }
    return Uri.parse(
      license.startsWith('CC0')
          ? 'https://creativecommons.org/publicdomain/zero/1.0/'
          : 'https://commons.wikimedia.org/wiki/Commons:Public_domain',
    );
  }
}

class PlacePhotoService {
  const PlacePhotoService({this.client});
  final http.Client? client;

  // Only exact Commons files are resolved, never arbitrary user image URLs.
  static String? commonsTitle(Map<String, dynamic> place) {
    final raw = place['wikimedia_commons']?.toString().trim();
    if (raw != null &&
        raw.startsWith('File:') &&
        raw.length > 5 &&
        raw.length < 250 &&
        !raw.contains(RegExp(r'[|#\r\n]'))) {
      return raw;
    }
    final uri = Uri.tryParse(place['image']?.toString() ?? '');
    if (uri?.scheme == 'https' &&
        uri?.host == 'commons.wikimedia.org' &&
        uri!.path.startsWith('/wiki/File:')) {
      return commonsTitle({
        'wikimedia_commons': Uri.decodeComponent(uri.path.substring(6)),
      });
    }
    return null;
  }

  Future<PlacePhoto?> load(Map<String, dynamic> place) async {
    final title = commonsTitle(place);
    if (title == null) return null;
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'origin': '*',
      'prop': 'imageinfo',
      'titles': title,
      'iiprop': 'url|mime|extmetadata',
      'iiurlwidth': '960',
      'iiextmetadatafilter': 'Artist|LicenseShortName',
    });
    final response = await (client?.get(uri) ?? http.get(uri)).timeout(
      const Duration(seconds: 10),
    );
    if (response.statusCode != 200) throw Exception('Photo unavailable');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final pages = payload['query']?['pages'] as Map?;
    if (pages == null || pages.isEmpty) return null;
    final info = pages.values.first['imageinfo'] as List?;
    if (info == null || info.isEmpty) return null;
    final image = info.first as Map;
    final metadata = image['extmetadata'] as Map? ?? {};
    final license = metadata['LicenseShortName']?['value']?.toString() ?? '';
    if (!RegExp(
      r'^(CC BY(-SA)? [1-4]\.0|CC0( 1\.0)?|Public domain)$',
    ).hasMatch(license)) {
      return null;
    }
    final url = Uri.tryParse(image['thumburl']?.toString() ?? '');
    if (url?.scheme != 'https' ||
        !['upload.wikimedia.org', 'thumb.wikimedia.org'].contains(url?.host) ||
        !['image/jpeg', 'image/png', 'image/webp'].contains(image['mime'])) {
      return null;
    }
    final author = (metadata['Artist']?['value']?.toString() ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .trim();
    if (author.isEmpty) return null;
    return PlacePhoto(
      url: url!,
      sourceUrl: Uri.https('commons.wikimedia.org', '/wiki/$title'),
      author: author,
      license: license,
    );
  }
}
