import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmaps/services/submission_history_service.dart';

void main() {
  const service = SubmissionHistoryService();

  test('stores a submitted place on this device', () async {
    SharedPreferences.setMockInitialValues({});
    final createdAt = DateTime.utc(2026, 8, 17, 12);
    final submission = TrackedSubmission(
      id: 7,
      latitude: 45.01,
      longitude: 78.39,
      username: 'Мирас',
      placeKind: 'community_toilet',
      isFree: true,
      cleanliness: 4,
      condition: 'Хорошее',
      comment: 'Вход со двора',
      createdAt: createdAt,
    );

    await service.record(submission);
    final restored = await service.load();

    expect(restored, hasLength(1));
    expect(restored.single.id, 7);
    expect(restored.single.latitude, 45.01);
    expect(restored.single.comment, 'Вход со двора');
    expect(restored.single.status, 'pending');
    expect(restored.single.createdAt, createdAt);
  });

  test('replaces a duplicate submission id', () async {
    SharedPreferences.setMockInitialValues({});
    final first = TrackedSubmission(
      id: 3,
      latitude: 45,
      longitude: 78,
      username: 'Мирас',
      placeKind: 'community_toilet',
      isFree: true,
      cleanliness: 3,
      condition: 'Среднее',
      createdAt: DateTime.utc(2026, 8, 17),
    );
    final updated = TrackedSubmission(
      id: 3,
      latitude: 45.1,
      longitude: 78.1,
      username: 'Мирас',
      placeKind: 'community_toilet',
      isFree: false,
      cleanliness: 5,
      condition: 'Хорошее',
      createdAt: DateTime.utc(2026, 8, 17, 1),
    );

    await service.record(first);
    await service.record(updated);
    final restored = await service.load();

    expect(restored, hasLength(1));
    expect(restored.single.latitude, 45.1);
    expect(restored.single.isFree, isFalse);
  });
}
