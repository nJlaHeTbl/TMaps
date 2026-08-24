import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/content_guard.dart';
import '../core/place_info.dart';
import 'community_backend.dart';

class ToiletRepository {
  const ToiletRepository(this._backend);

  final CommunityBackend _backend;

  Future<List<Map<String, dynamic>>> fetchAll() async {
    Future<List<Map<String, dynamic>>> safe(
      Future<List<Map<String, dynamic>>> request,
    ) async {
      try {
        return await request;
      } on Object {
        return const [];
      }
    }

    final results = await Future.wait([
      _fetchBundledPlaces(),
      safe(_fetchCommunityToilets()),
      safe(_fetchReports()),
      safe(_fetchVoteTotals()),
    ]);
    final openStreetMapToilets = results[0];
    final communityToilets = results[1];
    final reports = results[2];
    final voteTotals = results[3];

    return _attachCommunityData(
      [...communityToilets, ...openStreetMapToilets],
      reports,
      voteTotals,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCommunityToilets() async {
    final response = await _backend.fetchPlaces();
    return response
        .map(Map<String, dynamic>.from)
        .where(ContentGuard.isSafeCommunityToilet)
        .map((toilet) {
          return {
            ...toilet,
            'place_kind': toilet['place_kind'] ?? 'community_toilet',
            'has_toilet': toilet['has_toilet'] ?? true,
            'access_type': toilet['access_type'] ?? 'public',
            'source': 'community',
          };
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchBundledPlaces() async {
    Future<List<Map<String, dynamic>>> load(String assetPath) async {
      final json = await rootBundle.loadString(assetPath);
      final payload = jsonDecode(json) as Map<String, dynamic>;
      final places = (payload['places'] ?? payload['toilets']) as List<dynamic>;
      return places
          .map((place) => Map<String, dynamic>.from(place as Map))
          .toList(growable: false);
    }

    final bundled = await Future.wait([
      load('assets/data/kazakhstan_toilets.json'),
      load('assets/data/curated_places.json'),
    ]);
    return [...bundled[1], ...bundled[0]];
  }

  Future<List<Map<String, dynamic>>> _fetchReports() async {
    final response = await _backend.fetchReports();
    return response.where(ContentGuard.isSafeReport).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchVoteTotals() =>
      _backend.fetchVoteTotals();

  List<Map<String, dynamic>> _attachCommunityData(
    List<Map<String, dynamic>> places,
    List<Map<String, dynamic>> reports,
    List<Map<String, dynamic>> voteTotals,
  ) {
    final reportsByPlace = <String, List<Map<String, dynamic>>>{};

    for (final report in reports) {
      final key = report['place_key']?.toString();
      if (key == null || key.isEmpty) continue;
      reportsByPlace.putIfAbsent(key, () => []).add(report);
    }

    final votesByPlace = {
      for (final totals in voteTotals)
        if (totals['place_key'] != null) totals['place_key'].toString(): totals,
    };

    return places
        .map((place) {
          final key = PlaceInfo.keyOf(place);
          final placeReports = reportsByPlace[key] ?? const [];
          final votes = votesByPlace[key];
          return {
            ...place,
            'place_key': key,
            'report_count': placeReports.length,
            'likes': (votes?['likes'] as num?)?.toInt() ?? 0,
            'dislikes': (votes?['dislikes'] as num?)?.toInt() ?? 0,
            if (placeReports.isNotEmpty) 'latest_report': placeReports.first,
          };
        })
        .toList(growable: false);
  }

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
    final usernameIssue = ContentGuard.validateUsername(username);
    final commentIssue = ContentGuard.validateComment(comment);
    if (usernameIssue != null) throw ArgumentError(usernameIssue);
    if (commentIssue != null) throw ArgumentError(commentIssue);

    return _backend.submitPlace(
      latitude: latitude,
      longitude: longitude,
      username: username,
      placeKind: placeKind,
      isFree: isFree,
      cleanliness: cleanliness,
      condition: condition,
      comment: comment,
    );
  }

  Future<Map<String, dynamic>> addReport({
    required Map<String, dynamic> place,
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
    final usernameIssue = ContentGuard.validateUsername(username);
    final commentIssue = ContentGuard.validateComment(comment);

    if (usernameIssue != null) throw ArgumentError(usernameIssue);
    if (commentIssue != null) throw ArgumentError(commentIssue);

    return _backend.addReport(
      placeKey: PlaceInfo.keyOf(place),
      latitude: (place['lat'] as num).toDouble(),
      longitude: (place['lng'] as num).toDouble(),
      username: username,
      cleanliness: cleanliness,
      condition: condition,
      hasToilet: hasToilet,
      hasPaper: hasPaper,
      hasSoap: hasSoap,
      wheelchairAccessible: wheelchairAccessible,
      phoneCharging: phoneCharging,
      accessType: accessType,
      comment: comment,
    );
  }

  Future<void> castVote({
    required Map<String, dynamic> place,
    required String voterKey,
    required bool isCurrent,
  }) async {
    await _backend.castVote(
      placeKey: PlaceInfo.keyOf(place),
      voterKey: voterKey,
      isCurrent: isCurrent,
    );
  }
}
