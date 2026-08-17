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
    this.comment,
    this.status = 'pending',
  });

  final int id;
  final double latitude;
  final double longitude;
  final String username;
  final String placeKind;
  final bool isFree;
  final int cleanliness;
  final String condition;
  final String? comment;
  final DateTime createdAt;
  final String status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': latitude,
    'lng': longitude,
    'username': username,
    'place_kind': placeKind,
    'is_free': isFree,
    'cleanliness': cleanliness,
    'condition': condition,
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
      isFree: json['is_free'] == true,
      cleanliness: (json['cleanliness'] as num?)?.toInt() ?? 0,
      condition: json['condition']?.toString() ?? 'Не указано',
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

  Future<void> _save(List<TrackedSubmission> submissions) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(submissions.map((item) => item.toJson()).toList()),
    );
  }
}
