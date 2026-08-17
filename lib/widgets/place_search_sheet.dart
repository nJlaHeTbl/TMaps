import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_palette.dart';
import '../core/place_info.dart';
import '../core/place_search.dart';
import '../presentation/place_category_style.dart';

class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({
    super.key,
    required this.places,
    required this.origin,
    this.title = 'Найти место',
    this.subtitle,
    this.headerIcon = Icons.travel_explore_rounded,
    this.autofocus = true,
    this.sectionLabel = 'Ближайшие к центру карты',
    this.emptyTitle = 'Ничего не нашли',
    this.emptyMessage = 'Попробуй другое название или смени категорию',
  });

  final List<Map<String, dynamic>> places;
  final LatLng origin;
  final String title;
  final String? subtitle;
  final IconData headerIcon;
  final bool autofocus;
  final String sectionLabel;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final _controller = TextEditingController();
  PlaceKind? _category;
  String _query = '';

  List<PlaceSearchResult> get _results => PlaceSearch.find(
    widget.places,
    query: _query,
    origin: widget.origin,
    category: _category,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final scheme = Theme.of(context).colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboardInset;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: availableHeight * (keyboardInset > 0 ? 0.94 : 0.82),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 10, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: AppPalette.brandGradient,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(widget.headerIcon, color: Colors.white),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            widget.subtitle ??
                                '${widget.places.length} точки по Казахстану',
                            style: const TextStyle(
                              color: AppPalette.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: TextField(
                  controller: _controller,
                  autofocus: widget.autofocus,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Название, вода, АЗС, кафе, туалет…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить поиск',
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.cancel_rounded),
                          ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _SearchCategoryChip(
                      label: 'Все',
                      icon: Icons.apps_rounded,
                      color: AppPalette.emerald,
                      selected: _category == null,
                      onTap: () => setState(() => _category = null),
                    ),
                    ...PlaceKind.values.map(
                      (kind) => _SearchCategoryChip(
                        label: kind.shortLabel,
                        icon: kind.icon,
                        color: kind.color,
                        selected: _category == kind,
                        onTap: () => setState(() => _category = kind),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
                child: Row(
                  children: [
                    Icon(
                      _query.trim().isEmpty
                          ? Icons.near_me_rounded
                          : Icons.auto_awesome_rounded,
                      color: AppPalette.emerald,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _query.trim().isEmpty
                          ? widget.sectionLabel
                          : 'Показано: ${results.length}',
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: results.isEmpty
                      ? _EmptySearchResult(
                          title: widget.emptyTitle,
                          message: widget.emptyMessage,
                        )
                      : ListView.separated(
                          key: ValueKey('${_category?.name}:$_query'),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(14, 2, 14, 18),
                          itemCount: results.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final result = results[index];
                            return _PlaceSearchTile(
                              result: result,
                              onTap: () => Navigator.pop(context, result.place),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchCategoryChip extends StatelessWidget {
  const _SearchCategoryChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label),
        labelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: selected ? color : scheme.onSurface,
        ),
        selectedColor: color.withValues(alpha: 0.13),
        backgroundColor: scheme.surface,
        side: BorderSide(
          color: selected
              ? color.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _PlaceSearchTile extends StatelessWidget {
  const _PlaceSearchTile({required this.result, required this.onTap});

  final PlaceSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final place = result.place;
    final kind = PlaceInfo.kindOf(place);
    final hasToilet = PlaceInfo.hasToilet(place);
    final feeKnown = place['fee_known'] == true;
    final isFree = place['is_free'] == true;
    final drinkingWater = PlaceInfo.drinkingWater(place);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: kind.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(kind.icon, color: kind.color, size: 23),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PlaceInfo.titleOf(place),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${PlaceInfo.kindLabel(place)} • ${_formatDistance(result.distanceMeters)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 10.8,
                      ),
                    ),
                    if (hasToilet || feeKnown || kind == PlaceKind.water) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          if (hasToilet &&
                              kind != PlaceKind.publicToilet &&
                              kind != PlaceKind.communityToilet)
                            const _MiniBadge(
                              text: 'Туалет есть',
                              color: AppPalette.emerald,
                            ),
                          if (feeKnown)
                            _MiniBadge(
                              text: isFree ? 'Бесплатно' : 'Платно',
                              color: isFree
                                  ? AppPalette.emerald
                                  : AppPalette.sky,
                            ),
                          if (kind == PlaceKind.water)
                            _MiniBadge(
                              text: drinkingWater == true
                                  ? 'Можно пить'
                                  : 'Вода не проверена',
                              color: drinkingWater == true
                                  ? AppPalette.emerald
                                  : Colors.orange,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: AppPalette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} м';
    return '${(meters / 1000).toStringAsFixed(1)} км';
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('empty-search'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppPalette.coral.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: AppPalette.coral,
                size: 31,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppPalette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
