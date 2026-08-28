import 'place_info.dart';

enum PlaceFreshnessLevel { recent, aging, stale, unknown }

enum PlaceFreshnessSource {
  communityReport,
  locationCorrection,
  manualVerification,
  sourceSnapshot,
  added,
  unknown,
}

class PlaceFreshness {
  const PlaceFreshness({
    required this.level,
    required this.source,
    required this.date,
    required this.label,
    required this.detail,
  });

  final PlaceFreshnessLevel level;
  final PlaceFreshnessSource source;
  final DateTime? date;
  final String label;
  final String detail;
}

abstract final class PlaceFreshnessResolver {
  static PlaceFreshness resolve(Map<String, dynamic> place, {DateTime? now}) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final candidate = _candidate(place);
    if (candidate == null) {
      return const PlaceFreshness(
        level: PlaceFreshnessLevel.unknown,
        source: PlaceFreshnessSource.unknown,
        date: null,
        label: 'Дата не указана',
        detail: 'Проверь место перед поездкой',
      );
    }

    final date = candidate.$2.toUtc();
    final age = currentTime.difference(date);
    final safeDays = age.isNegative ? 0 : age.inDays;
    final level = switch (safeDays) {
      <= 30 => PlaceFreshnessLevel.recent,
      <= 180 => PlaceFreshnessLevel.aging,
      _ => PlaceFreshnessLevel.stale,
    };

    return PlaceFreshness(
      level: level,
      source: candidate.$1,
      date: date,
      label: _ageLabel(safeDays),
      detail: _sourceLabel(candidate.$1),
    );
  }

  static (PlaceFreshnessSource, DateTime)? _candidate(
    Map<String, dynamic> place,
  ) {
    final reportDate = _parse(PlaceInfo.latestReport(place)?['created_at']);
    if (reportDate != null) {
      return (PlaceFreshnessSource.communityReport, reportDate);
    }

    final correctionDate = _parse(place['location_corrected_at']);
    if (correctionDate != null) {
      return (PlaceFreshnessSource.locationCorrection, correctionDate);
    }

    final verifiedDate = _parse(place['verified_at']);
    if (verifiedDate != null) {
      return (PlaceFreshnessSource.manualVerification, verifiedDate);
    }

    final addedDate = _parse(place['created_at']);
    if (addedDate != null) {
      return (PlaceFreshnessSource.added, addedDate);
    }

    final snapshotDate = _parse(place['dataset_generated_at']);
    if (snapshotDate != null) {
      return (PlaceFreshnessSource.sourceSnapshot, snapshotDate);
    }

    return null;
  }

  static DateTime? _parse(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static String _ageLabel(int days) {
    if (days == 0) return 'Обновлено сегодня';
    if (days == 1) return 'Обновлено вчера';
    if (days < 7) return 'Обновлено $days дн. назад';
    if (days < 60) return 'Обновлено ${(days / 7).floor()} нед. назад';
    if (days < 730) return 'Обновлено ${(days / 30).floor()} мес. назад';
    return 'Обновлено ${(days / 365).floor()} г. назад';
  }

  static String _sourceLabel(PlaceFreshnessSource source) {
    return switch (source) {
      PlaceFreshnessSource.communityReport => 'Последнее уточнение от человека',
      PlaceFreshnessSource.locationCorrection =>
        'Координаты уточнены сообществом',
      PlaceFreshnessSource.manualVerification => 'Проверено командой TMaps',
      PlaceFreshnessSource.sourceSnapshot => 'Свежесть исходной открытой базы',
      PlaceFreshnessSource.added => 'Дата добавления точки',
      PlaceFreshnessSource.unknown => 'Источник даты неизвестен',
    };
  }
}
