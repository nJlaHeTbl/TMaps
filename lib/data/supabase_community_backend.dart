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
  Future<List<Map<String, dynamic>>> fetchLocationOverrides() async {
    final response = await _client.from('place_location_overrides').select();
    return response.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCommunityReviewSubmissions() async {
    final response = await _client.rpc('get_community_review_submissions');
    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchActiveHelpRequests() async {
    final response = await _client.rpc('get_active_place_help_requests');
    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPedestrianAlerts() async {
    final response = await _client.rpc('get_active_pedestrian_alerts');
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
    required String deviceKey,
    String? comment,
  }) async {
    final params = <String, dynamic>{
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
      'p_submitter_key': deviceKey,
      'p_comment': comment,
    };
    dynamic response;
    try {
      response = await _client.rpc('submit_place', params: params);
    } on PostgrestException catch (error) {
      // Keep submissions working during a rolling deployment where an older
      // database migration may be a few minutes behind the web bundle.
      if (error.code != 'PGRST202') rethrow;
      response = await _client.rpc(
        'submit_place',
        params: Map<String, dynamic>.of(params)..remove('p_submitter_key'),
      );
    }
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
  Future<int> submitLocationCorrection({
    required String placeKey,
    required double currentLatitude,
    required double currentLongitude,
    required double proposedLatitude,
    required double proposedLongitude,
    required String username,
    String? comment,
  }) async {
    final response = await _client.rpc(
      'submit_place_location_correction',
      params: {
        'p_place_key': placeKey,
        'p_current_lat': currentLatitude,
        'p_current_lng': currentLongitude,
        'p_proposed_lat': proposedLatitude,
        'p_proposed_lng': proposedLongitude,
        'p_username': username,
        'p_comment': comment,
      },
    );
    return (response as num).toInt();
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

  @override
  Future<Map<String, dynamic>> reviewSubmission({
    required int submissionId,
    required String voterKey,
    required bool isValid,
  }) async {
    final response = await _client.rpc(
      'review_place_submission',
      params: {
        'p_submission_id': submissionId,
        'p_voter_key': voterKey,
        'p_is_valid': isValid,
      },
    );
    final rows = response as List<dynamic>;
    if (rows.isEmpty) {
      throw const CommunityBackendException(
        'Не удалось получить результат проверки',
      );
    }
    return Map<String, dynamic>.from(rows.first as Map);
  }

  @override
  Future<DateTime> requestPaperHelp({
    required String placeKey,
    required double latitude,
    required double longitude,
    required String requesterKey,
  }) async {
    final response = await _client.rpc(
      'request_place_help',
      params: {
        'p_place_key': placeKey,
        'p_lat': latitude,
        'p_lng': longitude,
        'p_requester_key': requesterKey,
      },
    );
    final expiresAt = DateTime.tryParse(response.toString());
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
    final response = await _client.rpc(
      'report_pedestrian_alert',
      params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_alert_type': alertType,
        'p_username': username,
        'p_reporter_key': reporterKey,
        'p_description': description,
      },
    );
    return (response as num).toInt();
  }
}
