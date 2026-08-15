import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/content_guard.dart';

class ToiletRepository {
  const ToiletRepository(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> fetchAll() async {
    final openStreetMapToilets = await _fetchOpenStreetMapToilets();

    try {
      final communityToilets = await _fetchCommunityToilets();
      return [...communityToilets, ...openStreetMapToilets];
    } catch (_) {
      return openStreetMapToilets;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCommunityToilets() async {
    final response = await _client.from('toilets').select();
    return response
        .map(Map<String, dynamic>.from)
        .where(ContentGuard.isSafeCommunityToilet)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchOpenStreetMapToilets() async {
    final json = await rootBundle.loadString(
      'assets/data/kazakhstan_toilets.json',
    );
    final payload = jsonDecode(json) as Map<String, dynamic>;
    final toilets = payload['toilets'] as List<dynamic>;
    return toilets
        .map((toilet) => Map<String, dynamic>.from(toilet as Map))
        .toList();
  }

  Future<Map<String, dynamic>> add({
    required double latitude,
    required double longitude,
    required String username,
    required bool isFree,
    required int cleanliness,
    required String condition,
    String? comment,
  }) async {
    final usernameIssue = ContentGuard.validateUsername(username);
    final commentIssue = ContentGuard.validateComment(comment);

    if (usernameIssue != null) throw ArgumentError(usernameIssue);
    if (commentIssue != null) throw ArgumentError(commentIssue);

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
        })
        .select()
        .single();

    return Map<String, dynamic>.from(response);
  }
}
