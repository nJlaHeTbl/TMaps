import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/place_freshness.dart';

void main() {
  final now = DateTime.utc(2026, 8, 28, 12);

  test('prefers a recent community report over an older verification', () {
    final freshness = PlaceFreshnessResolver.resolve({
      'verified_at': '2025-01-01T00:00:00Z',
      'latest_report': {'created_at': '2026-08-20T00:00:00Z'},
    }, now: now);

    expect(freshness.level, PlaceFreshnessLevel.recent);
    expect(freshness.source, PlaceFreshnessSource.communityReport);
    expect(freshness.label, 'Обновлено 1 нед. назад');
  });

  test('uses source snapshot and marks old data as stale', () {
    final freshness = PlaceFreshnessResolver.resolve({
      'dataset_generated_at': '2025-08-01T00:00:00Z',
    }, now: now);

    expect(freshness.level, PlaceFreshnessLevel.stale);
    expect(freshness.source, PlaceFreshnessSource.sourceSnapshot);
  });

  test('returns an honest unknown state when no date is available', () {
    final freshness = PlaceFreshnessResolver.resolve({}, now: now);

    expect(freshness.level, PlaceFreshnessLevel.unknown);
    expect(freshness.date, isNull);
    expect(freshness.label, 'Дата не указана');
  });
}
