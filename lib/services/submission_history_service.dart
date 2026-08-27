import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TrackedSubmission {
  const TrackedSubmission({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.username,
    required this.placeKind,
    required this.isFree,
    required this.cleanliness,
    required this.condition,
    required this.createdAt,
    this.name,
    this.hasPaper,
    this.hasSoap,
    this.wheelchairAccessible,
    this.phoneCharging,
    this.accessType = 'public',
    this.comment,
    this.status = 'pending',
  });

  final int id;
  final double latitude;
  final double longitude;
  final String username;
  final String placeKind;
  final String? name;
  final bool isFree;
  final int cleanliness;
  final String condition;
  final bool? hasPaper;
  final bool? hasSoap;
  final bool? wheelchairAccessible;
  final bool? phoneCharging;
  final String accessType;
  final String? comment;
  final DateTime createdAt;
  final String status;

  TrackedSubmission copyWith({String? status}) => TrackedSubmission(
    id: id,
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
    comment: comment,
    createdAt: createdAt,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': latitude,
    'lng': longitude,
    'username': username,
    'place_kind': placeKind,
    'name': name,
    'is_free': isFree,
    'cleanliness': cleanliness,
    'condition': condition,
    'has_paper': hasPaper,
    'has_soap': hasSoap,
    'wheelchair_accessible': wheelchairAccessible,
    'phone_charging': phoneCharging,
    'access_type': accessType,
    'comment': comment,
    'created_at': createdAt.toUtc().toIso8601String(),
    'status': status,
  };

  factory TrackedSubmission.fromJson(Map<String, dynamic> json) {
    return TrackedSubmission(
      id: (json['id'] as num).toInt(),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      username: json['username']?.toString() ?? 'Пользователь TMaps',
      placeKind: json['place_kind']?.toString() ?? 'community_toilet',
      name: json['name']?.toString(),
      isFree: json['is_free'] == true,
      cleanliness: (json['cleanliness'] as num?)?.toInt() ?? 0,
      condition: json['condition']?.toString() ?? 'Не указано',
      hasPaper: json['has_paper'] as bool?,
      hasSoap: json['has_soap'] as bool?,
      wheelchairAccessible: json['wheelchair_accessible'] as bool?,
      phoneCharging: json['phone_charging'] as bool?,
      accessType: json['access_type']?.toString() ?? 'public',
      comment: json['comment']?.toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      status: json['status']?.toString() ?? 'pending',
    );
  }
}

class SubmissionHistoryService {
  const SubmissionHistoryService();

  static const _storageKey = 'tracked_place_submissions';

  Future<List<TrackedSubmission>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final values = jsonDecode(raw) as List<dynamic>;
      return values
          .map(
            (value) => TrackedSubmission.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<List<TrackedSubmission>> record(TrackedSubmission submission) async {
    final current = await load();
    final updated = [
      submission,
      ...current.where((item) => item.id != submission.id),
    ];
    await _save(updated);
    return updated;
  }

  Future<List<TrackedSubmission>> reconcilePublishedPlaces(
    List<Map<String, dynamic>> publishedPlaces,
  ) async {
    final current = await load();
    var changed = false;
    final updated = current
        .map((submission) {
          if (submission.status != 'pending') return submission;

          final wasPublished = publishedPlaces.any(
            (place) => _matchesPublishedPlace(submission, place),
          );
          if (!wasPublished) return submission;

          changed = true;
          return submission.copyWith(status: 'approved');
        })
        .toList(growable: false);

    if (changed) await _save(updated);
    return updated;
  }

  bool _matchesPublishedPlace(
    TrackedSubmission submission,
    Map<String, dynamic> place,
  ) {
    final latitude = (place['lat'] as num?)?.toDouble();
    final longitude = (place['lng'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return false;

    const coordinateTolerance = 0.000001;
    if ((latitude - submission.latitude).abs() > coordinateTolerance ||
        (longitude - submission.longitude).abs() > coordinateTolerance) {
      return false;
    }

    final publishedKind =
        place['place_kind']?.toString().trim() ?? 'community_toilet';
    if (publishedKind != submission.placeKind) return false;

    final publishedUsername = place['username']?.toString().trim() ?? '';
    final submittedUsername = submission.username.trim();
    return publishedUsername.isEmpty ||
        submittedUsername.isEmpty ||
        publishedUsername.toLowerCase() == submittedUsername.toLowerCase();
  }

  Future<void> _save(List<TrackedSubmission> submissions) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(submissions.map((item) => item.toJson()).toList()),
    );
  }
}
