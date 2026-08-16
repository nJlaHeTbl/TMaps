import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_config.dart';
import 'core/app_palette.dart';
import 'core/app_theme.dart';
import 'core/content_guard.dart';
import 'core/map_display_policy.dart';
import 'core/place_info.dart';
import 'core/place_visibility_policy.dart';
import 'data/toilet_repository.dart';
import 'presentation/place_category_style.dart';
import 'services/live_location_service.dart';
import 'services/route_service.dart';
import 'widgets/map_overlays.dart';

bool? _nullableBool(dynamic value) {
  if (value is bool) return value;
  return switch (value?.toString().toLowerCase()) {
    'yes' || 'true' || '1' => true,
    'no' || 'false' || '0' => false,
    _ => null,
  };
}

Color _toiletFeeColor({required bool feeKnown, required bool isFree}) {
  if (!feeKnown) return Colors.blueGrey.shade600;
  return isFree ? const Color(0xFF16A34A) : const Color(0xFF0284C7);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );

  runApp(const TMapsApp());
}

class TMapsApp extends StatelessWidget {
  const TMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TMaps',
      theme: AppTheme.light,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color green = Color(0xFF16A34A);

  final MapController _mapController = MapController();
  final RouteService _routeService = const RouteService();
  final LiveLocationService _locationService = LiveLocationService();

  late final ToiletRepository _toiletRepository;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _cameraUpdateTimer;

  LatLng currentPosition = const LatLng(45.0156, 78.3731);
  LatLng _pickedPosition = const LatLng(45.0156, 78.3731);
  LatLngBounds? _visibleMapBounds;
  LocationAccessState _locationState = LocationAccessState.permissionNeeded;
  double _mapZoom = 15;
  double _locationAccuracy = 0;
  double _locationHeading = 0;
  bool _followUser = false;
  bool _isPickingLocation = false;

  final List<Map<String, dynamic>> toilets = [];

  String? username;

  bool isAddingToilet = false;
  bool isBuildingRoute = false;
  bool isFindingNearest = false;
  bool isSubmittingReport = false;
  bool isSubmittingVote = false;
  bool showFreeOnly = false;
  bool showWheelchairOnly = false;
  bool showCommunityOnly = false;
  bool showVenueToilets = true;
  bool showPhoneCharging = true;
  bool showEvCharging = true;
  PlaceKind? selectedCategory;

  List<LatLng> routePoints = [];

  double? routeDistance;
  double? routeDuration;

  List<Map<String, dynamic>> get visibleToilets {
    return toilets
        .where(
          (place) => PlaceVisibilityPolicy.matches(
            place,
            selectedCategory: selectedCategory,
            freeOnly: showFreeOnly,
            wheelchairOnly: showWheelchairOnly,
            communityOnly: showCommunityOnly,
            venueToilets: showVenueToilets,
            phoneCharging: showPhoneCharging,
            evCharging: showEvCharging,
          ),
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get displayedPlaces =>
      MapDisplayPolicy.placesInside(
        visibleToilets,
        zoom: _mapZoom,
        bounds: _visibleMapBounds,
        maxMarkers: MediaQuery.sizeOf(context).width < 600 ? 44 : 72,
      );

  bool get showZoomHint =>
      !MapDisplayPolicy.canShowPlaces(_mapZoom) && !_isPickingLocation;

  bool get showEmptyAreaHint =>
      MapDisplayPolicy.canShowPlaces(_mapZoom) &&
      displayedPlaces.isEmpty &&
      visibleToilets.isNotEmpty &&
      !_isPickingLocation;

  String get _mapScopeLabel =>
      selectedCategory == null ? 'Туалеты' : selectedCategory!.shortLabel;

  String get _mapSummary => selectedCategory == null
      ? '${visibleToilets.length} туалетов по Казахстану'
      : '${visibleToilets.length} мест • ${selectedCategory!.shortLabel}';

  bool get filtersActive =>
      selectedCategory != null ||
      showFreeOnly ||
      showWheelchairOnly ||
      showCommunityOnly ||
      !showVenueToilets ||
      !showPhoneCharging ||
      !showEvCharging;

  @override
  void initState() {
    super.initState();

    _toiletRepository = ToiletRepository(Supabase.instance.client);

    _locationSubscription = _locationService.positions.listen(_applyPosition);

    loadUsername();
    unawaited(_startLocation(requestPermission: false));
    loadToilets();
  }

  @override
  void dispose() {
    _cameraUpdateTimer?.cancel();
    unawaited(_locationSubscription?.cancel());
    unawaited(_locationService.dispose());
    super.dispose();
  }

  // =========================================================
  // USERNAME
  // =========================================================

  Future<void> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();

    final savedUsername = prefs.getString('username');

    if (savedUsername != null && savedUsername.trim().isNotEmpty) {
      if (!mounted) return;

      setState(() {
        username = savedUsername;
      });

      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showUsernameDialog();
      }
    });
  }

  Future<void> showUsernameDialog() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    color: green,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Добро пожаловать в TMaps',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Как тебя называть?',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    hintText: 'Например: Мирас',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final name = controller.text.trim();

                      final issue = ContentGuard.validateUsername(name);

                      if (issue != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(issue),
                          ),
                        );
                        return;
                      }

                      final prefs = await SharedPreferences.getInstance();

                      await prefs.setString('username', name);

                      if (!mounted || !context.mounted) return;

                      setState(() {
                        username = name;
                      });

                      Navigator.of(context).pop();
                      unawaited(
                        _startLocation(requestPermission: true, center: true),
                      );
                    },
                    child: const Text('Продолжить'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    controller.dispose();
  }

  // =========================================================
  // GPS
  // =========================================================

  Future<bool> _startLocation({
    required bool requestPermission,
    bool center = false,
  }) async {
    final result = await _locationService.start(
      requestPermission: requestPermission,
    );
    if (!mounted) return false;

    setState(() => _locationState = result.state);
    if (result.position != null) {
      _applyPosition(result.position!, center: center);
    }
    return result.state == LocationAccessState.ready && result.position != null;
  }

  void _applyPosition(Position position, {bool center = false}) {
    if (!mounted) return;
    final point = LatLng(position.latitude, position.longitude);

    setState(() {
      currentPosition = point;
      _locationAccuracy = position.accuracy;
      _locationHeading = position.heading.isFinite ? position.heading : 0;
      _locationState = LocationAccessState.ready;
      if (routePoints.length >= 2) routePoints[0] = point;
    });

    if (center || _followUser) {
      _mapController.move(point, max(_mapZoom, 16));
    }
  }

  Future<void> centerOnUser() async {
    setState(() => _followUser = true);
    final locationFound = await _startLocation(
      requestPermission: true,
      center: true,
    );
    if (!mounted || locationFound) return;

    setState(() => _followUser = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_locationHelpMessage)));
  }

  String get _locationHelpMessage => switch (_locationState) {
    LocationAccessState.permissionNeeded =>
      'Нажми «Включить GPS» и разреши доступ к геопозиции',
    LocationAccessState.deniedForever =>
      'Разреши геопозицию для TMaps в настройках телефона',
    LocationAccessState.servicesDisabled =>
      'Включи GPS на телефоне и повтори попытку',
    LocationAccessState.unavailable =>
      'Не удалось получить координаты. Проверь GPS и интернет',
    LocationAccessState.ready => 'Геопозиция работает',
  };

  Future<void> showNearestToilet() async {
    if (isFindingNearest) return;

    setState(() {
      isFindingNearest = true;
    });

    try {
      final availableToilets = toilets
          .where(
            (place) => PlaceVisibilityPolicy.matches(
              place,
              selectedCategory: null,
              freeOnly: showFreeOnly,
              wheelchairOnly: showWheelchairOnly,
              communityOnly: showCommunityOnly,
              venueToilets: showVenueToilets,
              phoneCharging: true,
              evCharging: true,
            ),
          )
          .toList(growable: false);

      if (availableToilets.isEmpty) {
        throw Exception('На карте пока нет туалетов');
      }

      final locationFound = await _startLocation(requestPermission: true);
      if (!locationFound) {
        throw Exception('Не удалось определить местоположение');
      }

      Map<String, dynamic>? nearest;
      double nearestDistance = double.infinity;

      for (final toilet in availableToilets) {
        final distance = _distanceTo(toilet);
        if (distance < nearestDistance) {
          nearest = toilet;
          nearestDistance = distance;
        }
      }

      if (!mounted || nearest == null) return;

      final point = LatLng(
        (nearest['lat'] as num).toDouble(),
        (nearest['lng'] as num).toDouble(),
      );
      _mapController.move(point, 17);
      showToiletInfo(nearest);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isFindingNearest = false;
        });
      }
    }
  }

  double _distanceTo(Map<String, dynamic> toilet) {
    return Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      (toilet['lat'] as num).toDouble(),
      (toilet['lng'] as num).toDouble(),
    );
  }

  Future<void> showFilters() async {
    var category = selectedCategory;
    var freeOnly = showFreeOnly;
    var wheelchairOnly = showWheelchairOnly;
    var communityOnly = showCommunityOnly;
    var venueToilets = showVenueToilets;
    var phoneCharging = showPhoneCharging;
    var evCharging = showEvCharging;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Фильтры карты',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Что показать',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterCategoryChip(
                          label: 'Все туалеты',
                          icon: Icons.wc_rounded,
                          color: green,
                          selected: category == null,
                          onSelected: () {
                            setSheetState(() => category = null);
                          },
                        ),
                        ...PlaceKind.values.map(
                          (kind) => _FilterCategoryChip(
                            label: kind.shortLabel,
                            icon: kind.icon,
                            color: kind.color,
                            selected: category == kind,
                            onSelected: () {
                              setSheetState(() => category = kind);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Только бесплатные'),
                      subtitle: const Text('Скрыть платные и без цены'),
                      value: freeOnly,
                      onChanged: (value) {
                        setSheetState(() => freeOnly = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Доступно для коляски'),
                      subtitle: const Text(
                        'Только точки с отметкой wheelchair',
                      ),
                      value: wheelchairOnly,
                      onChanged: (value) {
                        setSheetState(() => wheelchairOnly = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Только точки сообщества'),
                      subtitle: const Text('Скрыть импорт OpenStreetMap'),
                      value: communityOnly,
                      onChanged: (value) {
                        setSheetState(() => communityOnly = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Туалеты в кафе, АЗС и организациях'),
                      subtitle: const Text(
                        'Места с доступом для клиентов или посетителей',
                      ),
                      value: venueToilets,
                      onChanged: (value) {
                        setSheetState(() => venueToilets = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Зарядка телефона'),
                      subtitle: const Text('Точки зарядки мобильных устройств'),
                      value: phoneCharging,
                      onChanged: (value) {
                        setSheetState(() => phoneCharging = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Электрозарядные станции'),
                      subtitle: const Text('Зарядка для электромобилей'),
                      value: evCharging,
                      onChanged: (value) {
                        setSheetState(() => evCharging = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setSheetState(() {
                                category = null;
                                freeOnly = false;
                                wheelchairOnly = false;
                                communityOnly = false;
                                venueToilets = true;
                                phoneCharging = true;
                                evCharging = true;
                              });
                            },
                            child: const Text('Сбросить'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                selectedCategory = category;
                                showFreeOnly = freeOnly;
                                showWheelchairOnly = wheelchairOnly;
                                showCommunityOnly = communityOnly;
                                showVenueToilets = venueToilets;
                                showPhoneCharging = phoneCharging;
                                showEvCharging = evCharging;
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Применить'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> showInstallInstructions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Установить TMaps',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'После установки карта будет открываться с главного экрана как обычное приложение.',
                ),
                SizedBox(height: 18),
                _InstallStep(
                  icon: Icons.android_rounded,
                  title: 'Android — Chrome',
                  text:
                      'Нажми ⋮ → «Установить приложение» или «Добавить на главный экран».',
                ),
                SizedBox(height: 12),
                _InstallStep(
                  icon: Icons.phone_iphone_rounded,
                  title: 'iPhone — Safari',
                  text: 'Нажми «Поделиться» → «На экран Домой» → «Добавить».',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // ЗАГРУЗКА ТУАЛЕТОВ
  // =========================================================

  Future<void> loadToilets() async {
    try {
      final loadedToilets = await _toiletRepository.fetchAll();

      if (!mounted) return;

      setState(() {
        toilets
          ..clear()
          ..addAll(loadedToilets);
      });

      debugPrint('Загружено туалетов: ${toilets.length}');
    } catch (e) {
      debugPrint('Ошибка загрузки туалетов: $e');
    }
  }

  // =========================================================
  // ДОБАВЛЕНИЕ ТУАЛЕТА
  // =========================================================

  Future<void> addToilet() async {
    if (isAddingToilet) return;

    if (ContentGuard.validateUsername(username) != null) {
      await showUsernameDialog();
      if (!mounted || ContentGuard.validateUsername(username) != null) return;
    }

    final mode = await showModalBottomSheet<AddLocationMode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddLocationChoiceSheet(),
    );
    if (!mounted || mode == null) return;

    if (mode == AddLocationMode.current) {
      setState(() => isAddingToilet = true);
      final locationFound = await _startLocation(
        requestPermission: true,
        center: true,
      );
      if (!mounted) return;
      if (!locationFound) {
        setState(() => isAddingToilet = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_locationHelpMessage)));
        return;
      }
      await _showAddPlaceForm(currentPosition);
      return;
    }

    final camera = _mapController.camera;
    setState(() {
      _followUser = false;
      _isPickingLocation = true;
      _pickedPosition = camera.center;
    });
  }

  void _cancelLocationPicker() {
    setState(() => _isPickingLocation = false);
  }

  Future<void> _confirmPickedLocation() async {
    final position = _pickedPosition;
    setState(() {
      _isPickingLocation = false;
      isAddingToilet = true;
    });
    await _showAddPlaceForm(position);
  }

  Future<void> _showAddPlaceForm(LatLng position) async {
    try {
      var isFree = true;
      var cleanliness = 5;
      var condition = 'Хорошее';
      var comment = '';
      var placeKind = PlaceKind.communityToilet;

      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return _AddToiletSheet(
                position: position,
                placeKind: placeKind,
                isFree: isFree,
                cleanliness: cleanliness,
                condition: condition,
                comment: comment,
                onPlaceKindChanged: (value) {
                  setDialogState(() {
                    placeKind = value;
                  });
                },
                onFreeChanged: (value) {
                  setDialogState(() {
                    isFree = value;
                  });
                },
                onCleanlinessChanged: (value) {
                  setDialogState(() {
                    cleanliness = value;
                  });
                },
                onConditionChanged: (value) {
                  setDialogState(() {
                    condition = value;
                  });
                },
                onCommentChanged: (value) {
                  comment = value;
                },
                onCancel: () {
                  Navigator.of(context).pop(false);
                },
                onAdd: () {
                  final issue = ContentGuard.validateComment(comment);
                  if (issue != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(issue),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
              );
            },
          );
        },
      );

      if (result != true || !mounted) return;

      final submissionId = await _toiletRepository.submitPlace(
        latitude: position.latitude,
        longitude: position.longitude,
        username: username!,
        placeKind: placeKind,
        isFree: isFree,
        cleanliness: cleanliness,
        condition: condition,
        comment: comment.trim().isEmpty ? null : comment.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            'Заявка #$submissionId отправлена. '
            'Место появится после проверки.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Ошибка добавления туалета: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: Colors.red.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text('Не удалось отправить заявку: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => isAddingToilet = false);
    }
  }

  // =========================================================
  // КАРТОЧКА ТУАЛЕТА
  // =========================================================

  void showToiletInfo(Map<String, dynamic> toilet) {
    final latestReport = PlaceInfo.latestReport(toilet);
    final String author =
        latestReport?['username']?.toString() ??
        toilet['username']?.toString() ??
        'Неизвестный пользователь';

    final bool isFree = toilet['is_free'] == true;
    final bool feeKnown = toilet['fee_known'] != false;

    final int cleanliness =
        (PlaceInfo.effectiveValue(toilet, 'cleanliness') as num?)?.toInt() ?? 0;

    final String condition =
        PlaceInfo.effectiveValue(toilet, 'condition')?.toString() ??
        'Не указано';

    final String comment =
        latestReport?['comment']?.toString() ??
        toilet['comment']?.toString() ??
        '';
    final String distance = formatDistance(_distanceTo(toilet));
    final hasPaper = _nullableBool(
      PlaceInfo.effectiveValue(toilet, 'has_paper'),
    );
    final hasSoap = _nullableBool(PlaceInfo.effectiveValue(toilet, 'has_soap'));
    final wheelchairAccessible =
        _nullableBool(
          PlaceInfo.effectiveValue(toilet, 'wheelchair_accessible'),
        ) ??
        _nullableBool(toilet['wheelchair']);
    final phoneCharging = _nullableBool(
      PlaceInfo.effectiveValue(toilet, 'phone_charging'),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ToiletInfoSheet(
          title: PlaceInfo.titleOf(toilet),
          kindLabel: PlaceInfo.kindLabel(toilet),
          placeKind: PlaceInfo.kindOf(toilet),
          accessLabel: PlaceInfo.accessLabel(toilet),
          hasToilet: PlaceInfo.hasToilet(toilet),
          author: author,
          isFree: isFree,
          feeKnown: feeKnown,
          cleanliness: cleanliness,
          condition: condition,
          comment: comment,
          distance: distance,
          hasPaper: hasPaper,
          hasSoap: hasSoap,
          wheelchairAccessible: wheelchairAccessible,
          phoneCharging: phoneCharging,
          reportCount: PlaceInfo.reportCount(toilet),
          likes: (toilet['likes'] as num?)?.toInt() ?? 0,
          dislikes: (toilet['dislikes'] as num?)?.toInt() ?? 0,
          isBuildingRoute: isBuildingRoute,
          isSubmittingReport: isSubmittingReport,
          isSubmittingVote: isSubmittingVote,
          onVote: (isCurrent) async {
            Navigator.of(context).pop();
            await submitVote(toilet, isCurrent: isCurrent);
          },
          onReport: () async {
            Navigator.of(context).pop();
            await showReportForm(toilet);
          },
          onRoute: () async {
            Navigator.of(context).pop();
            await buildRoute(toilet);
          },
          onClose: () {
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Future<void> showReportForm(Map<String, dynamic> place) async {
    if (isSubmittingReport) return;

    if (ContentGuard.validateUsername(username) != null) {
      await showUsernameDialog();
      if (ContentGuard.validateUsername(username) != null) return;
    }

    final placeKey = PlaceInfo.keyOf(place);
    final prefs = await SharedPreferences.getInstance();
    final lastReportAt = prefs.getInt('last_report:$placeKey');
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lastReportAt != null && now - lastReportAt < 300000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Подожди 5 минут перед следующим обновлением этой точки',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    final draft = await showModalBottomSheet<_PlaceReportDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _PlaceReportSheet(
          title: PlaceInfo.titleOf(place),
          canConfirmToilet: PlaceInfo.isVenue(place),
          initialHasToilet: _nullableBool(
            PlaceInfo.effectiveValue(place, 'has_toilet'),
          ),
          initialCleanliness:
              (PlaceInfo.effectiveValue(place, 'cleanliness') as num?)?.toInt(),
          initialCondition: PlaceInfo.effectiveValue(
            place,
            'condition',
          )?.toString(),
          initialPaper: _nullableBool(
            PlaceInfo.effectiveValue(place, 'has_paper'),
          ),
          initialSoap: _nullableBool(
            PlaceInfo.effectiveValue(place, 'has_soap'),
          ),
          initialWheelchair:
              _nullableBool(
                PlaceInfo.effectiveValue(place, 'wheelchair_accessible'),
              ) ??
              _nullableBool(place['wheelchair']),
          initialPhoneCharging: _nullableBool(
            PlaceInfo.effectiveValue(place, 'phone_charging'),
          ),
          initialAccessType: PlaceInfo.effectiveValue(
            place,
            'access_type',
          )?.toString(),
        );
      },
    );

    if (draft == null || !mounted) return;

    try {
      setState(() => isSubmittingReport = true);
      await _toiletRepository.addReport(
        place: place,
        username: username!,
        cleanliness: draft.cleanliness,
        condition: draft.condition,
        hasToilet: draft.hasToilet,
        hasPaper: draft.hasPaper,
        hasSoap: draft.hasSoap,
        wheelchairAccessible: draft.wheelchairAccessible,
        phoneCharging: draft.phoneCharging,
        accessType: draft.accessType,
        comment: draft.comment.trim().isEmpty ? null : draft.comment.trim(),
      );
      await prefs.setInt('last_report:$placeKey', now);
      await loadToilets();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Спасибо! Информация о месте обновлена'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: Text('Не удалось сохранить обновление: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmittingReport = false);
    }
  }

  Future<void> submitVote(
    Map<String, dynamic> place, {
    required bool isCurrent,
  }) async {
    if (isSubmittingVote) return;

    try {
      setState(() => isSubmittingVote = true);
      final prefs = await SharedPreferences.getInstance();
      var voterKey = prefs.getString('voter_key');

      if (voterKey == null || voterKey.length < 12) {
        final randomPart = Random.secure()
            .nextInt(0x7fffffff)
            .toRadixString(16);
        voterKey =
            'device-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
        await prefs.setString('voter_key', voterKey);
      }

      await _toiletRepository.castVote(
        place: place,
        voterKey: voterKey,
        isCurrent: isCurrent,
      );
      await loadToilets();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCurrent
                ? 'Спасибо! Ты подтвердил, что место актуально'
                : 'Спасибо! Отметили, что место нужно проверить',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Не удалось сохранить оценку: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmittingVote = false);
    }
  }

  // =========================================================
  // ПОСТРОЕНИЕ МАРШРУТА
  // =========================================================

  Future<void> buildRoute(Map<String, dynamic> toilet) async {
    try {
      setState(() {
        isBuildingRoute = true;
        routePoints = [];
        routeDistance = null;
        routeDuration = null;
      });

      final locationFound = await _startLocation(requestPermission: true);
      if (!locationFound) {
        throw Exception('Не удалось определить местоположение');
      }

      final double toiletLat = (toilet['lat'] as num).toDouble();
      final double toiletLng = (toilet['lng'] as num).toDouble();
      final result = await _routeService.build(
        from: currentPosition,
        to: LatLng(toiletLat, toiletLng),
      );

      if (!mounted) return;

      setState(() {
        routePoints = result.points;
        routeDistance = result.distance;
        routeDuration = result.duration;
        isBuildingRoute = false;
      });

      if (routePoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(routePoints);

        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            '🧭 Маршрут построен — ${formatDistance(result.distance)}',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Ошибка маршрута: $e');

      if (!mounted) return;

      setState(() {
        isBuildingRoute = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: Colors.red.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text('❌ Не удалось построить маршрут: $e'),
        ),
      );
    }
  }

  // =========================================================
  // ФОРМАТ РАССТОЯНИЯ
  // =========================================================

  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} м';
    }

    return '${(meters / 1000).toStringAsFixed(1)} км';
  }

  // =========================================================
  // ФОРМАТ ВРЕМЕНИ
  // =========================================================

  String formatDuration(double seconds) {
    final int minutes = (seconds / 60).round();

    if (minutes < 60) {
      return '$minutes мин';
    }

    final int hours = minutes ~/ 60;

    final int remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) {
      return '$hours ч';
    }

    return '$hours ч $remainingMinutes мин';
  }

  // =========================================================
  // ОЧИСТКА МАРШРУТА
  // =========================================================

  void clearRoute() {
    setState(() {
      routePoints = [];
      routeDistance = null;
      routeDuration = null;
    });
  }

  void _syncMapCamera() {
    final camera = _mapController.camera;
    if (!mounted) return;
    setState(() {
      _mapZoom = camera.zoom;
      _visibleMapBounds = camera.visibleBounds;
      if (_isPickingLocation) _pickedPosition = camera.center;
    });
  }

  void _handleMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture && _followUser) {
      _followUser = false;
    }

    if (_isPickingLocation) {
      setState(() {
        _mapZoom = camera.zoom;
        _visibleMapBounds = camera.visibleBounds;
        _pickedPosition = camera.center;
      });
      return;
    }

    _cameraUpdateTimer?.cancel();
    _cameraUpdateTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _mapZoom = camera.zoom;
        _visibleMapBounds = camera.visibleBounds;
      });
    });
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ===================================================
          // КАРТА
          // ===================================================
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentPosition,
              initialZoom: 15,
              minZoom: 5.4,
              maxZoom: 19,
              cameraConstraint: CameraConstraint.containCenter(
                bounds: MapDisplayPolicy.kazakhstanBounds,
              ),
              onMapReady: _syncMapCamera,
              onPositionChanged: _handleMapPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tmaps.app',
                keepBuffer: 1,
                panBuffer: 0,
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
                popupInitialDisplayDuration: Duration(seconds: 5),
              ),

              // =================================================
              // МАРШРУТ
              // =================================================
              if (routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      strokeWidth: 8,
                      color: Colors.white,
                    ),
                    Polyline(points: routePoints, strokeWidth: 5, color: green),
                  ],
                ),

              // =================================================
              // ТУАЛЕТЫ
              // =================================================
              if (!_isPickingLocation)
                MarkerLayer(
                  markers: displayedPlaces.map((toilet) {
                    final double lat = (toilet['lat'] as num).toDouble();

                    final double lng = (toilet['lng'] as num).toDouble();

                    final bool isFree = toilet['is_free'] == true;
                    final bool feeKnown = toilet['fee_known'] != false;
                    final placeKind = PlaceInfo.kindOf(toilet);

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 58,
                      height: 68,
                      child: Semantics(
                        button: true,
                        label:
                            '${PlaceInfo.kindLabel(toilet)}: ${PlaceInfo.titleOf(toilet)}',
                        child: GestureDetector(
                          onTap: () {
                            showToiletInfo(toilet);
                          },
                          child: _PlaceMarker(
                            isFree: isFree,
                            feeKnown: feeKnown,
                            placeKind: placeKind,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // =================================================
              // ТЕКУЩЕЕ МЕСТОПОЛОЖЕНИЕ
              // =================================================
              if (_locationState == LocationAccessState.ready)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentPosition,
                      width: 58,
                      height: 58,
                      child: _UserLocationMarker(
                        heading: _locationHeading,
                        accuracy: _locationAccuracy,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ===================================================
          // ВЕРХНЯЯ ПАНЕЛЬ
          // ===================================================
          if (!_isPickingLocation)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: _GlassHeader(
                    username: username,
                    summary: _mapSummary,
                    onInstall: showInstallInstructions,
                  ),
                ),
              ),
            ),

          // ===================================================
          // ЛЕГЕНДА КАТЕГОРИЙ
          // ===================================================
          if (!_isPickingLocation)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 88, 14, 0),
                  child: _MapLegendBar(
                    selectedKind: selectedCategory,
                    onSelected: (kind) {
                      setState(() => selectedCategory = kind);
                    },
                  ),
                ),
              ),
            ),

          // ===================================================
          // КНОПКИ СПРАВА
          // ===================================================
          if (!_isPickingLocation)
            Positioned(
              right: 16,
              bottom: routePoints.length >= 2 ? 150 : 28,
              child: SafeArea(
                child: Column(
                  children: [
                    _MapActionButton(
                      icon: Icons.my_location_rounded,
                      onPressed: centerOnUser,
                      tooltip: 'Моё местоположение',
                      backgroundColor: _followUser
                          ? AppPalette.sky
                          : Colors.white,
                      foregroundColor: _followUser
                          ? Colors.white
                          : AppPalette.ink,
                    ),
                    const SizedBox(height: 12),
                    _MapActionButton(
                      icon: Icons.filter_alt_rounded,
                      onPressed: showFilters,
                      tooltip: 'Фильтры',
                      backgroundColor: filtersActive
                          ? const Color(0xFFDCFCE7)
                          : Colors.white,
                      foregroundColor: filtersActive
                          ? green
                          : const Color(0xFF1F2937),
                    ),
                    const SizedBox(height: 12),
                    _MapActionButton(
                      icon: Icons.near_me_rounded,
                      onPressed: isFindingNearest ? null : showNearestToilet,
                      tooltip: 'Ближайший туалет',
                      child: isFindingNearest
                          ? const SizedBox(
                              width: 21,
                              height: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _MapActionButton(
                      icon: Icons.add_rounded,
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      size: 62,
                      onPressed: isAddingToilet ? null : addToilet,
                      tooltip: 'Добавить место',
                      child: isAddingToilet
                          ? const SizedBox(
                              width: 23,
                              height: 23,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),

          // ===================================================
          // СЧЕТЧИК ТУАЛЕТОВ
          // ===================================================
          if (!_isPickingLocation && displayedPlaces.isNotEmpty)
            Positioned(
              left: 16,
              bottom: routePoints.length >= 2 ? 150 : 28,
              child: SafeArea(
                child: _MapCounter(
                  count: displayedPlaces.length,
                  label: _mapScopeLabel,
                ),
              ),
            ),

          // ===================================================
          // ПАНЕЛЬ МАРШРУТА
          // ===================================================
          if (!_isPickingLocation &&
              routePoints.length >= 2 &&
              routeDistance != null &&
              routeDuration != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: _RoutePanel(
                  distance: formatDistance(routeDistance!),
                  duration: formatDuration(routeDuration!),
                  onClose: clearRoute,
                ),
              ),
            ),

          if (showZoomHint)
            const Positioned(
              left: 16,
              right: 90,
              bottom: 28,
              child: SafeArea(child: MapZoomHint()),
            ),

          if (showEmptyAreaHint)
            Positioned(
              left: 16,
              right: 90,
              bottom: 28,
              child: SafeArea(child: MapEmptyHint(label: _mapScopeLabel)),
            ),

          if (!_isPickingLocation &&
              _locationState != LocationAccessState.ready)
            Positioned(
              left: 16,
              right: 90,
              bottom: 92,
              child: SafeArea(
                child: LocationPromptCard(
                  title: 'GPS не включён',
                  message: _locationHelpMessage,
                  onEnable: centerOnUser,
                ),
              ),
            ),

          if (_isPickingLocation)
            PlacePickerOverlay(
              position: _pickedPosition,
              onCancel: _cancelLocationPicker,
              onConfirm: _confirmPickedLocation,
            ),
        ],
      ),
    );
  }
}

// =============================================================
// ВЕРХНЯЯ ПАНЕЛЬ
// =============================================================

class _GlassHeader extends StatelessWidget {
  final String? username;
  final String summary;
  final VoidCallback onInstall;

  const _GlassHeader({
    required this.username,
    required this.summary,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.96),
                AppPalette.mint.withValues(alpha: 0.18),
                AppPalette.aqua.withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.14),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppPalette.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TMaps',
                      style: TextStyle(
                        fontSize: 21,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onInstall,
                tooltip: 'Установить TMaps',
                icon: const Icon(Icons.install_mobile_rounded, size: 21),
              ),
              if (username != null) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(maxWidth: 105),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFDDE9E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_rounded,
                        size: 16,
                        color: Color(0xFF15803D),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          username!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
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

class _MapLegendBar extends StatelessWidget {
  final PlaceKind? selectedKind;
  final ValueChanged<PlaceKind?> onSelected;

  const _MapLegendBar({required this.selectedKind, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: 0.13),
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 44),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              children: [
                _LegendItem(
                  color: Color(0xFF16A34A),
                  icon: Icons.wc_rounded,
                  label: 'Туалеты',
                  selected: selectedKind == null,
                  onTap: () => onSelected(null),
                ),
                ...PlaceKind.values.map(
                  (kind) => _LegendItem(
                    color: kind.color,
                    icon: kind.icon,
                    label: kind.shortLabel,
                    selected: selectedKind == kind,
                    onTap: () => onSelected(kind),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LegendItem({
    required this.color,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Показать: $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterCategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterCategoryChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: Icon(icon, size: 18, color: selected ? color : Colors.blueGrey),
      label: Text(label),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: selected ? color : const Color(0xFF374151),
      ),
      selectedColor: color.withValues(alpha: 0.13),
      side: BorderSide(
        color: selected
            ? color.withValues(alpha: 0.35)
            : const Color(0xFFE5E7EB),
      ),
      showCheckmark: false,
    );
  }
}

// =============================================================
// МАРКЕР ТУАЛЕТА
// =============================================================

class _PlaceMarker extends StatelessWidget {
  final bool isFree;
  final bool feeKnown;
  final PlaceKind placeKind;

  const _PlaceMarker({
    required this.isFree,
    required this.feeKnown,
    required this.placeKind,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (placeKind) {
      PlaceKind.communityToilet || PlaceKind.publicToilet => (
        _toiletFeeColor(feeKnown: feeKnown, isFree: isFree),
        Icons.wc_rounded,
      ),
      PlaceKind.phoneCharging => (
        const Color(0xFF2563EB),
        Icons.battery_charging_full_rounded,
      ),
      PlaceKind.evCharging => (
        const Color(0xFF0891B2),
        Icons.ev_station_rounded,
      ),
      PlaceKind.cafe => (const Color(0xFFEA580C), Icons.restaurant_rounded),
      PlaceKind.fuel => (
        const Color(0xFF7C3AED),
        Icons.local_gas_station_rounded,
      ),
      PlaceKind.organization => (
        const Color(0xFF0F766E),
        Icons.apartment_rounded,
      ),
    };

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            if (placeKind == PlaceKind.communityToilet)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDB2777),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
        Transform.translate(
          offset: const Offset(0, -5),
          child: CustomPaint(
            size: const Size(12, 8),
            painter: _MarkerTrianglePainter(color: color),
          ),
        ),
      ],
    );
  }
}

class _MarkerTrianglePainter extends CustomPainter {
  final Color color;

  const _MarkerTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MarkerTrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// =============================================================
// МАРКЕР ПОЛЬЗОВАТЕЛЯ
// =============================================================

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker({required this.heading, required this.accuracy});

  final double heading;
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    final isMovingDirectionKnown = heading > 0 && heading <= 360;
    final haloOpacity = accuracy > 60 ? 0.11 : 0.19;

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.sky.withValues(alpha: haloOpacity),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(9),
      child: Transform.rotate(
        angle: isMovingDirectionKnown ? heading * pi / 180 : 0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppPalette.sky,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMovingDirectionKnown ? Icons.navigation_rounded : Icons.circle,
              color: Colors.white,
              size: isMovingDirectionKnown ? 22 : 13,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// КНОПКА КАРТЫ
// =============================================================

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final double size;
  final Widget? child;

  const _MapActionButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.backgroundColor = Colors.white,
    this.foregroundColor = const Color(0xFF1F2937),
    this.size = 54,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      elevation: 9,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: child ?? Icon(icon, size: 25, color: foregroundColor),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

// =============================================================
// СЧЕТЧИК
// =============================================================

class _MapCounter extends StatelessWidget {
  final int count;
  final String label;

  const _MapCounter({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on_rounded,
              color: Color(0xFF16A34A),
              size: 19,
            ),
            const SizedBox(width: 6),
            Text(
              '$count • $label',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// ПАНЕЛЬ МАРШРУТА
// =============================================================

class _RoutePanel extends StatelessWidget {
  final String distance;
  final String duration;
  final VoidCallback onClose;

  const _RoutePanel({
    required this.distance,
    required this.duration,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.directions_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    distance,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    duration,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF3F4F6),
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// CARD / BOTTOM SHEET ТУАЛЕТА
// =============================================================

class _ToiletInfoSheet extends StatelessWidget {
  final String title;
  final String kindLabel;
  final PlaceKind placeKind;
  final String accessLabel;
  final bool hasToilet;
  final String author;
  final bool isFree;
  final bool feeKnown;
  final int cleanliness;
  final String condition;
  final String comment;
  final String distance;
  final bool? hasPaper;
  final bool? hasSoap;
  final bool? wheelchairAccessible;
  final bool? phoneCharging;
  final int reportCount;
  final int likes;
  final int dislikes;
  final bool isBuildingRoute;
  final bool isSubmittingReport;
  final bool isSubmittingVote;
  final ValueChanged<bool> onVote;
  final VoidCallback onReport;
  final VoidCallback onRoute;
  final VoidCallback onClose;

  const _ToiletInfoSheet({
    required this.title,
    required this.kindLabel,
    required this.placeKind,
    required this.accessLabel,
    required this.hasToilet,
    required this.author,
    required this.isFree,
    required this.feeKnown,
    required this.cleanliness,
    required this.condition,
    required this.comment,
    required this.distance,
    required this.hasPaper,
    required this.hasSoap,
    required this.wheelchairAccessible,
    required this.phoneCharging,
    required this.reportCount,
    required this.likes,
    required this.dislikes,
    required this.isBuildingRoute,
    required this.isSubmittingReport,
    required this.isSubmittingVote,
    required this.onVote,
    required this.onReport,
    required this.onRoute,
    required this.onClose,
  });

  IconData get placeIcon {
    return switch (placeKind) {
      PlaceKind.communityToilet || PlaceKind.publicToilet => Icons.wc_rounded,
      PlaceKind.phoneCharging => Icons.battery_charging_full_rounded,
      PlaceKind.evCharging => Icons.ev_station_rounded,
      PlaceKind.cafe => Icons.restaurant_rounded,
      PlaceKind.fuel => Icons.local_gas_station_rounded,
      PlaceKind.organization => Icons.apartment_rounded,
    };
  }

  Color get placeColor {
    return switch (placeKind) {
      PlaceKind.communityToilet || PlaceKind.publicToilet => _toiletFeeColor(
        feeKnown: feeKnown,
        isFree: isFree,
      ),
      _ => placeKind.color,
    };
  }

  bool get isVenue =>
      placeKind == PlaceKind.cafe ||
      placeKind == PlaceKind.fuel ||
      placeKind == PlaceKind.organization;

  Color get conditionColor {
    if (condition == 'Хорошее') {
      return const Color(0xFF16A34A);
    }

    if (condition == 'Среднее') {
      return Colors.orange.shade700;
    }

    if (condition == 'Плохое') {
      return Colors.red.shade600;
    }

    return Colors.blueGrey.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Заголовок
                Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            placeColor.withValues(alpha: 0.12),
                            placeColor.withValues(alpha: 0.22),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Icon(placeIcon, color: placeColor, size: 34),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            kindLabel,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // Информация
                Row(
                  children: [
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.star_rounded,
                        iconColor: cleanliness > 0
                            ? Colors.amber.shade700
                            : Colors.blueGrey.shade600,
                        title: 'Чистота',
                        value: cleanliness > 0
                            ? '$cleanliness / 5'
                            : 'Не указано',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoCard(
                        icon: !feeKnown
                            ? Icons.help_outline_rounded
                            : isFree
                            ? Icons.check_circle_rounded
                            : Icons.payments_rounded,
                        iconColor: !feeKnown
                            ? Colors.blueGrey.shade600
                            : isFree
                            ? const Color(0xFF16A34A)
                            : Colors.orange.shade700,
                        title: hasToilet
                            ? 'Стоимость'
                            : isVenue
                            ? 'Туалет'
                            : 'Зарядка',
                        value: !hasToilet && isVenue
                            ? 'Не подтверждён'
                            : !feeKnown
                            ? 'Не указано'
                            : isFree
                            ? 'Бесплатно'
                            : 'Платный',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.health_and_safety_rounded,
                        iconColor: conditionColor,
                        title: 'Состояние',
                        value: condition,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.person_rounded,
                        iconColor: const Color(0xFF2563EB),
                        title: reportCount > 0 ? 'Обновил' : 'Добавил',
                        value: author,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                _InfoCard(
                  icon: Icons.door_front_door_rounded,
                  iconColor: placeColor,
                  title: 'Доступ',
                  value: accessLabel,
                ),

                const SizedBox(height: 10),

                _InfoCard(
                  icon: Icons.near_me_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Расстояние по прямой',
                  value: distance,
                ),

                const SizedBox(height: 18),

                const Text(
                  'Что есть на месте',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!hasToilet && isVenue)
                      const _AmenityStatusChip(
                        icon: Icons.wc_rounded,
                        label: 'Туалет',
                        value: null,
                      ),
                    if (hasToilet)
                      _AmenityStatusChip(
                        icon: Icons.receipt_long_rounded,
                        label: 'Бумага',
                        value: hasPaper,
                      ),
                    if (hasToilet)
                      _AmenityStatusChip(
                        icon: Icons.soap_rounded,
                        label: 'Мыло',
                        value: hasSoap,
                      ),
                    if (hasToilet)
                      _AmenityStatusChip(
                        icon: Icons.accessible_rounded,
                        label: 'Для коляски',
                        value: wheelchairAccessible,
                      ),
                    _AmenityStatusChip(
                      icon: Icons.bolt_rounded,
                      label: 'Зарядка телефона',
                      value: phoneCharging,
                    ),
                  ],
                ),

                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 19,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              reportCount > 0
                                  ? 'Последний отзыв'
                                  : 'Комментарий',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(
                          comment,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                const Text(
                  'Точка актуальна?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: isSubmittingVote ? null : () => onVote(true),
                        icon: const Icon(Icons.thumb_up_alt_rounded),
                        label: Text('Да · $likes'),
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xFF15803D),
                          backgroundColor: const Color(0xFFDCFCE7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: isSubmittingVote
                            ? null
                            : () => onVote(false),
                        icon: const Icon(Icons.report_problem_rounded),
                        label: Text('Проблема · $dislikes'),
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xFFB45309),
                          backgroundColor: const Color(0xFFFFF7ED),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isSubmittingReport ? null : onReport,
                    icon: const Icon(Icons.rate_review_outlined),
                    label: Text(
                      reportCount == 0
                          ? 'Обновить информацию или оставить отзыв'
                          : 'Отзывы и обновления: $reportCount · Добавить',
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isBuildingRoute ? null : onRoute,
                    icon: isBuildingRoute
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.directions_rounded),
                    label: Text(
                      isBuildingRoute
                          ? 'Строим маршрут...'
                          : 'Построить маршрут',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// INFO CARD
// =============================================================

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _AmenityStatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool? value;

  const _AmenityStatusChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final color = value == true
        ? const Color(0xFF15803D)
        : value == false
        ? const Color(0xFFB91C1C)
        : const Color(0xFF64748B);
    final status = value == true
        ? 'есть'
        : value == false
        ? 'нет'
        : 'неизвестно';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $status',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InstallStep({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF15803D)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceReportDraft {
  final int cleanliness;
  final String condition;
  final bool? hasToilet;
  final bool? hasPaper;
  final bool? hasSoap;
  final bool? wheelchairAccessible;
  final bool? phoneCharging;
  final String accessType;
  final String comment;

  const _PlaceReportDraft({
    required this.cleanliness,
    required this.condition,
    required this.hasToilet,
    required this.hasPaper,
    required this.hasSoap,
    required this.wheelchairAccessible,
    required this.phoneCharging,
    required this.accessType,
    required this.comment,
  });
}

class _PlaceReportSheet extends StatefulWidget {
  final String title;
  final bool canConfirmToilet;
  final bool? initialHasToilet;
  final int? initialCleanliness;
  final String? initialCondition;
  final bool? initialPaper;
  final bool? initialSoap;
  final bool? initialWheelchair;
  final bool? initialPhoneCharging;
  final String? initialAccessType;

  const _PlaceReportSheet({
    required this.title,
    required this.canConfirmToilet,
    required this.initialHasToilet,
    required this.initialCleanliness,
    required this.initialCondition,
    required this.initialPaper,
    required this.initialSoap,
    required this.initialWheelchair,
    required this.initialPhoneCharging,
    required this.initialAccessType,
  });

  @override
  State<_PlaceReportSheet> createState() => _PlaceReportSheetState();
}

class _PlaceReportSheetState extends State<_PlaceReportSheet> {
  late int cleanliness;
  late String condition;
  late bool? hasToilet;
  late bool? hasPaper;
  late bool? hasSoap;
  late bool? wheelchairAccessible;
  late bool? phoneCharging;
  late String accessType;
  final commentController = TextEditingController();

  static const conditions = ['Хорошее', 'Среднее', 'Плохое'];
  static const accessTypes = [
    'public',
    'customers',
    'permissive',
    'destination',
    'unknown',
  ];

  @override
  void initState() {
    super.initState();
    cleanliness =
        widget.initialCleanliness == null ||
            widget.initialCleanliness! < 1 ||
            widget.initialCleanliness! > 5
        ? 3
        : widget.initialCleanliness!;
    condition = conditions.contains(widget.initialCondition)
        ? widget.initialCondition!
        : 'Среднее';
    hasToilet = widget.initialHasToilet;
    hasPaper = widget.initialPaper;
    hasSoap = widget.initialSoap;
    wheelchairAccessible = widget.initialWheelchair;
    phoneCharging = widget.initialPhoneCharging;
    accessType = accessTypes.contains(widget.initialAccessType)
        ? widget.initialAccessType!
        : 'unknown';
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  void submit() {
    final issue = ContentGuard.validateComment(commentController.text);
    if (issue != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(issue)),
      );
      return;
    }

    Navigator.of(context).pop(
      _PlaceReportDraft(
        cleanliness: cleanliness,
        condition: condition,
        hasToilet: hasToilet,
        hasPaper: hasPaper,
        hasSoap: hasSoap,
        wheelchairAccessible: wheelchairAccessible,
        phoneCharging: phoneCharging,
        accessType: accessType,
        comment: commentController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Обновить информацию',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 18),
                const _SectionTitle(
                  icon: Icons.star_outline_rounded,
                  title: 'Текущая оценка',
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    final star = index + 1;
                    return IconButton(
                      onPressed: () => setState(() => cleanliness = star),
                      padding: const EdgeInsets.only(right: 4),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        star <= cleanliness
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber.shade700,
                        size: 36,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: condition,
                  decoration: const InputDecoration(
                    labelText: 'Состояние',
                    prefixIcon: Icon(Icons.health_and_safety_outlined),
                  ),
                  items: conditions
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => condition = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accessType,
                  decoration: const InputDecoration(
                    labelText: 'Кому можно зайти',
                    prefixIcon: Icon(Icons.door_front_door_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('Всем')),
                    DropdownMenuItem(
                      value: 'customers',
                      child: Text('Только клиентам'),
                    ),
                    DropdownMenuItem(
                      value: 'permissive',
                      child: Text('Обычно пускают'),
                    ),
                    DropdownMenuItem(
                      value: 'destination',
                      child: Text('Только посетителям'),
                    ),
                    DropdownMenuItem(value: 'unknown', child: Text('Не знаю')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => accessType = value);
                  },
                ),
                const SizedBox(height: 16),
                if (widget.canConfirmToilet) ...[
                  _TriStateField(
                    label: 'Есть туалет',
                    icon: Icons.wc_rounded,
                    value: hasToilet,
                    onChanged: (value) => setState(() => hasToilet = value),
                  ),
                  const SizedBox(height: 12),
                ],
                if (hasToilet == true) ...[
                  _TriStateField(
                    label: 'Туалетная бумага',
                    icon: Icons.receipt_long_outlined,
                    value: hasPaper,
                    onChanged: (value) => setState(() => hasPaper = value),
                  ),
                  const SizedBox(height: 12),
                  _TriStateField(
                    label: 'Мыло',
                    icon: Icons.soap_outlined,
                    value: hasSoap,
                    onChanged: (value) => setState(() => hasSoap = value),
                  ),
                  const SizedBox(height: 12),
                  _TriStateField(
                    label: 'Доступ для коляски',
                    icon: Icons.accessible_outlined,
                    value: wheelchairAccessible,
                    onChanged: (value) =>
                        setState(() => wheelchairAccessible = value),
                  ),
                  const SizedBox(height: 12),
                ],
                _TriStateField(
                  label: 'Можно зарядить телефон',
                  icon: Icons.bolt_outlined,
                  value: phoneCharging,
                  onChanged: (value) => setState(() => phoneCharging = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  maxLength: 300,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Отзыв или уточнение',
                    hintText: 'Например: бумага есть, вход со двора',
                    alignLabelWithHint: true,
                  ),
                ),
                Text(
                  'Обновление будет видно всем пользователям TMaps.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: submit,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Опубликовать обновление'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TriStateField extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _TriStateField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value == null
          ? 'unknown'
          : value!
          ? 'yes'
          : 'no',
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: const [
        DropdownMenuItem(value: 'yes', child: Text('Есть')),
        DropdownMenuItem(value: 'no', child: Text('Нет')),
        DropdownMenuItem(value: 'unknown', child: Text('Не знаю')),
      ],
      onChanged: (selection) {
        onChanged(switch (selection) {
          'yes' => true,
          'no' => false,
          _ => null,
        });
      },
    );
  }
}

// =============================================================
// ФОРМА ДОБАВЛЕНИЯ
// =============================================================

class _AddToiletSheet extends StatelessWidget {
  final LatLng position;
  final PlaceKind placeKind;
  final bool isFree;
  final int cleanliness;
  final String condition;
  final String comment;

  final ValueChanged<PlaceKind> onPlaceKindChanged;
  final ValueChanged<bool> onFreeChanged;
  final ValueChanged<int> onCleanlinessChanged;
  final ValueChanged<String> onConditionChanged;
  final ValueChanged<String> onCommentChanged;

  final VoidCallback onCancel;
  final VoidCallback onAdd;

  const _AddToiletSheet({
    required this.position,
    required this.placeKind,
    required this.isFree,
    required this.cleanliness,
    required this.condition,
    required this.comment,
    required this.onPlaceKindChanged,
    required this.onFreeChanged,
    required this.onCleanlinessChanged,
    required this.onConditionChanged,
    required this.onCommentChanged,
    required this.onCancel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final isToilet = placeKind == PlaceKind.communityToilet;
    final (placeIcon, placeColor, placeTitle) = switch (placeKind) {
      PlaceKind.phoneCharging => (
        Icons.battery_charging_full_rounded,
        const Color(0xFF2563EB),
        'Зарядка телефона',
      ),
      PlaceKind.evCharging => (
        Icons.ev_station_rounded,
        const Color(0xFF0891B2),
        'Электрозарядка',
      ),
      _ => (Icons.wc_rounded, const Color(0xFF15803D), 'Туалет'),
    };

    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: placeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(placeIcon, color: placeColor, size: 28),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Отправить место',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$placeTitle • '
                          '${position.latitude.toStringAsFixed(5)}, '
                          '${position.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              const _SectionTitle(
                icon: Icons.category_outlined,
                title: 'Категория',
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F3),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        selected: placeKind == PlaceKind.communityToilet,
                        icon: Icons.wc_rounded,
                        text: 'Туалет',
                        color: const Color(0xFF15803D),
                        onTap: () =>
                            onPlaceKindChanged(PlaceKind.communityToilet),
                      ),
                    ),
                    Expanded(
                      child: _ChoiceButton(
                        selected: placeKind == PlaceKind.phoneCharging,
                        icon: Icons.battery_charging_full_rounded,
                        text: 'Телефон',
                        color: const Color(0xFF2563EB),
                        onTap: () =>
                            onPlaceKindChanged(PlaceKind.phoneCharging),
                      ),
                    ),
                    Expanded(
                      child: _ChoiceButton(
                        selected: placeKind == PlaceKind.evCharging,
                        icon: Icons.ev_station_rounded,
                        text: 'Электро',
                        color: const Color(0xFF0891B2),
                        onTap: () => onPlaceKindChanged(PlaceKind.evCharging),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Стоимость
              const _SectionTitle(
                icon: Icons.payments_outlined,
                title: 'Стоимость',
              ),

              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(5),
                child: Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        selected: isFree,
                        icon: Icons.check_circle_outline_rounded,
                        text: 'Бесплатный',
                        color: const Color(0xFF16A34A),
                        onTap: () => onFreeChanged(true),
                      ),
                    ),
                    Expanded(
                      child: _ChoiceButton(
                        selected: !isFree,
                        icon: Icons.payments_outlined,
                        text: 'Платный',
                        color: Colors.orange.shade700,
                        onTap: () => onFreeChanged(false),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Чистота
              _SectionTitle(
                icon: Icons.star_outline_rounded,
                title: isToilet ? 'Чистота' : 'Общая оценка',
              ),

              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppPalette.emerald.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: AppPalette.emerald,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Точка появится на карте после быстрой проверки.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: List.generate(5, (index) {
                  final star = index + 1;

                  return GestureDetector(
                    onTap: () => onCleanlinessChanged(star),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Icon(
                        star <= cleanliness
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber.shade600,
                        size: 37,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 22),

              // Состояние
              const _SectionTitle(
                icon: Icons.health_and_safety_outlined,
                title: 'Состояние',
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                initialValue: condition,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.cleaning_services_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Хорошее',
                    child: Text('🟢  Хорошее'),
                  ),
                  DropdownMenuItem(
                    value: 'Среднее',
                    child: Text('🟡  Среднее'),
                  ),
                  DropdownMenuItem(value: 'Плохое', child: Text('🔴  Плохое')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onConditionChanged(value);
                  }
                },
              ),

              const SizedBox(height: 22),

              // Комментарий
              const _SectionTitle(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Комментарий',
              ),

              const SizedBox(height: 10),

              TextField(
                maxLines: 3,
                maxLength: 300,
                onChanged: onCommentChanged,
                decoration: InputDecoration(
                  hintText: isToilet
                      ? 'Например: находится внутри ТЦ'
                      : 'Например: розетка у стойки, работает круглосуточно',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 55),
                    child: Icon(Icons.edit_note_rounded),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Отправить на проверку'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// ЗАГОЛОВОК СЕКЦИИ
// =============================================================

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF15803D)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

// =============================================================
// КНОПКА ВЫБОРА
// =============================================================

class _ChoiceButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.selected,
    required this.icon,
    required this.text,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? color : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
