import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_palette.dart';

enum AddLocationMode { current, chooseOnMap }

class AddLocationChoiceSheet extends StatelessWidget {
  const AddLocationChoiceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Где находится место?',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Можно добавить точку рядом с собой или выбрать её в другом городе.',
              style: TextStyle(color: AppPalette.muted, height: 1.35),
            ),
            const SizedBox(height: 18),
            _LocationChoice(
              icon: Icons.my_location_rounded,
              title: 'Я нахожусь здесь',
              subtitle: 'Использовать текущее местоположение',
              gradient: AppPalette.brandGradient,
              onTap: () => Navigator.pop(context, AddLocationMode.current),
            ),
            const SizedBox(height: 12),
            _LocationChoice(
              icon: Icons.map_rounded,
              title: 'Выбрать на карте',
              subtitle: 'Добавить место удалённо в любой точке Казахстана',
              gradient: AppPalette.warmGradient,
              onTap: () => Navigator.pop(context, AddLocationMode.chooseOnMap),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationChoice extends StatelessWidget {
  const _LocationChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2EEE8)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: Colors.white, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppPalette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class PlacePickerOverlay extends StatelessWidget {
  const PlacePickerOverlay({
    super.key,
    required this.position,
    required this.onCancel,
    required this.onConfirm,
  });

  final LatLng position;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 148,
              left: 18,
              right: 18,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.ink.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        'Двигай карту — метка останется по центру',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Center(child: IgnorePointer(child: _PickerPin())),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Material(
                elevation: 18,
                shadowColor: Colors.black38,
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(25),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: AppPalette.warmGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.pin_drop_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Новая точка',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '${position.latitude.toStringAsFixed(5)}, '
                                  '${position.longitude.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    color: AppPalette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onCancel,
                              child: const Text('Отмена'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: onConfirm,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Выбрать эту точку'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerPin extends StatelessWidget {
  const _PickerPin();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -24),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: AppPalette.warmGradient,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.add_location_alt_rounded,
          color: Colors.white,
          size: 29,
        ),
      ),
    );
  }
}

class MapZoomHint extends StatelessWidget {
  const MapZoomHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: AppPalette.ink.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(17),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.zoom_in_map_rounded, color: AppPalette.mint, size: 20),
            SizedBox(width: 7),
            Text(
              'Приблизь карту — покажем места рядом',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocationPromptCard extends StatelessWidget {
  const LocationPromptCard({
    super.key,
    required this.title,
    required this.message,
    required this.onEnable,
  });

  final String title;
  final String message;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shadowColor: Colors.black26,
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onEnable,
        borderRadius: BorderRadius.circular(21),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppPalette.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.gps_fixed_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
