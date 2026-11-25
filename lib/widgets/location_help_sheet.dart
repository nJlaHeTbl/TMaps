import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../l10n/app_localizations.dart';

class LocationHelpSheet extends StatelessWidget {
  const LocationHelpSheet({
    super.key,
    required this.isWeb,
    required this.permissionBlocked,
    required this.onRetry,
  });

  final bool isWeb;
  final bool permissionBlocked;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppPalette.brandGradient,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.location_searching_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              LocalizedText(
                permissionBlocked
                    ? 'Разреши доступ к геопозиции'
                    : 'Поможем включить GPS',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              LocalizedText(
                permissionBlocked
                    ? 'TMaps работает, но браузер заблокировал передачу координат этому сайту.'
                    : 'Проверь разрешение на геопозицию и повтори попытку.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (isWeb) ...[
                const _LocationStep(
                  number: '1',
                  title: 'Chrome или Android',
                  text:
                      'Нажми значок настроек слева от адреса сайта → «Настройки сайта» → «Геоданные» → «Разрешить».',
                ),
                const SizedBox(height: 10),
                const _LocationStep(
                  number: '2',
                  title: 'iPhone или Safari',
                  text:
                      'Открой «Настройки» → «Конфиденциальность и безопасность» → «Службы геолокации» → «Safari Websites» → «При использовании».',
                ),
                const SizedBox(height: 10),
                const _LocationStep(
                  number: '3',
                  title: 'Вернись в TMaps',
                  text:
                      'Обнови страницу и нажми «Проверить GPS». Если TMaps установлен на главный экран, проверь разрешение также у Chrome, Safari или TMaps.',
                ),
              ] else ...[
                const _LocationStep(
                  number: '1',
                  title: 'Открой настройки телефона',
                  text: 'Разреши приложению TMaps доступ к геопозиции.',
                ),
                const SizedBox(height: 10),
                const _LocationStep(
                  number: '2',
                  title: 'Включи точное местоположение',
                  text: 'Так синяя точка и расстояние до туалета будут точнее.',
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onRetry();
                  },
                  icon: const Icon(Icons.my_location_rounded),
                  label: const LocalizedText('Проверить GPS'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const LocalizedText('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.number,
    required this.title,
    required this.text,
  });

  final String number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.emerald.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: LocalizedText(
              number,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppPalette.mint
                    : AppPalette.emeraldText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                LocalizedText(
                  text,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
