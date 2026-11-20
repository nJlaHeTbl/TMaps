import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/place_description.dart';
import '../l10n/app_localizations.dart';
import '../services/place_photo_service.dart';

class PlaceOverview extends StatefulWidget {
  const PlaceOverview({
    super.key,
    required this.place,
    this.photoService = const PlacePhotoService(),
  });
  final Map<String, dynamic> place;
  final PlacePhotoService photoService;

  @override
  State<PlaceOverview> createState() => _PlaceOverviewState();
}

class _PlaceOverviewState extends State<PlaceOverview> {
  late Future<PlacePhoto?> _photo;
  @override
  void initState() {
    super.initState();
    _photo = widget.photoService.load(widget.place);
  }

  @override
  void didUpdateWidget(PlaceOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (PlacePhotoService.commonsTitle(oldWidget.place) !=
            PlacePhotoService.commonsTitle(widget.place) ||
        oldWidget.photoService != widget.photoService) {
      _photo = widget.photoService.load(widget.place);
    }
  }

  Widget _placeholder(BuildContext context, {bool failed = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.photo_camera_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: LocalizedText(
              failed ? 'Фото не загрузилось' : 'Фотографии пока нет',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          if (failed)
            IconButton(
              tooltip: context.l10n.translate('Повторить'),
              onPressed: () => setState(() {
                _photo = widget.photoService.load(widget.place);
              }),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocalizedText(
          'О месте',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          PlaceDescription.build(widget.place, context.l10n),
          style: TextStyle(fontSize: 14, height: 1.55, color: scheme.onSurface),
        ),
        const SizedBox(height: 6),
        LocalizedText(
          'По данным карты и последних сообщений. Условия могут измениться.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        FutureBuilder<PlacePhoto?>(
          future: _photo,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final photo = snapshot.data;
            if (photo == null) {
              return _placeholder(context, failed: snapshot.hasError);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    photo.url.toString(),
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.contain,
                    semanticLabel: context.l10n.translate('Фотография места'),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                    errorBuilder: (context, error, stack) =>
                        _placeholder(context, failed: true),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${photo.author} · ${photo.license} · Wikimedia Commons',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                SelectableText(
                  photo.licenseUrl.toString(),
                  style: TextStyle(fontSize: 11, color: scheme.primary),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text:
                            '${photo.sourceUrl}\n${photo.author} · ${photo.license}\n${photo.licenseUrl}',
                      ),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: LocalizedText(
                          'Ссылка на источник скопирована',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const LocalizedText('Скопировать источник фото'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
