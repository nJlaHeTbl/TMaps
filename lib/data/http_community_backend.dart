import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/place_info.dart';
import 'community_backend.dart';

final class HttpCommunityBackend implements CommunityBackend {
  HttpCommunityBackend({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

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
  Future<int> submitPlace({
    required double latitude,
    required double longitude,
    required String username,
    required PlaceKind placeKind,
    required bool isFree,
    required int cleanliness,
    required String condition,
    String? comment,
  }) async {
    final payload = await _send('/api/submissions', {
      'lat': latitude,
      'lng': longitude,
      'username': username,
      'placeKind': PlaceInfo.valueOfKind(placeKind),
      'isFree': isFree,
      'cleanliness': cleanliness,
      'condition': condition,
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
    required bool? hasToilet,
    required bool? hasPaper,
    required bool? hasSoap,
    required bool? wheelchairAccessible,
    required bool? phoneCharging,
    required String accessType,
    String? comment,
  }) async {
    final payload = await _send('/api/reports', {
      'placeKey': placeKey,
      'lat': latitude,
      'lng': longitude,
      'username': username,
      'cleanliness': cleanliness,
      'condition': condition,
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
  Future<void> castVote({
    required String placeKey,
    required String voterKey,
    required bool isCurrent,
  }) async {
    await _send('/api/votes', {
      'placeKey': placeKey,
      'voterKey': voterKey,
      'isCurrent': isCurrent,
    });
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
    Map<String, dynamic> body,
  ) async {
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
