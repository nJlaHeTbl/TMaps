import 'package:flutter/material.dart';

import '../core/pedestrian_alert.dart';
import '../l10n/app_localizations.dart';
import '../services/walking_route_controller.dart';
import '../presentation/app_motion.dart';

class WalkingRoutePanel extends StatelessWidget {
  const WalkingRoutePanel({
    super.key,
    required this.status,
    required this.distance,
    required this.duration,
    required this.alerts,
    required this.onClose,
    this.onRetry,
  });

  final WalkingRouteStatus status;
  final String? distance;
  final String? duration;
  final List<PedestrianAlert> alerts;
  final VoidCallback onClose;
  final VoidCallback? onRetry;

  bool get _busy =>
      status == WalkingRouteStatus.locating ||
      status == WalkingRouteStatus.loading ||
      status == WalkingRouteStatus.rerouting;

  String get _title => switch (status) {
    WalkingRouteStatus.idle || WalkingRouteStatus.ready => 'Пеший маршрут',
    WalkingRouteStatus.locating => 'Определяем местоположение…',
    WalkingRouteStatus.loading => 'Строим пеший маршрут…',
    WalkingRouteStatus.rerouting => 'Обновляем пеший маршрут…',
    WalkingRouteStatus.offRoute => 'Вы отошли от маршрута',
    WalkingRouteStatus.locationUnavailable => 'Маршрут на паузе: нет GPS',
    WalkingRouteStatus.impreciseLocation => 'Маршрут на паузе: неточный GPS',
    WalkingRouteStatus.failed =>
      distance == null
          ? 'Не удалось построить маршрут'
          : 'Не удалось обновить маршрут',
  };

  String? get _hint => switch (status) {
    WalkingRouteStatus.locationUnavailable =>
      'Верни сигнал GPS, чтобы обновить путь',
    WalkingRouteStatus.impreciseLocation => 'Ждём более точные координаты',
    WalkingRouteStatus.failed => 'Проверь интернет и повтори попытку',
    WalkingRouteStatus.offRoute => 'Проверяем отклонение от пути',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hint = _hint;
    return AnimatedSize(
      duration: AppMotion.duration(context, AppMotion.panel),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      child: Material(
        elevation: 12,
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_busy)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(
                      Icons.directions_walk_rounded,
                      color: colors.primary,
                      size: 28,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MotionSwitcher(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        key: ValueKey('$status:$distance:$duration'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocalizedText(
                            _title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (distance != null && duration != null)
                            Text(
                              '≈ ${context.l10n.translate(distance!)} · ${context.l10n.translate(duration!)}',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!_busy)
                    IconButton(
                      tooltip: context.l10n.translate('Обновить маршрут'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  IconButton(
                    tooltip: context.l10n.translate('Убрать маршрут'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                LocalizedText(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (alerts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: colors.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: colors.onTertiaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alerts.length == 1
                              ? context.l10n
                                    .translate('{label} рядом с маршрутом', {
                                      'label': context.l10n.translate(
                                        alerts.first.type.label,
                                      ),
                                    })
                              : context.l10n.translate(
                                  'Предупреждений рядом с маршрутом: {count}',
                                  {'count': alerts.length},
                                ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
