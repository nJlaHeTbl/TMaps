import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../core/content_guard.dart';
import '../core/place_info.dart';
import '../core/pedestrian_alert.dart';
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
      safe(_backend.fetchLocationOverrides()),
      safe(_fetchCommunityReviewSubmissions()),
      safe(_backend.fetchActiveHelpRequests()),
    ]);
    final openStreetMapToilets = results[0];
    final communityToilets = results[1];
    final reports = results[2];
    final voteTotals = results[3];
    final locationOverrides = results[4];
    final communityReviewSubmissions = results[5];
    final activeHelpRequests = results[6];

    final places = _attachCommunityData(
      [
        ...communityReviewSubmissions,
        ...communityToilets,
        ...openStreetMapToilets,
      ],
      reports,
      voteTotals,
      activeHelpRequests,
    );
    return _applyLocationOverrides(
      places
          .where((place) => !PlaceInfo.isCommunityVerifiedAbsent(place))
          .toList(),
      locationOverrides,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCommunityReviewSubmissions() async {
    final response = await _backend.fetchCommunityReviewSubmissions();
    return response
        .map(Map<String, dynamic>.from)
        .where(ContentGuard.isSafeCommunityToilet)
        .map((submission) {
          final kind = PlaceInfo.kindOf(submission);
          return {
            ...submission,
            'id': 'community_review_${submission['submission_id']}',
            'submission_status': 'community_review',
            'has_toilet':
                submission['has_toilet'] ??
                (kind == PlaceKind.communityToilet ||
                    kind == PlaceKind.publicToilet),
            'fee_known':
                submission['fee_known'] ??
                (kind == PlaceKind.communityToilet ||
                    kind == PlaceKind.publicToilet),
            'source': 'community_review_submission',
          };
        })
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchCommunityToilets() async {
    final response = await _backend.fetchPlaces();
    return response
        .map(Map<String, dynamic>.from)
        .where(ContentGuard.isSafeCommunityToilet)
        .map((toilet) {
          final kind = PlaceInfo.kindOf(toilet);
          return {
            ...toilet,
            'place_kind': toilet['place_kind'] ?? 'community_toilet',
            'has_toilet': toilet['has_toilet'] ?? true,
            'access_type': toilet['access_type'] ?? 'public',
            'fee_known':
                toilet['fee_known'] ??
                (kind == PlaceKind.communityToilet ||
                    kind == PlaceKind.publicToilet),
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
      final generatedAt = payload['generated_at']?.toString();
      return places
          .map(
            (place) => <String, dynamic>{
              ...Map<String, dynamic>.from(place as Map),
              if (generatedAt != null && generatedAt.isNotEmpty)
                'dataset_generated_at': generatedAt,
            },
          )
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

  List<Map<String, dynamic>> _applyLocationOverrides(
    List<Map<String, dynamic>> places,
    List<Map<String, dynamic>> overrides,
  ) {
    final overridesByPlace = {
      for (final override in overrides)
        if (override['place_key'] != null)
          override['place_key'].toString(): override,
    };

    return places
        .map((place) {
          final override = overridesByPlace[PlaceInfo.keyOf(place)];
          if (override == null) return place;
          return {
            ...place,
            'original_lat': place['lat'],
            'original_lng': place['lng'],
            'lat': override['lat'],
            'lng': override['lng'],
            'location_corrected': true,
            'location_corrected_at': override['updated_at'],
          };
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _attachCommunityData(
    List<Map<String, dynamic>> places,
    List<Map<String, dynamic>> reports,
    List<Map<String, dynamic>> voteTotals,
    List<Map<String, dynamic>> activeHelpRequests,
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
    final helpByPlace = {
      for (final request in activeHelpRequests)
        if (request['place_key'] != null)
          request['place_key'].toString(): request,
    };

    return places
        .map((place) {
          final key = PlaceInfo.keyOf(place);
          final placeReports = reportsByPlace[key] ?? const [];
          final votes = votesByPlace[key];
          final helpRequest = helpByPlace[key];
          return {
            ...place,
            'place_key': key,
            'report_count': placeReports.length,
            'likes': (votes?['likes'] as num?)?.toInt() ?? 0,
            'dislikes': (votes?['dislikes'] as num?)?.toInt() ?? 0,
            'paper_help_active': helpRequest != null,
            if (helpRequest != null)
              'paper_help_expires_at': helpRequest['expires_at'],
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
    final usernameIssue = ContentGuard.validateUsername(username);
    final commentIssue = ContentGuard.validateComment(comment);
    if (usernameIssue != null) throw ArgumentError(usernameIssue);
    if (commentIssue != null) throw ArgumentError(commentIssue);

    return _backend.submitPlace(
      latitude: latitude,
      longitude: longitude,
      username: username,
      placeKind: placeKind,
      name: name,
      isFree: isFree,
      cleanliness: cleanliness,
      condition: condition,
      hasPaper: hasPaper,
      hasSoap: hasSoap,
      wheelchairAccessible: wheelchairAccessible,
      phoneCharging: phoneCharging,
      accessType: accessType,
      deviceKey: deviceKey,
      comment: comment,
    );
  }

  Future<Map<String, dynamic>> addReport({
    required Map<String, dynamic> place,
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
      isFree: isFree,
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

  Future<Map<String, dynamic>> reviewSubmission({
    required int submissionId,
    required String voterKey,
    required bool isValid,
  }) {
    if (voterKey.length < 12 || voterKey.length > 80) {
      throw ArgumentError('Некорректный ключ устройства');
    }
    return _backend.reviewSubmission(
      submissionId: submissionId,
      voterKey: voterKey,
      isValid: isValid,
    );
  }

  Future<DateTime> requestPaperHelp({
    required Map<String, dynamic> place,
    required String requesterKey,
  }) {
    if (!PlaceInfo.hasToilet(place)) {
      throw ArgumentError('Сигнал помощи доступен только для туалетов');
    }
    return _backend.requestPaperHelp(
      placeKey: PlaceInfo.keyOf(place),
      latitude: (place['lat'] as num).toDouble(),
      longitude: (place['lng'] as num).toDouble(),
      requesterKey: requesterKey,
    );
  }

  Future<int> submitLocationCorrection({
    required Map<String, dynamic> place,
    required double proposedLatitude,
    required double proposedLongitude,
    required String username,
    String? comment,
  }) async {
    final usernameIssue = ContentGuard.validateUsername(username);
    final commentIssue = ContentGuard.validateComment(comment);
    if (usernameIssue != null) throw ArgumentError(usernameIssue);
    if (commentIssue != null) throw ArgumentError(commentIssue);

    final currentLatitude = (place['lat'] as num).toDouble();
    final currentLongitude = (place['lng'] as num).toDouble();
    if ((currentLatitude - proposedLatitude).abs() < 0.000001 &&
        (currentLongitude - proposedLongitude).abs() < 0.000001) {
      throw ArgumentError('Передвинь метку в новое место');
    }

    return _backend.submitLocationCorrection(
      placeKey: PlaceInfo.keyOf(place),
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      proposedLatitude: proposedLatitude,
      proposedLongitude: proposedLongitude,
      username: username,
      comment: comment,
    );
  }

  Future<List<PedestrianAlert>> fetchPedestrianAlerts() async {
    final response = await _backend.fetchPedestrianAlerts();
    return PedestrianAlertPolicy.active(
      response.map(PedestrianAlert.fromJson).whereType<PedestrianAlert>(),
    );
  }

  Future<int> submitPedestrianAlert({
    required LatLng position,
    required PedestrianAlertDraft draft,
    required String username,
    required String reporterKey,
  }) {
    final usernameIssue = ContentGuard.validateUsername(username);
    final descriptionIssue = ContentGuard.validateComment(draft.description);
    if (usernameIssue != null) throw ArgumentError(usernameIssue);
    if (descriptionIssue != null) throw ArgumentError(descriptionIssue);
    if (reporterKey.length < 12 || reporterKey.length > 80) {
      throw ArgumentError('Некорректный ключ устройства');
    }

    return _backend.submitPedestrianAlert(
      latitude: position.latitude,
      longitude: position.longitude,
      alertType: draft.type.value,
      username: username,
      reporterKey: reporterKey,
      description: draft.description,
    );
  }
}
