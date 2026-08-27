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
      name: 'Туалет у пляжа',
      isFree: true,
      cleanliness: 4,
      condition: 'Хорошее',
      hasPaper: false,
      hasSoap: false,
      wheelchairAccessible: false,
      phoneCharging: false,
      accessType: 'public',
      comment: 'Вход со двора',
      createdAt: createdAt,
    );

    await service.record(submission);
    final restored = await service.load();

    expect(restored, hasLength(1));
    expect(restored.single.id, 7);
    expect(restored.single.latitude, 45.01);
    expect(restored.single.name, 'Туалет у пляжа');
    expect(restored.single.hasPaper, isFalse);
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

  test('marks a matching published place as approved', () async {
    SharedPreferences.setMockInitialValues({});
    final submission = TrackedSubmission(
      id: 3,
      latitude: 45.0228440284174,
      longitude: 78.402359908659,
      username: 'Мирас',
      placeKind: 'community_toilet',
      isFree: true,
      cleanliness: 3,
      condition: 'Среднее',
      createdAt: DateTime.utc(2026, 8, 27),
    );
    await service.record(submission);

    final reconciled = await service.reconcilePublishedPlaces([
      {
        'id': 19,
        'lat': 45.0228440284174,
        'lng': 78.402359908659,
        'username': 'Мирас',
        'place_kind': 'community_toilet',
      },
    ]);

    expect(reconciled.single.status, 'approved');
    expect((await service.load()).single.status, 'approved');
  });

  test('does not approve a different nearby place', () async {
    SharedPreferences.setMockInitialValues({});
    final submission = TrackedSubmission(
      id: 9,
      latitude: 45.02,
      longitude: 78.40,
      username: 'Мирас',
      placeKind: 'community_toilet',
      isFree: true,
      cleanliness: 3,
      condition: 'Среднее',
      createdAt: DateTime.utc(2026, 8, 27),
    );
    await service.record(submission);

    final reconciled = await service.reconcilePublishedPlaces([
      {
        'lat': 45.02001,
        'lng': 78.40001,
        'username': 'Мирас',
        'place_kind': 'cafe',
      },
    ]);

    expect(reconciled.single.status, 'pending');
  });

  test(
    'moves an unanswered submission to community review after 24h',
    () async {
      SharedPreferences.setMockInitialValues({});
      final submission = TrackedSubmission(
        id: 15,
        latitude: 45.02,
        longitude: 78.40,
        username: 'Мирас',
        placeKind: 'community_toilet',
        isFree: true,
        cleanliness: 3,
        condition: 'Среднее',
        createdAt: DateTime.utc(2026, 8, 25, 10),
      );
      await service.record(submission);

      final before = await service.refreshLifecycle(
        now: DateTime.utc(2026, 8, 26, 9, 59),
      );
      final after = await service.refreshLifecycle(
        now: DateTime.utc(2026, 8, 26, 10),
      );

      expect(before.single.status, 'pending');
      expect(after.single.status, 'community_review');
      expect(after.single.statusUpdatedAt, DateTime.utc(2026, 8, 26, 10));
    },
  );

  test('removes a completed result one day after it was shown', () async {
    SharedPreferences.setMockInitialValues({});
    final resolvedAt = DateTime.utc(2026, 8, 26, 8);
    await service.record(
      TrackedSubmission(
        id: 16,
        latitude: 45.02,
        longitude: 78.40,
        username: 'Мирас',
        placeKind: 'community_toilet',
        isFree: true,
        cleanliness: 3,
        condition: 'Среднее',
        createdAt: DateTime.utc(2026, 8, 25),
        status: 'approved',
        statusUpdatedAt: resolvedAt,
      ),
    );

    expect(
      await service.refreshLifecycle(
        now: resolvedAt.add(const Duration(hours: 23)),
      ),
      hasLength(1),
    );
    expect(
      await service.refreshLifecycle(
        now: resolvedAt.add(const Duration(hours: 24)),
      ),
      isEmpty,
    );
  });
}
