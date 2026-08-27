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
    this.statusUpdatedAt,
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
  final DateTime? statusUpdatedAt;

  TrackedSubmission copyWith({String? status, DateTime? statusUpdatedAt}) =>
      TrackedSubmission(
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
        statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
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
    'status_updated_at': statusUpdatedAt?.toUtc().toIso8601String(),
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
      statusUpdatedAt: DateTime.tryParse(
        json['status_updated_at']?.toString() ?? '',
      ),
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

  /// Keeps the on-device inbox useful without turning it into a permanent log.
  /// Pending requests move to community review after a day. Completed results
  /// remain visible for one day and are then removed automatically.
  Future<List<TrackedSubmission>> refreshLifecycle({DateTime? now}) async {
    final current = await load();
    final currentTime = (now ?? DateTime.now()).toUtc();
    var changed = false;
    final updated = <TrackedSubmission>[];

    for (final submission in current) {
      final age = currentTime.difference(submission.createdAt.toUtc());
      if (submission.status == 'pending' && age >= const Duration(hours: 24)) {
        changed = true;
        updated.add(
          submission.copyWith(
            status: 'community_review',
            statusUpdatedAt: submission.createdAt.toUtc().add(
              const Duration(hours: 24),
            ),
          ),
        );
        continue;
      }

      if (submission.status == 'approved' || submission.status == 'rejected') {
        final resolvedAt =
            submission.statusUpdatedAt?.toUtc() ?? submission.createdAt.toUtc();
        if (currentTime.difference(resolvedAt) >= const Duration(hours: 24)) {
          changed = true;
          continue;
        }
      }

      updated.add(submission);
    }

    if (changed) await _save(updated);
    return updated;
  }

  Future<List<TrackedSubmission>> reconcilePublishedPlaces(
    List<Map<String, dynamic>> publishedPlaces,
  ) async {
    final current = await load();
    var changed = false;
    final updated = current
        .map((submission) {
          if (submission.status != 'pending' &&
              submission.status != 'community_review') {
            return submission;
          }

          final wasPublished = publishedPlaces.any(
            (place) => _matchesPublishedPlace(submission, place),
          );
          if (!wasPublished) return submission;

          changed = true;
          final publishedAt = publishedPlaces
              .where((place) => _matchesPublishedPlace(submission, place))
              .map(
                (place) =>
                    DateTime.tryParse(place['created_at']?.toString() ?? ''),
              )
              .whereType<DateTime>()
              .firstOrNull;
          return submission.copyWith(
            status: 'approved',
            statusUpdatedAt: publishedAt?.toUtc() ?? DateTime.now().toUtc(),
          );
        })
        .toList(growable: false);

    if (changed) await _save(updated);
    return updated;
  }

  bool _matchesPublishedPlace(
    TrackedSubmission submission,
    Map<String, dynamic> place,
  ) {
    final publishedSubmissionId = (place['submission_id'] as num?)?.toInt();
    if (publishedSubmissionId != null) {
      return publishedSubmissionId == submission.id;
    }

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

    final publishedName = place['name']?.toString().trim().toLowerCase() ?? '';
    final submittedName = submission.name?.trim().toLowerCase() ?? '';
    return publishedName.isEmpty ||
        submittedName.isEmpty ||
        publishedName == submittedName;
  }

  Future<void> _save(List<TrackedSubmission> submissions) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(submissions.map((item) => item.toJson()).toList()),
    );
  }
}
