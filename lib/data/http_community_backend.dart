import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/place_info.dart';
import 'community_backend.dart';

final class HttpCommunityBackend implements CommunityBackend {
  HttpCommunityBackend({
    required String baseUrl,
    http.Client? client,
    this.turnstileToken,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  /// Supplies a fresh Cloudflare Turnstile token for anti-bot checks.
  final Future<String?> Function()? turnstileToken;

  @override
  Future<List<Map<String, dynamic>>> fetchPlaces() =>
      _getList('/api/places', 'places');

  @override
  Future<List<Map<String, dynamic>>> fetchReports() =>
      _getList('/api/reports', 'reports');

  @override
  Future<List<Map<String, dynamic>>> fetchVoteTotals() =>
      _getList('/api/votes', 'votes');

  @override
  Future<List<Map<String, dynamic>>> fetchLocationOverrides() =>
      _getList('/api/location-overrides', 'overrides');

  @override
  Future<List<Map<String, dynamic>>> fetchCommunityReviewSubmissions() =>
      _getList('/api/community-reviews', 'submissions');

  @override
  Future<List<Map<String, dynamic>>> fetchActiveHelpRequests() =>
      _getList('/api/help-requests', 'requests');

  @override
  Future<List<Map<String, dynamic>>> fetchPedestrianAlerts() =>
      _getList('/api/pedestrian-alerts', 'alerts');

  @override
  Future<int> submitPlace({
    required double latitude,
    required double longitude,
    required String username,
    required PlaceKind placeKind,
    required String? name,
    required bool isFree,
    required int cleanliness,
    required String condition,
    required bool? hasPaper,
    required bool? hasSoap,
    required bool? wheelchairAccessible,
    required bool? phoneCharging,
    required String accessType,
    required String deviceKey,
    String? comment,
  }) async {
    final payload = await _send('/api/submissions', protected: true, {
      'lat': latitude,
      'lng': longitude,
      'username': username,
      'placeKind': PlaceInfo.valueOfKind(placeKind),
      'name': name,
      'isFree': isFree,
      'cleanliness': cleanliness,
      'condition': condition,
      'hasPaper': hasPaper,
      'hasSoap': hasSoap,
      'wheelchairAccessible': wheelchairAccessible,
      'phoneCharging': phoneCharging,
      'accessType': accessType,
      'deviceKey': deviceKey,
      'comment': comment,
    });
    return (payload['id'] as num).toInt();
  }

  @override
  Future<Map<String, dynamic>> addReport({
    required String placeKey,
    required double latitude,
    required double longitude,
    required String username,
    required int cleanliness,
    required String condition,
    required bool? isFree,
    required bool? hasToilet,
    required bool? hasPaper,
    required bool? hasSoap,
    required bool? wheelchairAccessible,
    required bool? phoneCharging,
    required String accessType,
    String? comment,
  }) async {
    final payload = await _send('/api/reports', protected: true, {
      'placeKey': placeKey,
      'lat': latitude,
      'lng': longitude,
      'username': username,
      'cleanliness': cleanliness,
      'condition': condition,
      'isFree': isFree,
      'hasToilet': hasToilet,
      'hasPaper': hasPaper,
      'hasSoap': hasSoap,
      'wheelchairAccessible': wheelchairAccessible,
      'phoneCharging': phoneCharging,
      'accessType': accessType,
      'comment': comment,
    });
    return Map<String, dynamic>.from(payload['report'] as Map);
  }

  @override
  Future<int> submitLocationCorrection({
    required String placeKey,
    required double currentLatitude,
    required double currentLongitude,
    required double proposedLatitude,
    required double proposedLongitude,
    required String username,
    String? comment,
  }) async {
    final payload = await _send('/api/location-corrections', protected: true, {
      'placeKey': placeKey,
      'currentLat': currentLatitude,
      'currentLng': currentLongitude,
      'proposedLat': proposedLatitude,
      'proposedLng': proposedLongitude,
      'username': username,
      'comment': comment,
    });
    return (payload['id'] as num).toInt();
  }

  @override
  Future<void> castVote({
    required String placeKey,
    required String voterKey,
    required bool isCurrent,
  }) async {
    await _send('/api/votes', protected: true, {
      'placeKey': placeKey,
      'voterKey': voterKey,
      'isCurrent': isCurrent,
    });
  }

  @override
  Future<Map<String, dynamic>> reviewSubmission({
    required int submissionId,
    required String voterKey,
    required bool isValid,
  }) async {
    final payload = await _send(
      '/api/community-reviews/$submissionId/votes',
      protected: true,
      {'voterKey': voterKey, 'isValid': isValid},
    );
    return Map<String, dynamic>.from(payload['review'] as Map);
  }

  @override
  Future<DateTime> requestPaperHelp({
    required String placeKey,
    required double latitude,
    required double longitude,
    required String requesterKey,
  }) async {
    final payload = await _send('/api/help-requests', {
      'placeKey': placeKey,
      'lat': latitude,
      'lng': longitude,
      'requesterKey': requesterKey,
    });
    final expiresAt = DateTime.tryParse(payload['expiresAt']?.toString() ?? '');
    if (expiresAt == null) {
      throw const CommunityBackendException(
        'Не удалось получить срок сигнала помощи',
      );
    }
    return expiresAt;
  }

  @override
  Future<int> submitPedestrianAlert({
    required double latitude,
    required double longitude,
    required String alertType,
    required String username,
    required String reporterKey,
    String? description,
  }) async {
    final payload = await _send('/api/pedestrian-alerts', {
      'lat': latitude,
      'lng': longitude,
      'alertType': alertType,
      'username': username,
      'reporterKey': reporterKey,
      'description': description,
    });
    return (payload['id'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> _getList(String path, String field) async {
    final response = await _client
        .get(Uri.parse('$_baseUrl$path'))
        .timeout(const Duration(seconds: 12));
    final payload = _decode(response);
    final rows = payload[field];
    if (rows is! List) {
      throw const CommunityBackendException('Сервер вернул неверный формат');
    }
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _send(
    String path,
    Map<String, dynamic> body, {
    bool protected = false,
  }) async {
    final tokenProvider = turnstileToken;
    if (protected && tokenProvider != null) {
      String? token;
      try {
        token = await tokenProvider();
      } on Object {
        throw const CommunityBackendException(
          'Не удалось пройти проверку от ботов. Попробуй ещё раз',
        );
      }
      if (token != null) body = {...body, 'turnstileToken': token};
    }
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } on Object {
      throw const CommunityBackendException('Сервер временно недоступен');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CommunityBackendException(
        payload['error']?.toString() ?? 'Не удалось выполнить запрос',
      );
    }
    return payload;
  }
}
