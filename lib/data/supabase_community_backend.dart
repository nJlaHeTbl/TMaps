import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/place_info.dart';
import 'community_backend.dart';

final class SupabaseCommunityBackend implements CommunityBackend {
  const SupabaseCommunityBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchPlaces() async {
    final response = await _client.from('toilets').select();
    return response.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReports() async {
    final response = await _client
        .from('toilet_reports')
        .select()
        .order('created_at', ascending: false);
    return response.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchVoteTotals() async {
    final response = await _client.rpc('get_place_vote_totals');
    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

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
    String? comment,
  }) async {
    final response = await _client.rpc(
      'submit_place',
      params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_username': username,
        'p_place_kind': PlaceInfo.valueOfKind(placeKind),
        'p_name': name,
        'p_is_free': isFree,
        'p_cleanliness': cleanliness,
        'p_condition': condition,
        'p_has_paper': hasPaper,
        'p_has_soap': hasSoap,
        'p_wheelchair_accessible': wheelchairAccessible,
        'p_phone_charging': phoneCharging,
        'p_access_type': accessType,
        'p_comment': comment,
      },
    );
    return (response as num).toInt();
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
    final response = await _client
        .from('toilet_reports')
        .insert({
          'place_key': placeKey,
          'lat': latitude,
          'lng': longitude,
          'username': username,
          'cleanliness': cleanliness,
          'condition': condition,
          'is_free': isFree,
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

  @override
  Future<void> castVote({
    required String placeKey,
    required String voterKey,
    required bool isCurrent,
  }) async {
    await _client.rpc(
      'cast_place_vote',
      params: {
        'p_place_key': placeKey,
        'p_voter_key': voterKey,
        'p_is_current': isCurrent,
      },
    );
  }
}
