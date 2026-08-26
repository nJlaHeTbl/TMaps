import '../core/place_info.dart';

abstract interface class CommunityBackend {
  Future<List<Map<String, dynamic>>> fetchPlaces();

  Future<List<Map<String, dynamic>>> fetchReports();

  Future<List<Map<String, dynamic>>> fetchVoteTotals();

  Future<List<Map<String, dynamic>>> fetchLocationOverrides();

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
  });

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
  });

  Future<int> submitLocationCorrection({
    required String placeKey,
    required double currentLatitude,
    required double currentLongitude,
    required double proposedLatitude,
    required double proposedLongitude,
    required String username,
    String? comment,
  });

  Future<void> castVote({
    required String placeKey,
    required String voterKey,
    required bool isCurrent,
  });
}

final class CommunityBackendException implements Exception {
  const CommunityBackendException(this.message);

  final String message;

  @override
  String toString() => message;
}
