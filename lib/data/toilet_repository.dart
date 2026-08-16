import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/content_guard.dart';
import '../core/place_info.dart';

class ToiletRepository {
  const ToiletRepository(this._client);

  final SupabaseClient _client;

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
      _fetchOpenStreetMapToilets(),
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
    final response = await _client.from('toilets').select();
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

  Future<List<Map<String, dynamic>>> _fetchOpenStreetMapToilets() async {
    final json = await rootBundle.loadString(
      'assets/data/kazakhstan_toilets.json',
    );
    final payload = jsonDecode(json) as Map<String, dynamic>;
    final places = (payload['places'] ?? payload['toilets']) as List<dynamic>;
    return places
        .map((toilet) => Map<String, dynamic>.from(toilet as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchReports() async {
    final response = await _client
        .from('toilet_reports')
        .select()
        .order('created_at', ascending: false);

    return response
        .map(Map<String, dynamic>.from)
        .where(ContentGuard.isSafeReport)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchVoteTotals() async {
    final response = await _client.rpc('get_place_vote_totals');
    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

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

  Future<Map<String, dynamic>> add({
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

    final hasToilet = placeKind == PlaceKind.communityToilet;
    final response = await _client
        .from('toilets')
        .insert({
          'lat': latitude,
          'lng': longitude,
          'username': username,
          'is_free': isFree,
          'cleanliness': cleanliness,
          'condition': condition,
          'comment': comment,
          'place_kind': PlaceInfo.valueOfKind(placeKind),
          'has_toilet': hasToilet,
          'access_type': 'public',
        })
        .select()
        .single();

    return {
      ...Map<String, dynamic>.from(response),
      'source': 'community',
      'fee_known': true,
      'phone_charging': placeKind == PlaceKind.phoneCharging,
      'ev_charging': placeKind == PlaceKind.evCharging,
    };
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

    final response = await _client.rpc(
      'submit_place',
      params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_username': username,
        'p_place_kind': PlaceInfo.valueOfKind(placeKind),
        'p_is_free': isFree,
        'p_cleanliness': cleanliness,
        'p_condition': condition,
        'p_comment': comment,
      },
    );
    return (response as num).toInt();
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

    final response = await _client
        .from('toilet_reports')
        .insert({
          'place_key': PlaceInfo.keyOf(place),
          'lat': (place['lat'] as num).toDouble(),
          'lng': (place['lng'] as num).toDouble(),
          'username': username,
          'cleanliness': cleanliness,
          'condition': condition,
          'has_toilet': hasToilet,
          'has_paper': hasPaper,
          'has_soap': hasSoap,
          'wheelchair_accessible': wheelchairAccessible,
          'phone_charging': phoneCharging,
          'access_type': accessType,
          'comment': comment,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(response);
  }

  Future<void> castVote({
    required Map<String, dynamic> place,
    required String voterKey,
    required bool isCurrent,
  }) async {
    await _client.rpc(
      'cast_place_vote',
      params: {
        'p_place_key': PlaceInfo.keyOf(place),
        'p_voter_key': voterKey,
        'p_is_current': isCurrent,
      },
    );
  }
}
