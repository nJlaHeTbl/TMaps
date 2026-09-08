import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_config.dart';
import 'core/app_palette.dart';
import 'core/app_theme.dart';
import 'core/content_guard.dart';
import 'core/map_base_style.dart';
import 'core/map_display_policy.dart';
import 'core/map_marker_clustering.dart';
import 'core/map_tile_policy.dart';
import 'core/pedestrian_alert.dart';
import 'core/place_freshness.dart';
import 'core/place_info.dart';
import 'core/quick_need_finder.dart';
import 'core/place_submission_defaults.dart';
import 'core/place_visibility_policy.dart';
import 'core/weather_snapshot.dart';
import 'data/http_community_backend.dart';
import 'data/supabase_community_backend.dart';
import 'data/toilet_repository.dart';
import 'l10n/app_localizations.dart';
import 'presentation/place_category_style.dart';
import 'services/favorites_service.dart';
import 'services/live_location_service.dart';
import 'services/language_preference_service.dart';
import 'services/map_style_preference_service.dart';
import 'services/place_share_service.dart';
import 'services/route_service.dart';
import 'services/submission_history_service.dart';
import 'services/theme_preference_service.dart';
import 'services/weather_service.dart';
import 'services/weather_controller.dart';
import 'widgets/map_overlays.dart';
import 'widgets/location_help_sheet.dart';
import 'widgets/place_search_sheet.dart';

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

  if (!AppConfig.usesCommunityApi) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  }

  runApp(const TMapsApp());
}

class TMapsApp extends StatefulWidget {
  const TMapsApp({super.key});

  @override
  State<TMapsApp> createState() => _TMapsAppState();
}

class _TMapsAppState extends State<TMapsApp> {
  final ThemePreferenceService _themePreferenceService =
      const ThemePreferenceService();
  final LanguagePreferenceService _languagePreferenceService =
      const LanguagePreferenceService();
  ThemeMode _themeMode = ThemeMode.system;
  AppLanguage _language = AppLanguage.system;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTheme());
    unawaited(_loadLanguage());
  }

  Future<void> _loadTheme() async {
    final themeMode = await _themePreferenceService.load();
    if (mounted) setState(() => _themeMode = themeMode);
  }

  Future<void> _setThemeMode(ThemeMode themeMode) async {
    setState(() => _themeMode = themeMode);
    await _themePreferenceService.save(themeMode);
  }

  Future<void> _loadLanguage() async {
    final language = await _languagePreferenceService.load();
    if (mounted) setState(() => _language = language);
  }

  Future<void> _setLanguage(AppLanguage language) async {
    setState(() => _language = language);
    await _languagePreferenceService.save(language);
  }

  Locale? get _selectedLocale => switch (_language) {
    AppLanguage.system => null,
    AppLanguage.russian => const Locale('ru'),
    AppLanguage.kazakh => const Locale('kk'),
    AppLanguage.english => const Locale('en'),
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TMaps',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      locale: _selectedLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeListResolutionCallback: (locales, supportedLocales) {
        for (final locale in locales ?? const <Locale>[]) {
          for (final supportedLocale in supportedLocales) {
            if (supportedLocale.languageCode == locale.languageCode) {
              return supportedLocale;
            }
          }
        }
        return const Locale('ru');
      },
      home: HomePage(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        language: _language,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color green = Color(0xFF16A34A);
  static const double _initialMapZoom = 15.8;
  static const double _minMapZoom = 5.4;
  static const double _maxMapZoom = 19;

  final MapController _mapController = MapController();
  final RouteService _routeService = const RouteService();
  final FavoritesService _favoritesService = const FavoritesService();
  final MapStylePreferenceService _mapStylePreferenceService =
      const MapStylePreferenceService();
  final PlaceShareService _placeShareService = const PlaceShareService();
  final SubmissionHistoryService _submissionHistoryService =
      const SubmissionHistoryService();
  final LiveLocationService _locationService = LiveLocationService();
  final WeatherService _weatherService = WeatherService();
  late final WeatherController _weatherController;

  late final ToiletRepository _toiletRepository;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _cameraUpdateTimer;
  Timer? _weatherUpdateTimer;

  LatLng currentPosition = const LatLng(45.0156, 78.3731);
  LatLng _pickedPosition = const LatLng(45.0156, 78.3731);
  LatLngBounds? _visibleMapBounds;
  LocationAccessState _locationState = LocationAccessState.permissionNeeded;
  double _mapZoom = _initialMapZoom;
  double _locationAccuracy = 0;
  double _locationHeading = 0;
  bool _followUser = false;
  bool _isPickingLocation = false;
  bool _isPickingPedestrianAlert = false;
  Map<String, dynamic>? _locationCorrectionPlace;
  MapBaseStyle _mapBaseStyle = MapBaseStyle.streets;

  final List<Map<String, dynamic>> toilets = [];
  List<PedestrianAlert> _pedestrianAlerts = const [];
  List<PedestrianAlert> _routePedestrianAlerts = const [];
  WeatherSnapshot? get _weather => _weatherController.weather;
  bool get _isLoadingWeather => _weatherController.isLoading;
  bool get _weatherLoadFailed => _weatherController.hasError;
  List<TrackedSubmission> _submissionHistory = const [];
  Set<String> _favoritePlaceKeys = const {};

  String? username;

  bool isAddingToilet = false;
  bool isBuildingRoute = false;
  bool isFindingNearest = false;
  bool isOpeningQuickNeeds = false;
  bool isSubmittingReport = false;
  bool isSubmittingLocationCorrection = false;
  bool isSubmittingVote = false;
  bool isSubmittingHelp = false;
  bool isSubmittingPedestrianAlert = false;
  bool showFreeOnly = false;
  bool showWheelchairOnly = false;
  bool showCommunityOnly = false;
  bool showVenueToilets = true;
  bool showPhoneCharging = true;
  bool showEvCharging = true;
  bool showAllCategories = false;
  bool showToiletPlaces = true;
  bool showPedestrianAlerts = true;
  bool _sharedPlaceHandled = false;
  Set<PlaceKind> selectedCategories = <PlaceKind>{};

  double get _activeMaxMapZoom => _mapBaseStyle == MapBaseStyle.satellite
      ? MapTilePolicy.satelliteMaxDisplayZoom
      : _maxMapZoom;
  int _mapAnimationGeneration = 0;

  List<LatLng> routePoints = [];

  double? routeDistance;
  double? routeDuration;

  Map<String, dynamic> _submissionToPlace(TrackedSubmission submission) {
    final kind = submission.placeKind;
    return <String, dynamic>{
      'id': 'submission_${submission.id}',
      'submission_id': submission.id,
      'submission_status': submission.status,
      'lat': submission.latitude,
      'lng': submission.longitude,
      'username': submission.username,
      'name': submission.name?.trim().isNotEmpty == true
          ? submission.name
          : 'Моя заявка #${submission.id}',
      'place_kind': kind,
      'has_toilet': kind == 'community_toilet',
      'access_type': submission.accessType,
      'is_free': submission.isFree,
      'fee_known': kind == 'community_toilet',
      'cleanliness': submission.cleanliness,
      'condition': submission.condition,
      'has_paper': submission.hasPaper,
      'has_soap': submission.hasSoap,
      'wheelchair_accessible': submission.wheelchairAccessible,
      'phone_charging': submission.phoneCharging,
      'comment': submission.comment,
      'source': 'pending_submission',
      'created_at': submission.createdAt.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> get _pendingSubmissionPlaces => _submissionHistory
      .where(
        (submission) =>
            submission.status == 'pending' ||
            submission.status == 'community_review',
      )
      .map(_submissionToPlace)
      .toList(growable: false);

  List<Map<String, dynamic>> get allPlaces {
    final remoteSubmissionIds = toilets
        .map((place) => (place['submission_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    return [
      ..._pendingSubmissionPlaces.where(
        (place) => !remoteSubmissionIds.contains(place['submission_id']),
      ),
      ...toilets,
    ];
  }

  List<Map<String, dynamic>> get visibleToilets {
    return allPlaces
        .where(
          (place) => PlaceVisibilityPolicy.matches(
            place,
            showAllCategories: showAllCategories,
            showToiletPlaces: showToiletPlaces,
            selectedCategories: selectedCategories,
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

  List<PlaceMarkerGroup> get displayedPlaceGroups {
    final size = MediaQuery.sizeOf(context);
    return MapMarkerClustering.group(
      displayedPlaces,
      bounds: _visibleMapBounds,
      viewportWidth: size.width,
      viewportHeight: size.height,
      zoom: _mapZoom,
    );
  }

  List<PedestrianAlert> get displayedPedestrianAlerts {
    if (!showPedestrianAlerts || _mapZoom < 12.8) return const [];
    final bounds = _visibleMapBounds;
    return _pedestrianAlerts
        .where((alert) => bounds == null || bounds.contains(alert.position))
        .take(80)
        .toList(growable: false);
  }

  bool get showZoomHint =>
      !MapDisplayPolicy.canShowPlaces(_mapZoom) && !_isPickingLocation;

  bool get showEmptyAreaHint =>
      MapDisplayPolicy.canShowPlaces(_mapZoom) &&
      displayedPlaces.isEmpty &&
      visibleToilets.isNotEmpty &&
      !_isPickingLocation;

  int get _selectedCategoryCount =>
      (showToiletPlaces ? 1 : 0) + selectedCategories.length;

  String get _mapScopeLabel {
    if (showAllCategories) return context.l10n.translate('Все места');
    final labels = <String>[
      if (showToiletPlaces) context.l10n.translate('Туалеты'),
      ...selectedCategories.map(
        (kind) => context.l10n.translate(kind.shortLabel),
      ),
    ];
    if (labels.length <= 2) return labels.join(' + ');
    return context.l10n.translate('{count} категории', {
      'count': labels.length,
    });
  }

  String get _mapSummary => context.l10n.translate(
    showAllCategories
        ? '{count} мест • все категории'
        : '{count} мест • {scope}',
    {'count': visibleToilets.length, 'scope': _mapScopeLabel},
  );

  IconData get _clusterIcon {
    if (showAllCategories || _selectedCategoryCount != 1) {
      return Icons.layers_rounded;
    }
    if (showToiletPlaces) return Icons.wc_rounded;
    return selectedCategories.single.icon;
  }

  Color get _clusterColor {
    if (showAllCategories || _selectedCategoryCount != 1) {
      return AppPalette.aqua;
    }
    if (showToiletPlaces) return AppPalette.emerald;
    return selectedCategories.single.color;
  }

  bool get filtersActive =>
      showAllCategories ||
      !showToiletPlaces ||
      selectedCategories.isNotEmpty ||
      showFreeOnly ||
      showWheelchairOnly ||
      showCommunityOnly ||
      !showVenueToilets ||
      !showPhoneCharging ||
      !showEvCharging;

  List<Map<String, dynamic>> get favoritePlaces => allPlaces
      .where((place) => _favoritePlaceKeys.contains(PlaceInfo.keyOf(place)))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();

    _weatherController = WeatherController(fetch: _weatherService.fetch)
      ..addListener(_onWeatherChanged);

    final communityBackend = AppConfig.usesCommunityApi
        ? HttpCommunityBackend(baseUrl: AppConfig.communityApiBaseUrl)
        : SupabaseCommunityBackend(Supabase.instance.client);
    _toiletRepository = ToiletRepository(communityBackend);

    _locationSubscription = _locationService.positions.listen(_applyPosition);

    loadUsername();
    unawaited(_loadMapBaseStyle());
    unawaited(_loadFavorites());
    unawaited(_startLocation(requestPermission: false));
    unawaited(_loadInitialCommunityData());
    unawaited(_loadWeatherFor(currentPosition));
  }

  @override
  void dispose() {
    _cameraUpdateTimer?.cancel();
    _weatherUpdateTimer?.cancel();
    unawaited(_locationSubscription?.cancel());
    unawaited(_locationService.dispose());
    _weatherController.dispose();
    _weatherService.dispose();
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

      unawaited(_focusSharedPlaceIfReady());

      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showUsernameDialog();
      }
    });
  }

  Future<void> _loadMapBaseStyle() async {
    final savedStyle = await _mapStylePreferenceService.load();
    if (!mounted) return;
    setState(() => _mapBaseStyle = savedStyle);
  }

  Future<void> _setMapBaseStyle(MapBaseStyle style) async {
    if (_mapBaseStyle == style) return;

    final previousStyle = _mapBaseStyle;
    setState(() => _mapBaseStyle = style);

    if (style == MapBaseStyle.satellite &&
        _mapZoom > MapTilePolicy.satelliteMaxDisplayZoom) {
      unawaited(
        _animateMapTo(
          _mapController.camera.center,
          MapTilePolicy.satelliteMaxDisplayZoom,
        ),
      );
    }

    try {
      await _mapStylePreferenceService.save(style);
    } catch (_) {
      if (!mounted) return;
      setState(() => _mapBaseStyle = previousStyle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText('Не удалось сохранить выбранный слой карты'),
        ),
      );
    }
  }

  void showMapStylePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _MapStyleSheet(
        selectedStyle: _mapBaseStyle,
        onSelected: (style) {
          Navigator.of(sheetContext).pop();
          unawaited(_setMapBaseStyle(style));
        },
      ),
    );
  }

  Future<void> _loadFavorites() async {
    final savedKeys = await _favoritesService.load();
    if (!mounted) return;
    setState(() => _favoritePlaceKeys = savedKeys);
  }

  Future<void> _loadSubmissionHistory() async {
    final submissions = await _submissionHistoryService.refreshLifecycle();
    if (!mounted) return;
    setState(() => _submissionHistory = submissions);
  }

  Future<void> _loadInitialCommunityData() async {
    await _loadSubmissionHistory();
    await loadToilets();
    await _focusSharedPlaceIfReady();
  }

  Future<void> _focusSharedPlaceIfReady() async {
    if (_sharedPlaceHandled || username == null || allPlaces.isEmpty) return;
    final place = _placeShareService.findLinkedPlace(Uri.base, allPlaces);
    if (place == null) return;

    _sharedPlaceHandled = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted) await _focusOnPlace(place);
  }

  bool _isFavorite(Map<String, dynamic> place) {
    return _favoritePlaceKeys.contains(PlaceInfo.keyOf(place));
  }

  Future<bool> _toggleFavorite(Map<String, dynamic> place) async {
    final placeKey = PlaceInfo.keyOf(place);
    final wasFavorite = _favoritePlaceKeys.contains(placeKey);
    final updatedKeys = Set<String>.of(_favoritePlaceKeys);
    wasFavorite ? updatedKeys.remove(placeKey) : updatedKeys.add(placeKey);

    setState(() => _favoritePlaceKeys = updatedKeys);

    try {
      await _favoritesService.save(updatedKeys);
    } catch (_) {
      if (mounted) {
        setState(() {
          _favoritePlaceKeys = Set<String>.of(_favoritePlaceKeys)
            ..remove(placeKey)
            ..addAll(wasFavorite ? {placeKey} : const <String>{});
        });
      }
      return wasFavorite;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: LocalizedText(
            wasFavorite
                ? 'Место удалено из избранного'
                : 'Место сохранено в избранное',
          ),
        ),
      );
    }
    return !wasFavorite;
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
                const LocalizedText(
                  'Добро пожаловать в TMaps',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  'Как тебя называть?',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('Имя'),
                    hintText: context.l10n.translate('Например: Мирас'),
                    prefixIcon: const Icon(Icons.person_outline),
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
                            content: LocalizedText(issue),
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
                      unawaited(_focusSharedPlaceIfReady());
                      unawaited(
                        _startLocation(requestPermission: true, center: true),
                      );
                    },
                    child: const LocalizedText('Продолжить'),
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

  void _scheduleWeather(LatLng position) {
    _weatherUpdateTimer?.cancel();
    _weatherUpdateTimer = Timer(
      const Duration(milliseconds: 850),
      () => unawaited(_loadWeatherFor(position)),
    );
  }

  void _onWeatherChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadWeatherFor(LatLng position, {bool force = false}) =>
      _weatherController.load(position, force: force);

  Future<void> _showWeatherDetails() async {
    final weather = _weather;
    if (weather == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnimatedBuilder(
        animation: _weatherController,
        builder: (_, _) => _WeatherDetailsSheet(
          weather: _weather ?? weather,
          isRefreshing: _isLoadingWeather,
          hasError: _weatherLoadFailed,
          onRefresh: () =>
              _loadWeatherFor(_mapController.camera.center, force: true),
        ),
      ),
    );
  }

  Future<void> centerOnUser() async {
    setState(() => _followUser = true);
    final locationFound = await _startLocation(
      requestPermission: true,
      center: true,
    );
    if (!mounted || locationFound) return;

    setState(() => _followUser = false);
    await _presentLocationHelp();
  }

  Future<void> _presentLocationHelp({VoidCallback? onRetry}) async {
    if (!mounted) return;

    if (kIsWeb || _locationState == LocationAccessState.deniedForever) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LocationHelpSheet(
          isWeb: kIsWeb,
          permissionBlocked:
              _locationState == LocationAccessState.deniedForever,
          onRetry: onRetry ?? centerOnUser,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(_locationHelpMessage)));
  }

  String get _locationHelpMessage => switch (_locationState) {
    LocationAccessState.permissionNeeded =>
      kIsWeb
          ? 'Нажми и разреши геопозицию в браузере'
          : 'Нажми «Включить GPS» и разреши доступ к геопозиции',
    LocationAccessState.deniedForever =>
      kIsWeb
          ? 'Доступ заблокирован — нажми, чтобы исправить'
          : 'Разреши геопозицию для TMaps в настройках телефона',
    LocationAccessState.servicesDisabled =>
      'Включи GPS на телефоне и повтори попытку',
    LocationAccessState.unavailable =>
      kIsWeb
          ? 'Нет координат — проверь разрешение браузера'
          : 'Не удалось получить координаты. Проверь GPS и интернет',
    LocationAccessState.ready => 'Геопозиция работает',
  };

  Future<void> showQuickNeeds() async {
    if (isOpeningQuickNeeds) return;
    setState(() => isOpeningQuickNeeds = true);

    try {
      final locationFound = await _startLocation(requestPermission: true);
      if (!locationFound) {
        await _presentLocationHelp();
        return;
      }

      final results = QuickNeedFinder.findNearest(
        places: allPlaces,
        origin: currentPosition,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: LocalizedText(
              'Рядом пока нет подтверждённых полезных мест',
            ),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _QuickNeedsSheet(
          results: results,
          distanceLabel: formatDistance,
          onSelected: (place) => Navigator.of(sheetContext).pop(place),
        ),
      );
      if (selected != null && mounted) await _focusOnPlace(selected);
    } finally {
      if (mounted) setState(() => isOpeningQuickNeeds = false);
    }
  }

  Future<void> _copyPlaceLink(Map<String, dynamic> place) async {
    try {
      await _placeShareService.copyLink(place);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(
            'Ссылка на место скопирована — отправь её другу',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText('Не удалось скопировать ссылку'),
        ),
      );
    }
  }

  Future<void> showNearestToilet() async {
    if (isFindingNearest) return;

    setState(() {
      isFindingNearest = true;
    });

    try {
      final availableToilets = allPlaces
          .where(
            (place) => PlaceVisibilityPolicy.matches(
              place,
              showAllCategories: false,
              showToiletPlaces: true,
              selectedCategories: const <PlaceKind>{},
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
        if (!mounted) return;
        setState(() => isFindingNearest = false);
        await _presentLocationHelp(
          onRetry: () => unawaited(showNearestToilet()),
        );
        return;
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
          content: LocalizedText(
            error.toString().replaceFirst('Exception: ', ''),
          ),
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

  Future<void> showPlaceSearch() async {
    final camera = _mapController.camera;
    final place = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) =>
          PlaceSearchSheet(places: allPlaces, origin: camera.center),
    );

    if (place == null || !mounted) return;
    await _focusOnPlace(place);
  }

  Future<void> showFavorites() async {
    final camera = _mapController.camera;
    final places = favoritePlaces;
    final place = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => PlaceSearchSheet(
        places: places,
        origin: camera.center,
        title: 'Избранное',
        subtitle: '${places.length} сохранено на этом устройстве',
        headerIcon: Icons.bookmarks_rounded,
        autofocus: false,
        sectionLabel: 'Сохранённые места',
        emptyTitle: 'Избранное пока пусто',
        emptyMessage: 'Открой любое место на карте и нажми на значок закладки',
      ),
    );

    if (place == null || !mounted) return;
    await _focusOnPlace(place);
  }

  Future<void> _focusOnPlace(Map<String, dynamic> place) async {
    if (!mounted) return;

    final kind = PlaceInfo.kindOf(place);
    final point = LatLng(
      (place['lat'] as num).toDouble(),
      (place['lng'] as num).toDouble(),
    );

    final isToiletCategory =
        kind == PlaceKind.publicToilet || kind == PlaceKind.communityToilet;
    setState(() {
      showAllCategories = false;
      showToiletPlaces = isToiletCategory;
      selectedCategories = isToiletCategory ? <PlaceKind>{} : {kind};
      _followUser = false;
    });
    await _animateMapTo(point, max(_mapZoom, 16.8));

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (mounted) showToiletInfo(place);
  }

  void _showAllMapCategories() {
    setState(() {
      showAllCategories = true;
      showToiletPlaces = false;
      selectedCategories = <PlaceKind>{};
    });
  }

  void _toggleToiletCategory() {
    setState(() {
      if (showAllCategories) {
        showAllCategories = false;
        showToiletPlaces = true;
        selectedCategories = <PlaceKind>{};
        return;
      }

      showToiletPlaces = !showToiletPlaces;
      if (!showToiletPlaces && selectedCategories.isEmpty) {
        showAllCategories = true;
      }
    });
  }

  void _toggleMapCategory(PlaceKind kind) {
    var wasEnabled = false;
    setState(() {
      if (showAllCategories) {
        showAllCategories = false;
        showToiletPlaces = false;
        selectedCategories = {kind};
        wasEnabled = true;
        return;
      }

      final updated = Set<PlaceKind>.of(selectedCategories);
      if (updated.remove(kind)) {
        wasEnabled = false;
      } else {
        updated.add(kind);
        wasEnabled = true;
      }
      selectedCategories = updated;
      if (!showToiletPlaces && selectedCategories.isEmpty) {
        showAllCategories = true;
      }
    });

    if (wasEnabled && kind == PlaceKind.water) {
      unawaited(_focusNearbyWater());
    }
  }

  Future<void> _focusNearbyWater() async {
    final cameraCenter = _mapController.camera.center;
    final nearbyWater = allPlaces
        .where((place) {
          if (PlaceInfo.kindOf(place) != PlaceKind.water) return false;
          final distance = Geolocator.distanceBetween(
            cameraCenter.latitude,
            cameraCenter.longitude,
            (place['lat'] as num).toDouble(),
            (place['lng'] as num).toDouble(),
          );
          return distance <= 25000;
        })
        .toList(growable: false);

    if (nearbyWater.isEmpty) return;

    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLng = double.infinity;
    var maxLng = -double.infinity;
    for (final place in nearbyWater) {
      final lat = (place['lat'] as num).toDouble();
      final lng = (place['lng'] as num).toDouble();
      minLat = min(minLat, lat);
      maxLat = max(maxLat, lat);
      minLng = min(minLng, lng);
      maxLng = max(maxLng, lng);
    }

    final span = max(maxLat - minLat, maxLng - minLng);
    final zoom = switch (span) {
      > 0.06 => 13.9,
      > 0.035 => 14.45,
      > 0.018 => 15.0,
      _ => 15.7,
    };
    await _animateMapTo(
      LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
      zoom,
    );
  }

  Future<void> _animateMapTo(LatLng target, double zoom) async {
    final generation = ++_mapAnimationGeneration;
    final camera = _mapController.camera;
    final startCenter = camera.center;
    final startZoom = camera.zoom;
    const frames = 18;

    for (var frame = 1; frame <= frames; frame++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || generation != _mapAnimationGeneration) return;
      final progress = Curves.easeOutCubic.transform(frame / frames);
      _mapController.move(
        LatLng(
          ui.lerpDouble(startCenter.latitude, target.latitude, progress)!,
          ui.lerpDouble(startCenter.longitude, target.longitude, progress)!,
        ),
        ui.lerpDouble(startZoom, zoom, progress)!,
      );
    }
  }

  Future<void> showFilters() async {
    var allCategories = showAllCategories;
    var toiletPlaces = showToiletPlaces;
    var categories = Set<PlaceKind>.of(selectedCategories);
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
                    const LocalizedText(
                      'Фильтры карты',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const LocalizedText(
                      'Выбирай сразу несколько категорий — например, туалеты и питьевую воду.',
                      style: TextStyle(color: AppPalette.muted, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    const LocalizedText(
                      'Что показать',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterCategoryChip(
                          label: 'Все места',
                          icon: Icons.layers_rounded,
                          color: AppPalette.aqua,
                          selected: allCategories,
                          onSelected: () {
                            setSheetState(() {
                              allCategories = true;
                              toiletPlaces = false;
                              categories.clear();
                            });
                          },
                        ),
                        _FilterCategoryChip(
                          label: 'Все туалеты',
                          icon: Icons.wc_rounded,
                          color: green,
                          selected: !allCategories && toiletPlaces,
                          onSelected: () {
                            setSheetState(() {
                              if (allCategories) {
                                allCategories = false;
                                toiletPlaces = true;
                                categories.clear();
                                return;
                              }
                              toiletPlaces = !toiletPlaces;
                              if (!toiletPlaces && categories.isEmpty) {
                                allCategories = true;
                              }
                            });
                          },
                        ),
                        ...PlaceKind.values.map(
                          (kind) => _FilterCategoryChip(
                            label: kind.shortLabel,
                            icon: kind.icon,
                            color: kind.color,
                            selected:
                                !allCategories && categories.contains(kind),
                            onSelected: () {
                              setSheetState(() {
                                if (allCategories) {
                                  allCategories = false;
                                  toiletPlaces = false;
                                  categories = {kind};
                                  return;
                                }
                                final updated = Set<PlaceKind>.of(categories);
                                if (!updated.remove(kind)) {
                                  updated.add(kind);
                                }
                                categories = updated;
                                if (!toiletPlaces && categories.isEmpty) {
                                  allCategories = true;
                                }
                              });
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
                      title: const LocalizedText('Только бесплатные'),
                      subtitle: const LocalizedText(
                        'Скрыть платные и без цены',
                      ),
                      value: freeOnly,
                      onChanged: (value) {
                        setSheetState(() => freeOnly = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('Доступно для коляски'),
                      subtitle: const LocalizedText(
                        'Только места с подтверждённым доступом',
                      ),
                      value: wheelchairOnly,
                      onChanged: (value) {
                        setSheetState(() => wheelchairOnly = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('Добавленные пользователями'),
                      subtitle: const LocalizedText(
                        'Скрыть автоматически загруженные точки',
                      ),
                      value: communityOnly,
                      onChanged: (value) {
                        setSheetState(() => communityOnly = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText(
                        'Туалеты в кафе, АЗС и организациях',
                      ),
                      subtitle: const LocalizedText(
                        'Места с доступом для клиентов или посетителей',
                      ),
                      value: venueToilets,
                      onChanged: (value) {
                        setSheetState(() => venueToilets = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('Зарядка телефона'),
                      subtitle: const LocalizedText(
                        'Точки зарядки мобильных устройств',
                      ),
                      value: phoneCharging,
                      onChanged: (value) {
                        setSheetState(() => phoneCharging = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('Электрозарядные станции'),
                      subtitle: const LocalizedText(
                        'Зарядка для электромобилей',
                      ),
                      value: evCharging,
                      onChanged: (value) {
                        setSheetState(() => evCharging = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                showAllCategories = true;
                                showToiletPlaces = false;
                                selectedCategories = <PlaceKind>{};
                                showFreeOnly = false;
                                showWheelchairOnly = false;
                                showCommunityOnly = false;
                                showVenueToilets = true;
                                showPhoneCharging = true;
                                showEvCharging = true;
                              });
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.layers_clear_rounded),
                            label: const LocalizedText('Показать всё'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                showAllCategories = allCategories;
                                showToiletPlaces = toiletPlaces;
                                selectedCategories = Set<PlaceKind>.of(
                                  categories,
                                );
                                showFreeOnly = freeOnly;
                                showWheelchairOnly = wheelchairOnly;
                                showCommunityOnly = communityOnly;
                                showVenueToilets = venueToilets;
                                showPhoneCharging = phoneCharging;
                                showEvCharging = evCharging;
                              });
                              Navigator.of(context).pop();
                            },
                            child: const LocalizedText('Применить'),
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
                LocalizedText(
                  'Установить TMaps',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                LocalizedText(
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
      final alertsFuture = _loadPedestrianAlertsSafely();
      final loadedToilets = await _toiletRepository.fetchAll();
      final loadedAlerts = await alertsFuture;
      await _submissionHistoryService.reconcilePublishedPlaces(loadedToilets);
      final visibleSubmissionHistory = await _submissionHistoryService
          .refreshLifecycle();

      if (!mounted) return;

      setState(() {
        _submissionHistory = visibleSubmissionHistory;
        toilets
          ..clear()
          ..addAll(loadedToilets);
        _pedestrianAlerts = loadedAlerts;
        _routePedestrianAlerts = PedestrianAlertPolicy.nearRoute(
          loadedAlerts,
          routePoints,
        );
      });

      debugPrint('Загружено туалетов: ${toilets.length}');
    } catch (e) {
      debugPrint('Ошибка загрузки туалетов: $e');
    }
  }

  Future<List<PedestrianAlert>> _loadPedestrianAlertsSafely() async {
    try {
      return await _toiletRepository.fetchPedestrianAlerts();
    } on Object catch (error) {
      debugPrint('Предупреждения пешеходов пока недоступны: $error');
      return const [];
    }
  }

  Future<void> showSubmissionHistory() async {
    final selected = await showModalBottomSheet<TrackedSubmission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SubmissionHistorySheet(
        submissions: _submissionHistory,
        onSelect: (submission) => Navigator.of(context).pop(submission),
      ),
    );

    if (selected == null || !mounted) return;
    await _focusOnPlace(_submissionToPlace(selected));
  }

  // =========================================================
  // ДОБАВЛЕНИЕ ТУАЛЕТА
  // =========================================================

  Future<bool> _ensureValidUsername() async {
    if (ContentGuard.validateUsername(username) == null) return true;

    await showUsernameDialog();
    return mounted && ContentGuard.validateUsername(username) == null;
  }

  Future<void> addToilet() async {
    if (isAddingToilet) return;

    final mode = await showModalBottomSheet<AddLocationMode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          AddLocationChoiceSheet(submissionCount: _submissionHistory.length),
    );
    if (!mounted || mode == null) return;

    if (mode == AddLocationMode.submissions) {
      await showSubmissionHistory();
      return;
    }

    if (mode == AddLocationMode.roadAlert) {
      await _startPedestrianAlertFlow();
      return;
    }

    if (!await _ensureValidUsername()) return;

    if (mode == AddLocationMode.current) {
      setState(() => isAddingToilet = true);
      final locationFound = await _startLocation(
        requestPermission: true,
        center: true,
      );
      if (!mounted) return;
      if (!locationFound) {
        setState(() => isAddingToilet = false);
        await _presentLocationHelp();
        return;
      }
      await _showAddPlaceForm(currentPosition);
      return;
    }

    _beginLocationPicker();
  }

  void _beginLocationPicker([LatLng? position]) {
    if (isAddingToilet) return;

    final camera = _mapController.camera;
    final target = position ?? camera.center;
    setState(() {
      _followUser = false;
      _isPickingLocation = true;
      _isPickingPedestrianAlert = false;
      _locationCorrectionPlace = null;
      _pickedPosition = target;
    });
    if (position != null) {
      _mapController.move(target, max(camera.zoom, 16.2));
    }
  }

  void _cancelLocationPicker() {
    setState(() {
      _isPickingLocation = false;
      _isPickingPedestrianAlert = false;
      _locationCorrectionPlace = null;
    });
  }

  Future<void> _confirmPickedLocation() async {
    if (!await _ensureValidUsername()) return;

    final position = _pickedPosition;
    if (_isPickingPedestrianAlert) {
      setState(() {
        _isPickingLocation = false;
        _isPickingPedestrianAlert = false;
      });
      await _showPedestrianAlertForm(position);
      return;
    }
    final correctionPlace = _locationCorrectionPlace;
    if (correctionPlace != null) {
      await _submitLocationCorrection(correctionPlace, position);
      return;
    }
    setState(() {
      _isPickingLocation = false;
      isAddingToilet = true;
    });
    await _showAddPlaceForm(position);
  }

  Future<void> _startPedestrianAlertFlow() async {
    if (isSubmittingPedestrianAlert || !await _ensureValidUsername()) return;
    if (!mounted) return;

    final locationMode =
        await showModalBottomSheet<PedestrianAlertLocationMode>(
          context: context,
          showDragHandle: true,
          builder: (_) => const PedestrianAlertLocationSheet(),
        );
    if (!mounted || locationMode == null) return;

    if (locationMode == PedestrianAlertLocationMode.current) {
      final locationFound = await _startLocation(
        requestPermission: true,
        center: true,
      );
      if (!mounted) return;
      if (!locationFound) {
        await _presentLocationHelp();
        return;
      }
      await _showPedestrianAlertForm(currentPosition);
      return;
    }

    final camera = _mapController.camera;
    setState(() {
      _followUser = false;
      _isPickingLocation = true;
      _isPickingPedestrianAlert = true;
      _locationCorrectionPlace = null;
      _pickedPosition = camera.center;
    });
  }

  Future<void> _showPedestrianAlertForm(LatLng position) async {
    final draft = await showModalBottomSheet<PedestrianAlertDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PedestrianAlertFormSheet(position: position),
    );
    if (draft == null || !mounted) return;
    await _submitPedestrianAlert(position, draft);
  }

  Future<void> _submitPedestrianAlert(
    LatLng position,
    PedestrianAlertDraft draft,
  ) async {
    setState(() => isSubmittingPedestrianAlert = true);
    try {
      await _toiletRepository.submitPedestrianAlert(
        position: position,
        draft: draft,
        username: username!,
        reporterKey: await _deviceVoterKey(),
      );
      final alerts = await _loadPedestrianAlertsSafely();
      if (!mounted) return;
      setState(() {
        _pedestrianAlerts = alerts;
        _routePedestrianAlerts = PedestrianAlertPolicy.nearRoute(
          alerts,
          routePoints,
        );
        showPedestrianAlerts = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(
            draft.type == PedestrianAlertType.open
                ? 'Спасибо! Участок отмечен как открытый'
                : 'Предупреждение опубликовано и исчезнет автоматически',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: LocalizedText('Не удалось отправить предупреждение: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmittingPedestrianAlert = false);
    }
  }

  Future<void> _showPedestrianAlertInfo(PedestrianAlert alert) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PedestrianAlertInfoSheet(alert: alert),
    );
  }

  Future<void> _beginLocationCorrection(Map<String, dynamic> place) async {
    if (isSubmittingLocationCorrection || !await _ensureValidUsername()) return;
    if (!mounted) return;

    final target = LatLng(
      (place['lat'] as num).toDouble(),
      (place['lng'] as num).toDouble(),
    );
    final camera = _mapController.camera;
    setState(() {
      _followUser = false;
      _locationCorrectionPlace = Map<String, dynamic>.from(place);
      _pickedPosition = target;
      _isPickingLocation = true;
      _isPickingPedestrianAlert = false;
    });
    _mapController.move(target, max(camera.zoom, 17.2));
  }

  Future<void> _submitLocationCorrection(
    Map<String, dynamic> place,
    LatLng position,
  ) async {
    final placeKey = PlaceInfo.keyOf(place);
    final prefs = await SharedPreferences.getInstance();
    final lastCorrectionAt = prefs.getInt('last_location_correction:$placeKey');
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lastCorrectionAt != null && now - lastCorrectionAt < 300000) {
      if (!mounted) return;
      setState(() {
        _isPickingLocation = false;
        _locationCorrectionPlace = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(
            'Подожди 5 минут перед новой заявкой на перенос этой точки',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isPickingLocation = false;
      _locationCorrectionPlace = null;
      isSubmittingLocationCorrection = true;
    });

    try {
      final correctionId = await _toiletRepository.submitLocationCorrection(
        place: place,
        proposedLatitude: position.latitude,
        proposedLongitude: position.longitude,
        username: username!,
      );
      await prefs.setInt('last_location_correction:$placeKey', now);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(
            'Заявка #$correctionId на перенос отправлена. '
            'Метка изменится после проверки.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: LocalizedText('Не удалось отправить перенос: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmittingLocationCorrection = false);
    }
  }

  Future<void> _showAddPlaceForm(LatLng position) async {
    try {
      var placeName = '';
      var placeKind = PlaceKind.communityToilet;
      var hasChosenPlaceKind = false;
      var outdoorToilet = false;
      var defaults = PlaceSubmissionDefaults.forKind(placeKind);
      var isFree = defaults.isFree;
      var cleanliness = defaults.rating;
      var condition = defaults.condition;
      var hasPaper = defaults.hasPaper;
      var hasSoap = defaults.hasSoap;
      var wheelchairAccessible = defaults.wheelchairAccessible;
      var phoneCharging = defaults.phoneCharging;
      var accessType = defaults.accessType;
      var comment = '';

      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return _AddPlaceSheet(
                position: position,
                placeKind: placeKind,
                categoryChosen: hasChosenPlaceKind,
                placeName: placeName,
                outdoorToilet: outdoorToilet,
                isFree: isFree,
                cleanliness: cleanliness,
                condition: condition,
                hasPaper: hasPaper,
                hasSoap: hasSoap,
                wheelchairAccessible: wheelchairAccessible,
                phoneCharging: phoneCharging,
                accessType: accessType,
                comment: comment,
                onPlaceKindChanged: (value) {
                  setDialogState(() {
                    placeKind = value;
                    hasChosenPlaceKind = true;
                    outdoorToilet = false;
                    defaults = PlaceSubmissionDefaults.forKind(value);
                    isFree = defaults.isFree;
                    cleanliness = defaults.rating;
                    condition = defaults.condition;
                    hasPaper = defaults.hasPaper;
                    hasSoap = defaults.hasSoap;
                    wheelchairAccessible = defaults.wheelchairAccessible;
                    phoneCharging = defaults.phoneCharging;
                    accessType = defaults.accessType;
                  });
                },
                onPlaceNameChanged: (value) => placeName = value,
                onOutdoorToiletChanged: (value) {
                  setDialogState(() {
                    outdoorToilet = value;
                    defaults = value
                        ? PlaceSubmissionDefaults.outdoorToilet
                        : PlaceSubmissionDefaults.forKind(placeKind);
                    isFree = defaults.isFree;
                    cleanliness = defaults.rating;
                    condition = defaults.condition;
                    hasPaper = defaults.hasPaper;
                    hasSoap = defaults.hasSoap;
                    wheelchairAccessible = defaults.wheelchairAccessible;
                    phoneCharging = defaults.phoneCharging;
                    accessType = defaults.accessType;
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
                onPaperChanged: (value) {
                  setDialogState(() => hasPaper = value);
                },
                onSoapChanged: (value) {
                  setDialogState(() => hasSoap = value);
                },
                onWheelchairChanged: (value) {
                  setDialogState(() => wheelchairAccessible = value);
                },
                onPhoneChargingChanged: (value) {
                  setDialogState(() => phoneCharging = value);
                },
                onAccessTypeChanged: (value) {
                  setDialogState(() => accessType = value);
                },
                onCommentChanged: (value) {
                  comment = value;
                },
                onCancel: () {
                  Navigator.of(context).pop(false);
                },
                onAdd: () {
                  if (!hasChosenPlaceKind) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: LocalizedText(
                          'Сначала выбери тип места: туалет, кафе, организацию или другое',
                        ),
                      ),
                    );
                    return;
                  }
                  final requiresName =
                      placeKind == PlaceKind.cafe ||
                      placeKind == PlaceKind.fuel ||
                      placeKind == PlaceKind.organization;
                  if (requiresName && placeName.trim().length < 2) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: LocalizedText(
                          'Напиши название места или организации',
                        ),
                      ),
                    );
                    return;
                  }
                  final issue = ContentGuard.validateComment(comment);
                  if (issue != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: LocalizedText(issue),
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
        name: placeName.trim().isEmpty ? null : placeName.trim(),
        isFree: isFree,
        cleanliness: cleanliness,
        condition: condition,
        hasPaper: hasPaper,
        hasSoap: hasSoap,
        wheelchairAccessible: wheelchairAccessible,
        phoneCharging: phoneCharging,
        accessType: accessType,
        deviceKey: await _deviceVoterKey(),
        comment: comment.trim().isEmpty ? null : comment.trim(),
      );

      final trackedSubmission = TrackedSubmission(
        id: submissionId,
        latitude: position.latitude,
        longitude: position.longitude,
        username: username!,
        placeKind: PlaceInfo.valueOfKind(placeKind),
        name: placeName.trim().isEmpty ? null : placeName.trim(),
        isFree: isFree,
        cleanliness: cleanliness,
        condition: condition,
        hasPaper: hasPaper,
        hasSoap: hasSoap,
        wheelchairAccessible: wheelchairAccessible,
        phoneCharging: phoneCharging,
        accessType: accessType,
        comment: comment.trim().isEmpty ? null : comment.trim(),
        createdAt: DateTime.now().toUtc(),
      );
      final submissionHistory = await _submissionHistoryService.record(
        trackedSubmission,
      );

      if (!mounted) return;

      setState(() {
        _submissionHistory = submissionHistory;
        showAllCategories = false;
        showToiletPlaces = placeKind == PlaceKind.communityToilet;
        selectedCategories = showToiletPlaces ? <PlaceKind>{} : {placeKind};
      });
      await _animateMapTo(position, max(_mapZoom, 16.8));
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: LocalizedText(
            'Заявка #$submissionId отправлена. '
            'Ты уже видишь её на карте, остальные — после проверки.',
          ),
          action: SnackBarAction(
            label: context.l10n.translate('Мои заявки'),
            onPressed: () => unawaited(showSubmissionHistory()),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Ошибка добавления места: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: Colors.red.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: LocalizedText('Не удалось отправить заявку: $e'),
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
    if (toilet['submission_status'] == 'community_review') {
      unawaited(_showCommunityReviewInfo(toilet));
      return;
    }

    final latestReport = PlaceInfo.latestReport(toilet);
    final String author =
        latestReport?['username']?.toString() ??
        toilet['username']?.toString() ??
        'Неизвестный пользователь';

    final bool isFree = PlaceInfo.feeStatus(toilet) == true;
    final bool feeKnown = PlaceInfo.feeKnown(toilet);

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
    final drinkingWater = PlaceInfo.drinkingWater(toilet);
    final waterRefill = _nullableBool(
      PlaceInfo.effectiveValue(toilet, 'water_refill'),
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
          isPending: toilet['submission_status'] == 'pending',
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
          drinkingWater: drinkingWater,
          waterRefill: waterRefill,
          waterTypeLabel: PlaceInfo.waterTypeLabel(toilet),
          freshness: PlaceFreshnessResolver.resolve(toilet),
          hasActivePaperHelp: toilet['paper_help_active'] == true,
          reportCount: PlaceInfo.reportCount(toilet),
          likes: (toilet['likes'] as num?)?.toInt() ?? 0,
          dislikes: (toilet['dislikes'] as num?)?.toInt() ?? 0,
          isBuildingRoute: isBuildingRoute,
          isSubmittingReport: isSubmittingReport,
          isSubmittingLocationCorrection: isSubmittingLocationCorrection,
          isSubmittingVote: isSubmittingVote,
          isSubmittingHelp: isSubmittingHelp,
          isFavorite: _isFavorite(toilet),
          onFavorite: () => _toggleFavorite(toilet),
          onShare: () => unawaited(_copyPlaceLink(toilet)),
          onVote: (isCurrent) async {
            Navigator.of(context).pop();
            await submitVote(toilet, isCurrent: isCurrent);
          },
          onReport: () async {
            Navigator.of(context).pop();
            await showReportForm(toilet);
          },
          onMove: () async {
            Navigator.of(context).pop();
            await _beginLocationCorrection(toilet);
          },
          onPaperHelp: () async {
            Navigator.of(context).pop();
            await _requestPaperHelp(toilet);
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

  Future<void> _requestPaperHelp(Map<String, dynamic> place) async {
    if (isSubmittingHelp || place['paper_help_active'] == true) return;
    try {
      setState(() => isSubmittingHelp = true);
      await _toiletRepository.requestPaperHelp(
        place: place,
        requesterKey: await _deviceVoterKey(),
      );
      await loadToilets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(
            '🆘 Сигнал «нужна бумага» виден людям рядом в течение 45 минут',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: LocalizedText('Не удалось отправить сигнал помощи: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmittingHelp = false);
    }
  }

  Future<void> _showCommunityReviewInfo(Map<String, dynamic> submission) async {
    final submissionId = (submission['submission_id'] as num?)?.toInt();
    if (submissionId == null) return;
    final isOwnSubmission = _submissionHistory.any(
      (tracked) => tracked.id == submissionId,
    );
    final action = await showModalBottomSheet<_CommunityReviewAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CommunityReviewSheet(
        title: PlaceInfo.titleOf(submission),
        kindLabel: PlaceInfo.kindLabel(submission),
        distance: formatDistance(_distanceTo(submission)),
        confirmations: (submission['confirmation_count'] as num?)?.toInt() ?? 0,
        rejections: (submission['rejection_count'] as num?)?.toInt() ?? 0,
        isOwnSubmission: isOwnSubmission,
        onConfirm: () =>
            Navigator.of(sheetContext).pop(_CommunityReviewAction.confirm),
        onReject: () =>
            Navigator.of(sheetContext).pop(_CommunityReviewAction.reject),
        onRoute: () =>
            Navigator.of(sheetContext).pop(_CommunityReviewAction.route),
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
    if (!mounted || action == null) return;
    if (action == _CommunityReviewAction.route) {
      await buildRoute(submission);
      return;
    }
    await _reviewCommunitySubmission(
      submissionId,
      isValid: action == _CommunityReviewAction.confirm,
    );
  }

  Future<void> _reviewCommunitySubmission(
    int submissionId, {
    required bool isValid,
  }) async {
    if (isSubmittingVote) return;
    if (_submissionHistory.any((tracked) => tracked.id == submissionId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(
            'Свою заявку должен подтвердить другой человек',
          ),
        ),
      );
      return;
    }

    try {
      setState(() => isSubmittingVote = true);
      final result = await _toiletRepository.reviewSubmission(
        submissionId: submissionId,
        voterKey: await _deviceVoterKey(),
        isValid: isValid,
      );
      await loadToilets();
      if (!mounted) return;

      final status = result['status']?.toString() ?? 'pending';
      final message = switch (status) {
        'approved' => 'Спасибо! Место подтверждено и опубликовано',
        'rejected' => 'Спасибо! Ошибочная точка снята с проверки',
        _ =>
          isValid
              ? 'Спасибо! Учли подтверждение. Нужен ещё один независимый голос'
              : 'Спасибо! Учли, что точку не удалось подтвердить',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(message),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: LocalizedText('Не удалось сохранить проверку: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmittingVote = false);
    }
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
          content: LocalizedText(
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
          initialIsFree: PlaceInfo.feeStatus(place),
          canEditFee: PlaceInfo.hasToilet(place),
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
        isFree: draft.isFree,
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
          content: LocalizedText('Спасибо! Информация о месте обновлена'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: LocalizedText('Не удалось сохранить обновление: $error'),
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
      final voterKey = await _deviceVoterKey();

      await _toiletRepository.castVote(
        place: place,
        voterKey: voterKey,
        isCurrent: isCurrent,
      );
      await loadToilets();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
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
          content: LocalizedText('Не удалось сохранить оценку: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmittingVote = false);
    }
  }

  Future<String> _deviceVoterKey() async {
    final prefs = await SharedPreferences.getInstance();
    var voterKey = prefs.getString('voter_key');
    if (voterKey == null || voterKey.length < 12 || voterKey.length > 80) {
      final randomPart = Random.secure().nextInt(0x7fffffff).toRadixString(16);
      voterKey = 'device-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
      await prefs.setString('voter_key', voterKey);
    }
    return voterKey;
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
        _routePedestrianAlerts = const [];
      });

      final locationFound = await _startLocation(requestPermission: true);
      if (!locationFound) {
        if (!mounted) return;
        setState(() => isBuildingRoute = false);
        await _presentLocationHelp(
          onRetry: () => unawaited(buildRoute(toilet)),
        );
        return;
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
        _routePedestrianAlerts = PedestrianAlertPolicy.nearRoute(
          _pedestrianAlerts,
          result.points,
        );
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
          content: LocalizedText(
            '🚶 Пеший маршрут по дорожкам — ${formatDistance(result.distance)}',
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
          content: LocalizedText('❌ Не удалось построить маршрут: $e'),
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
      _routePedestrianAlerts = const [];
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
    _scheduleWeather(camera.center);
  }

  void _changeMapZoom(double delta) {
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + delta)
        .clamp(_minMapZoom, _activeMaxMapZoom)
        .toDouble();
    unawaited(_animateMapTo(camera.center, nextZoom));
  }

  void _openPlaceCluster(PlaceMarkerGroup group) {
    final zoomStep = group.places.length >= 8 ? 2.2 : 1.7;
    unawaited(
      _animateMapTo(group.center, min(_mapZoom + zoomStep, _activeMaxMapZoom)),
    );
  }

  void _handleMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) _mapAnimationGeneration++;
    if (hasGesture && _followUser) {
      _followUser = false;
    }
    _scheduleWeather(camera.center);

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final viewport = MediaQuery.sizeOf(context);
    final compactMapControls = MapDisplayPolicy.useCompactControls(
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
    );
    final mapControlGap = compactMapControls ? 8.0 : 12.0;
    final mapActionSize = compactMapControls ? 50.0 : 54.0;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ===================================================
          // КАРТА
          // ===================================================
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentPosition,
              initialZoom: _initialMapZoom,
              minZoom: _minMapZoom,
              maxZoom: _activeMaxMapZoom,
              interactionOptions: const InteractionOptions(
                scrollWheelVelocity: 0.0015,
              ),
              cameraConstraint: CameraConstraint.containCenter(
                bounds: MapDisplayPolicy.kazakhstanBounds,
              ),
              backgroundColor: theme.scaffoldBackgroundColor,
              onMapReady: _syncMapCamera,
              onPositionChanged: _handleMapPositionChanged,
              onLongPress: (_, position) {
                if (_isPickingLocation || isAddingToilet) return;
                _beginLocationPicker(position);
              },
            ),
            children: [
              _StreetMapLayer(isDark: isDark),
              if (_mapBaseStyle == MapBaseStyle.satellite)
                _SatelliteMapLayer(isDark: isDark),
              if (_mapBaseStyle == MapBaseStyle.satellite)
                TileLayer(
                  key: const ValueKey('satellite-label-tiles'),
                  urlTemplate: MapTilePolicy.satelliteLabelsUrl,
                  fallbackUrl: MapTilePolicy.satelliteLabelsFallbackUrl,
                  userAgentPackageName: 'com.tmaps.app',
                  maxNativeZoom: MapTilePolicy.satelliteLabelsMaxNativeZoom,
                  keepBuffer: MapTilePolicy.keepBuffer,
                  panBuffer: MapTilePolicy.panBuffer,
                  evictErrorTileStrategy:
                      EvictErrorTileStrategy.notVisibleRespectMargin,
                ),
              RichAttributionWidget(
                attributions: [
                  if (_mapBaseStyle == MapBaseStyle.satellite) ...[
                    LogoSourceAttribution(
                      const LocalizedText(
                        '© Esri · © OSM',
                        style: TextStyle(
                          color: Color(0xFF1F2937),
                          backgroundColor: Color(0xDDF8FAFC),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      tooltip: context.l10n.translate(
                        'Источники спутниковой карты',
                      ),
                      height: 22,
                    ),
                    const TextSourceAttribution(
                      'Imagery © Esri, Vantor, Earthstar Geographics, '
                      'GIS User Community; labels © Esri, TomTom, Garmin, '
                      'OpenStreetMap contributors',
                    ),
                  ] else ...[
                    LogoSourceAttribution(
                      const LocalizedText(
                        '© OpenStreetMap',
                        style: TextStyle(
                          color: Color(0xFF1F2937),
                          backgroundColor: Color(0xDDF8FAFC),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      tooltip: context.l10n.translate('Источник данных карты'),
                      height: 22,
                    ),
                    const TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ],
                permanentHeight: 22,
                showFlutterMapAttribution: false,
                popupInitialDisplayDuration: Duration.zero,
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
              // ПЕШЕХОДНАЯ ОБСТАНОВКА
              // =================================================
              if (!_isPickingLocation && displayedPedestrianAlerts.isNotEmpty)
                MarkerLayer(
                  markers: displayedPedestrianAlerts
                      .map(
                        (alert) => Marker(
                          key: ValueKey('pedestrian-alert:${alert.id}'),
                          point: alert.position,
                          width: 52,
                          height: 58,
                          child: _AppearingPlaceMarker(
                            child: _PedestrianAlertMarker(
                              alert: alert,
                              onTap: () => _showPedestrianAlertInfo(alert),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),

              // =================================================
              // ТУАЛЕТЫ
              // =================================================
              if (!_isPickingLocation)
                MarkerLayer(
                  markers: displayedPlaceGroups.map((group) {
                    if (group.isCluster) {
                      return Marker(
                        key: ValueKey(
                          'cluster:${group.center.latitude}:'
                          '${group.center.longitude}:${group.places.length}',
                        ),
                        point: group.center,
                        width: 62,
                        height: 62,
                        child: _AppearingPlaceMarker(
                          child: _PlaceClusterMarker(
                            count: group.places.length,
                            icon: _clusterIcon,
                            color: _clusterColor,
                            onTap: () => _openPlaceCluster(group),
                          ),
                        ),
                      );
                    }

                    final toilet = group.places.single;
                    final double lat = (toilet['lat'] as num).toDouble();

                    final double lng = (toilet['lng'] as num).toDouble();

                    final bool isFree = PlaceInfo.feeStatus(toilet) == true;
                    final bool feeKnown = PlaceInfo.feeKnown(toilet);
                    final placeKind = PlaceInfo.kindOf(toilet);
                    final placeKey = PlaceInfo.keyOf(toilet);

                    return Marker(
                      key: ValueKey(placeKey),
                      point: LatLng(lat, lng),
                      width: 58,
                      height: 68,
                      child: _AppearingPlaceMarker(
                        child: Semantics(
                          button: true,
                          label:
                              '${context.l10n.translate(PlaceInfo.kindLabel(toilet))}: '
                              '${context.l10n.translate(PlaceInfo.titleOf(toilet))}',
                          child: GestureDetector(
                            onTap: () {
                              showToiletInfo(toilet);
                            },
                            child: _PlaceMarker(
                              isFree: isFree,
                              feeKnown: feeKnown,
                              placeKind: placeKind,
                              isPending:
                                  toilet['submission_status'] == 'pending',
                              isCommunityReview:
                                  toilet['submission_status'] ==
                                  'community_review',
                              hasActiveHelp:
                                  toilet['paper_help_active'] == true,
                            ),
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

          if (!_isPickingLocation &&
              !_weatherLoadFailed &&
              _weather != null &&
              (_weather!.isRainy || _weather!.isSnowy))
            Positioned.fill(
              child: _WeatherMapAmbience(weather: _weather!, isDark: isDark),
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
                    themeMode: widget.themeMode,
                    onThemeModeChanged: widget.onThemeModeChanged,
                    language: widget.language,
                    onLanguageChanged: widget.onLanguageChanged,
                  ),
                ),
              ),
            ),

          // ===================================================
          // ПОГОДА В ТЕКУЩЕМ ГОРОДЕ
          // ===================================================
          if (!_isPickingLocation && (_weather != null || _weatherLoadFailed))
            Positioned(
              top: 0,
              left: 0,
              right: 90,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 146, 0, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _weather == null || _weatherLoadFailed
                        ? _WeatherRetryChip(
                            isRefreshing: _isLoadingWeather,
                            onTap: () => unawaited(
                              _loadWeatherFor(
                                _mapController.camera.center,
                                force: true,
                              ),
                            ),
                          )
                        : _WeatherChip(
                            weather: _weather!,
                            isRefreshing: _isLoadingWeather,
                            onTap: _showWeatherDetails,
                          ),
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
                    showAll: showAllCategories,
                    showToilets: showToiletPlaces,
                    showPedestrianAlerts: showPedestrianAlerts,
                    pedestrianAlertCount: _pedestrianAlerts.length,
                    selectedKinds: selectedCategories,
                    onShowAll: _showAllMapCategories,
                    onToggleToilets: _toggleToiletCategory,
                    onToggleKind: _toggleMapCategory,
                    onTogglePedestrianAlerts: () => setState(
                      () => showPedestrianAlerts = !showPedestrianAlerts,
                    ),
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!compactMapControls) ...[
                      _MapZoomControl(
                        onZoomIn: _mapZoom < _activeMaxMapZoom
                            ? () => _changeMapZoom(0.75)
                            : null,
                        onZoomOut: _mapZoom > _minMapZoom
                            ? () => _changeMapZoom(-0.75)
                            : null,
                      ),
                      SizedBox(height: mapControlGap),
                    ],
                    _MapDiscoveryControl(
                      onSearch: showPlaceSearch,
                      onQuickNeeds: isOpeningQuickNeeds ? null : showQuickNeeds,
                      onFavorites: showFavorites,
                      favoritesCount: _favoritePlaceKeys.length,
                    ),
                    SizedBox(height: mapControlGap),
                    _MapActionButton(
                      icon: _mapBaseStyle == MapBaseStyle.satellite
                          ? Icons.satellite_alt_rounded
                          : Icons.layers_rounded,
                      onPressed: showMapStylePicker,
                      tooltip: context.l10n.translate(
                        _mapBaseStyle == MapBaseStyle.satellite
                            ? 'Спутниковая карта'
                            : 'Слой карты',
                      ),
                      backgroundColor: _mapBaseStyle == MapBaseStyle.satellite
                          ? AppPalette.aqua
                          : scheme.surface,
                      foregroundColor: _mapBaseStyle == MapBaseStyle.satellite
                          ? Colors.white
                          : scheme.onSurface,
                      size: mapActionSize,
                    ),
                    SizedBox(height: mapControlGap),
                    _MapActionButton(
                      icon: Icons.wc_rounded,
                      onPressed: isFindingNearest ? null : showNearestToilet,
                      tooltip: context.l10n.translate('WC — ближайший туалет'),
                      backgroundColor: green.withValues(
                        alpha: isDark ? 0.26 : 0.13,
                      ),
                      foregroundColor: green,
                      size: mapActionSize,
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
                    SizedBox(height: mapControlGap),
                    _MapActionButton(
                      icon: Icons.filter_alt_rounded,
                      onPressed: showFilters,
                      tooltip: context.l10n.translate('Фильтры'),
                      backgroundColor: filtersActive
                          ? green.withValues(alpha: isDark ? 0.28 : 0.14)
                          : scheme.surface,
                      foregroundColor: filtersActive ? green : scheme.onSurface,
                      size: mapActionSize,
                      child: _CategoryFilterIcon(
                        color: filtersActive ? green : scheme.onSurface,
                        count: showAllCategories ? 0 : _selectedCategoryCount,
                        showAll: showAllCategories,
                      ),
                    ),
                    SizedBox(height: mapControlGap),
                    _MapActionButton(
                      icon: Icons.navigation_rounded,
                      onPressed: centerOnUser,
                      tooltip: context.l10n.translate('Моё местоположение'),
                      backgroundColor: _followUser
                          ? AppPalette.sky
                          : scheme.surface,
                      foregroundColor: _followUser
                          ? Colors.white
                          : scheme.onSurface,
                      size: mapActionSize,
                    ),
                    if (_submissionHistory.isNotEmpty) ...[
                      SizedBox(height: mapControlGap),
                      _MapActionButton(
                        icon: Icons.fact_check_rounded,
                        onPressed: showSubmissionHistory,
                        tooltip: context.l10n.translate('Мои заявки: {count}', {
                          'count': _submissionHistory.length,
                        }),
                        backgroundColor: const Color(
                          0xFF2563EB,
                        ).withValues(alpha: isDark ? 0.28 : 0.13),
                        foregroundColor: const Color(0xFF2563EB),
                        size: mapActionSize,
                      ),
                    ],
                    SizedBox(height: mapControlGap),
                    _MapActionButton(
                      icon: Icons.add_rounded,
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      size: compactMapControls ? 58 : 62,
                      onPressed: isAddingToilet ? null : addToilet,
                      tooltip: context.l10n.translate('Добавить место'),
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
                  alerts: _routePedestrianAlerts,
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: LocationPromptCard(
                      title: 'GPS не включён',
                      message: _locationHelpMessage,
                      onEnable: centerOnUser,
                    ),
                  ),
                ),
              ),
            ),

          if (_isPickingLocation)
            PlacePickerOverlay(
              position: _pickedPosition,
              onCancel: _cancelLocationPicker,
              onConfirm: _confirmPickedLocation,
              title: _isPickingPedestrianAlert
                  ? 'Проблема на дороге'
                  : _locationCorrectionPlace == null
                  ? 'Новая точка'
                  : 'Новое положение точки',
              confirmLabel: _isPickingPedestrianAlert
                  ? 'Отметить этот участок'
                  : _locationCorrectionPlace == null
                  ? 'Выбрать эту точку'
                  : 'Отправить на проверку',
              pinIcon: _isPickingPedestrianAlert
                  ? Icons.edit_road_rounded
                  : _locationCorrectionPlace == null
                  ? Icons.add_location_alt_rounded
                  : Icons.edit_location_alt_rounded,
            ),
        ],
      ),
    );
  }
}

class _StreetMapLayer extends StatelessWidget {
  const _StreetMapLayer({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(
        isDark
            ? const [
                -0.14,
                -0.14,
                -0.07,
                0,
                165,
                -0.10,
                -0.20,
                -0.05,
                0,
                178,
                -0.10,
                -0.13,
                -0.10,
                0,
                180,
                0,
                0,
                0,
                1,
                0,
              ]
            : const [
                0.74,
                0.17,
                0.04,
                0,
                18,
                0.08,
                0.82,
                0.05,
                0,
                20,
                0.06,
                0.17,
                0.72,
                0,
                23,
                0,
                0,
                0,
                1,
                0,
              ],
      ),
      child: TileLayer(
        key: const ValueKey('street-map-tiles'),
        urlTemplate: MapTilePolicy.streetUrl,
        userAgentPackageName: 'com.tmaps.app',
        keepBuffer: MapTilePolicy.keepBuffer,
        panBuffer: MapTilePolicy.panBuffer,
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
      ),
    );
  }
}

class _SatelliteMapLayer extends StatelessWidget {
  const _SatelliteMapLayer({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    Widget imagery = TileLayer(
      key: const ValueKey('satellite-imagery-tiles'),
      urlTemplate: MapTilePolicy.satelliteUrl,
      fallbackUrl: MapTilePolicy.satelliteFallbackUrl,
      userAgentPackageName: 'com.tmaps.app',
      maxNativeZoom: MapTilePolicy.satelliteMaxNativeZoom,
      keepBuffer: MapTilePolicy.keepBuffer,
      panBuffer: MapTilePolicy.panBuffer,
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 180),
      ),
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
    );

    if (isDark) {
      imagery = ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0x14000000),
          BlendMode.darken,
        ),
        child: imagery,
      );
    }

    return imagery;
  }
}

class _MapStyleSheet extends StatelessWidget {
  const _MapStyleSheet({required this.selectedStyle, required this.onSelected});

  final MapBaseStyle selectedStyle;
  final ValueChanged<MapBaseStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppPalette.brandGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.layers_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        'Вид карты',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      LocalizedText(
                        'Переключай слой — точки и маршрут останутся на месте',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MapStyleOptionCard(
                    title: 'Обычная',
                    subtitle: 'Улицы и дома',
                    icon: Icons.map_rounded,
                    selected: selectedStyle == MapBaseStyle.streets,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7DD3FC), Color(0xFF86EFAC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => onSelected(MapBaseStyle.streets),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MapStyleOptionCard(
                    title: 'Спутник',
                    subtitle: 'Снимки местности',
                    icon: Icons.satellite_alt_rounded,
                    selected: selectedStyle == MapBaseStyle.satellite,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF713F12)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => onSelected(MapBaseStyle.satellite),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 19,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LocalizedText(
                      'В спутниковом режиме используются снимки Esri, '
                      'а названия городов остаются поверх карты.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapStyleOptionCard extends StatelessWidget {
  const _MapStyleOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${context.l10n.translate(title)}: '
          '${context.l10n.translate(subtitle)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.60)
                : scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 84,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -14,
                      top: -18,
                      child: Icon(
                        icon,
                        size: 92,
                        color: Colors.white.withValues(alpha: 0.20),
                      ),
                    ),
                    Center(child: Icon(icon, size: 38, color: Colors.white)),
                    if (selected)
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: AppPalette.emerald,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    LocalizedText(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// ВЕРХНЯЯ ПАНЕЛЬ
// =============================================================

enum _HeaderPreferenceAction {
  themeSystem,
  themeLight,
  themeDark,
  languageSystem,
  languageRussian,
  languageKazakh,
  languageEnglish,
}

class _GlassHeader extends StatelessWidget {
  final String? username;
  final String summary;
  final VoidCallback onInstall;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  const _GlassHeader({
    required this.username,
    required this.summary,
    required this.onInstall,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.surface.withValues(alpha: 0.96),
                AppPalette.mint.withValues(alpha: 0.18),
                AppPalette.aqua.withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? scheme.outlineVariant
                  : Colors.white.withValues(alpha: 0.9),
              width: 1.4,
            ),
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
                    const LocalizedText(
                      'TMaps',
                      style: TextStyle(
                        fontSize: 21,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.22),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: LocalizedText(
                        summary,
                        key: ValueKey(summary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_HeaderPreferenceAction>(
                tooltip: context.l10n.translate('Настройки приложения'),
                onSelected: (action) {
                  switch (action) {
                    case _HeaderPreferenceAction.themeSystem:
                      onThemeModeChanged(ThemeMode.system);
                    case _HeaderPreferenceAction.themeLight:
                      onThemeModeChanged(ThemeMode.light);
                    case _HeaderPreferenceAction.themeDark:
                      onThemeModeChanged(ThemeMode.dark);
                    case _HeaderPreferenceAction.languageSystem:
                      onLanguageChanged(AppLanguage.system);
                    case _HeaderPreferenceAction.languageRussian:
                      onLanguageChanged(AppLanguage.russian);
                    case _HeaderPreferenceAction.languageKazakh:
                      onLanguageChanged(AppLanguage.kazakh);
                    case _HeaderPreferenceAction.languageEnglish:
                      onLanguageChanged(AppLanguage.english);
                  }
                },
                icon: Icon(
                  language == AppLanguage.system
                      ? switch (themeMode) {
                          ThemeMode.light => Icons.light_mode_rounded,
                          ThemeMode.dark => Icons.dark_mode_rounded,
                          ThemeMode.system => Icons.settings_rounded,
                        }
                      : Icons.language_rounded,
                  size: 21,
                ),
                itemBuilder: (context) => [
                  PopupMenuItem<_HeaderPreferenceAction>(
                    enabled: false,
                    child: LocalizedText(
                      'Оформление',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _preferenceMenuItem(
                    context,
                    value: _HeaderPreferenceAction.themeSystem,
                    icon: Icons.phone_iphone_rounded,
                    label: 'Как на телефоне',
                    selected: themeMode == ThemeMode.system,
                  ),
                  _preferenceMenuItem(
                    context,
                    value: _HeaderPreferenceAction.themeLight,
                    icon: Icons.light_mode_rounded,
                    label: 'Светлая тема',
                    selected: themeMode == ThemeMode.light,
                  ),
                  _preferenceMenuItem(
                    context,
                    value: _HeaderPreferenceAction.themeDark,
                    icon: Icons.dark_mode_rounded,
                    label: 'Тёмная тема',
                    selected: themeMode == ThemeMode.dark,
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<_HeaderPreferenceAction>(
                    enabled: false,
                    child: LocalizedText(
                      'Язык',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _preferenceMenuItem(
                    context,
                    value: _HeaderPreferenceAction.languageSystem,
                    icon: Icons.phone_iphone_rounded,
                    label: context.l10n.translate('Как в системе'),
                    selected: language == AppLanguage.system,
                  ),
                  _preferenceMenuItem(
                    context,
                    value: _HeaderPreferenceAction.languageRussian,
                    icon: Icons.language_rounded,
                    label: 'Русский',
                    selected: language == AppLanguage.russian,
                  ),
                  _preferenceMenuItem(
                    context,
                    value: _HeaderPreferenceAction.languageKazakh,
                    icon: Icons.language_rounded,
                    label: 'Қазақша',
                    selected: language == AppLanguage.kazakh,
                  ),
                  _preferenceMenuItem(
                    context,
                    value: _HeaderPreferenceAction.languageEnglish,
                    icon: Icons.language_rounded,
                    label: 'English',
                    selected: language == AppLanguage.english,
                  ),
                ],
              ),
              IconButton.filledTonal(
                onPressed: onInstall,
                tooltip: context.l10n.translate('Установить TMaps'),
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
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.82,
                    ),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: scheme.outlineVariant),
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
                        child: LocalizedText(
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

  PopupMenuItem<_HeaderPreferenceAction> _preferenceMenuItem(
    BuildContext context, {
    required _HeaderPreferenceAction value,
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem<_HeaderPreferenceAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: LocalizedText(label)),
          if (selected) ...[
            const SizedBox(width: 10),
            Icon(
              Icons.check_rounded,
              size: 19,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

class _MapLegendBar extends StatefulWidget {
  final bool showAll;
  final bool showToilets;
  final bool showPedestrianAlerts;
  final int pedestrianAlertCount;
  final Set<PlaceKind> selectedKinds;
  final VoidCallback onShowAll;
  final VoidCallback onToggleToilets;
  final ValueChanged<PlaceKind> onToggleKind;
  final VoidCallback onTogglePedestrianAlerts;

  const _MapLegendBar({
    required this.showAll,
    required this.showToilets,
    required this.showPedestrianAlerts,
    required this.pedestrianAlertCount,
    required this.selectedKinds,
    required this.onShowAll,
    required this.onToggleToilets,
    required this.onToggleKind,
    required this.onTogglePedestrianAlerts,
  });

  @override
  State<_MapLegendBar> createState() => _MapLegendBarState();
}

class _MapLegendBarState extends State<_MapLegendBar> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void didUpdateWidget(covariant _MapLegendBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollButtons)
      ..dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canScrollBack = position.pixels > 2;
    final canScrollForward = position.pixels < position.maxScrollExtent - 2;
    if (_canScrollBack == canScrollBack &&
        _canScrollForward == canScrollForward) {
      return;
    }
    setState(() {
      _canScrollBack = canScrollBack;
      _canScrollForward = canScrollForward;
    });
  }

  Future<void> _scrollBy(double delta) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    await _scrollController.animateTo(
      (position.pixels + delta).clamp(0, position.maxScrollExtent).toDouble(),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: 0.13),
        color: scheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Row(
                  children: [
                    _LegendItem(
                      color: AppPalette.aqua,
                      icon: Icons.layers_rounded,
                      label: 'Все места',
                      selected: widget.showAll,
                      onTap: widget.onShowAll,
                    ),
                    _LegendItem(
                      color: Color(0xFF16A34A),
                      icon: Icons.wc_rounded,
                      label: 'Туалеты',
                      selected: !widget.showAll && widget.showToilets,
                      onTap: widget.onToggleToilets,
                    ),
                    ...PlaceKind.values.map(
                      (kind) => _LegendItem(
                        color: kind.color,
                        icon: kind.icon,
                        label: kind.shortLabel,
                        selected:
                            !widget.showAll &&
                            widget.selectedKinds.contains(kind),
                        onTap: () => widget.onToggleKind(kind),
                      ),
                    ),
                    _LegendItem(
                      color: const Color(0xFFF97316),
                      icon: Icons.edit_road_rounded,
                      label: widget.pedestrianAlertCount > 0
                          ? 'Дороги · ${widget.pedestrianAlertCount}'
                          : 'Дороги',
                      selected: widget.showPedestrianAlerts,
                      onTap: widget.onTogglePedestrianAlerts,
                    ),
                  ],
                ),
              ),
              if (_canScrollBack)
                _LegendScrollButton(
                  icon: Icons.chevron_left_rounded,
                  alignment: Alignment.centerLeft,
                  tooltip: context.l10n.translate('Предыдущие категории'),
                  onPressed: () => _scrollBy(-190),
                ),
              if (_canScrollForward)
                _LegendScrollButton(
                  icon: Icons.chevron_right_rounded,
                  alignment: Alignment.centerRight,
                  tooltip: context.l10n.translate('Ещё категории'),
                  onPressed: () => _scrollBy(190),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendScrollButton extends StatelessWidget {
  const _LegendScrollButton({
    required this.icon,
    required this.alignment,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Alignment alignment;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;
    final surface = Theme.of(context).colorScheme.surface;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 42,
        alignment: alignment,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [surface, surface.withValues(alpha: 0.72)],
          ),
        ),
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, color: AppPalette.emerald, size: 24),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.translate('Категория {label}: {state}', {
        'label': context.l10n.translate(label),
        'state': context.l10n.translate(selected ? 'включена' : 'выключена'),
      }),
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: AnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(icon, color: color, size: 17),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : onSurface,
                ),
                child: LocalizedText(label),
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
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: AnimatedScale(
        scale: selected ? 1.12 : 1,
        duration: const Duration(milliseconds: 180),
        child: Icon(
          icon,
          size: 18,
          color: selected ? color : scheme.onSurfaceVariant,
        ),
      ),
      label: LocalizedText(label),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: selected ? color : scheme.onSurface,
      ),
      selectedColor: color.withValues(alpha: 0.13),
      side: BorderSide(
        color: selected ? color.withValues(alpha: 0.35) : scheme.outlineVariant,
      ),
      showCheckmark: false,
    );
  }
}

// =============================================================
// МАРКЕР ТУАЛЕТА
// =============================================================

class _AppearingPlaceMarker extends StatelessWidget {
  const _AppearingPlaceMarker({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, animatedChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 7 * (1 - value)),
            child: Transform.scale(
              scale: 0.78 + value * 0.22,
              alignment: Alignment.bottomCenter,
              child: animatedChild,
            ),
          ),
        );
      },
    );
  }
}

class _PlaceClusterMarker extends StatelessWidget {
  const _PlaceClusterMarker({
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.translate(
        '{count} мест рядом. Нажмите, чтобы приблизить',
        {'count': count},
      ),
      child: Tooltip(
        message: context.l10n.translate('{count} мест рядом — приблизить', {
          'count': count,
        }),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Colors.black, 0.18)!],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 17),
                LocalizedText(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
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

class _PlaceMarker extends StatelessWidget {
  final bool isFree;
  final bool feeKnown;
  final PlaceKind placeKind;
  final bool isPending;
  final bool isCommunityReview;
  final bool hasActiveHelp;

  const _PlaceMarker({
    required this.isFree,
    required this.feeKnown,
    required this.placeKind,
    this.isPending = false,
    this.isCommunityReview = false,
    this.hasActiveHelp = false,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon) = isPending
        ? (const Color(0xFFF59E0B), Icons.hourglass_top_rounded)
        : isCommunityReview
        ? (const Color(0xFF64748B), Icons.fact_check_outlined)
        : switch (placeKind) {
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
            PlaceKind.water => (
              const Color(0xFF0284C7),
              Icons.water_drop_rounded,
            ),
            PlaceKind.cafe => (
              const Color(0xFFEA580C),
              Icons.restaurant_rounded,
            ),
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
            if (isPending ||
                isCommunityReview ||
                placeKind == PlaceKind.communityToilet)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isPending || isCommunityReview
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFDB2777),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    isPending ? Icons.schedule_rounded : Icons.groups_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            if (hasActiveHelp)
              Positioned(
                left: -5,
                bottom: -4,
                child: Container(
                  width: 23,
                  height: 23,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const LocalizedText(
                    '!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
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

class _MapDiscoveryControl extends StatelessWidget {
  const _MapDiscoveryControl({
    required this.onSearch,
    required this.onQuickNeeds,
    required this.onFavorites,
    required this.favoritesCount,
  });

  final VoidCallback onSearch;
  final VoidCallback? onQuickNeeds;
  final VoidCallback onFavorites;
  final int favoritesCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget divider() =>
        Container(width: 1, height: 27, color: scheme.outlineVariant);
    final buttons = <Widget>[
      _ZoomButton(
        icon: Icons.search_rounded,
        tooltip: context.l10n.translate('Поиск места'),
        onPressed: onSearch,
        foregroundColor: AppPalette.aqua,
      ),
      divider(),
      _ZoomButton(
        icon: Icons.bolt_rounded,
        tooltip: context.l10n.translate(
          'Нужно сейчас: туалет, вода или зарядка',
        ),
        onPressed: onQuickNeeds,
        foregroundColor: const Color(0xFFF59E0B),
      ),
      divider(),
      _ZoomButton(
        icon: favoritesCount > 0
            ? Icons.bookmark_rounded
            : Icons.bookmark_border_rounded,
        tooltip: context.l10n.translate('Избранное: {count}', {
          'count': favoritesCount,
        }),
        onPressed: onFavorites,
        foregroundColor: favoritesCount > 0
            ? AppPalette.pink
            : AppPalette.muted,
        badgeCount: favoritesCount,
      ),
    ];
    return Material(
      elevation: 9,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      color: scheme.surface.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }
}

class _MapZoomControl extends StatelessWidget {
  const _MapZoomControl({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 9,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      color: scheme.surface.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.add_rounded,
            tooltip: context.l10n.translate('Приблизить карту'),
            onPressed: onZoomIn,
          ),
          Container(width: 27, height: 1, color: scheme.outlineVariant),
          _ZoomButton(
            icon: Icons.remove_rounded,
            tooltip: context.l10n.translate('Отдалить карту'),
            onPressed: onZoomOut,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.foregroundColor,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? foregroundColor;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final resolvedForeground =
        foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 23,
                color: onPressed == null
                    ? AppPalette.muted
                    : resolvedForeground,
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.pink,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: LocalizedText(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
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

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double size;
  final Widget? child;

  const _MapActionButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.size = 54,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Material(
      elevation: 9,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      color: backgroundColor ?? scheme.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child:
                child ??
                Icon(
                  icon,
                  size: 25,
                  color: foregroundColor ?? scheme.onSurface,
                ),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _CategoryFilterIcon extends StatelessWidget {
  const _CategoryFilterIcon({
    required this.color,
    required this.count,
    required this.showAll,
  });

  final Color color;
  final int count;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            showAll ? Icons.layers_rounded : Icons.filter_alt_rounded,
            key: ValueKey(showAll),
            size: 25,
            color: color,
          ),
        ),
        if (!showAll && count > 1)
          Positioned(
            top: -13,
            right: -15,
            child: AnimatedScale(
              scale: count > 1 ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: AppPalette.pink,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: LocalizedText(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
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
      color: Theme.of(context).colorScheme.surface,
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: LocalizedText(
                '$count • $label',
                key: ValueKey('$count-$label'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
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

class _WeatherMapAmbience extends StatefulWidget {
  const _WeatherMapAmbience({required this.weather, required this.isDark});

  final WeatherSnapshot weather;
  final bool isDark;

  @override
  State<_WeatherMapAmbience> createState() => _WeatherMapAmbienceState();
}

class _WeatherMapAmbienceState extends State<_WeatherMapAmbience>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.weather.isSnowy ? 5200 : 1700),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _WeatherMapAmbience oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weather.isSnowy != widget.weather.isSnowy) {
      _controller.duration = Duration(
        milliseconds: widget.weather.isSnowy ? 5200 : 1700,
      );
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.weather.isSnowy
        ? const Color(0xFFDCEEFF)
        : const Color(0xFF4DA8D8);
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tint.withValues(alpha: widget.isDark ? 0.10 : 0.055),
                      tint.withValues(alpha: widget.isDark ? 0.045 : 0.025),
                    ],
                  ),
                ),
              ),
              CustomPaint(
                painter: widget.weather.isSnowy
                    ? _SnowAmbiencePainter(
                        progress: _controller.value,
                        isDark: widget.isDark,
                      )
                    : _RainAmbiencePainter(
                        progress: _controller.value,
                        isDark: widget.isDark,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RainAmbiencePainter extends CustomPainter {
  const _RainAmbiencePainter({required this.progress, required this.isDark});

  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? const Color(0xFFBDEAFF) : const Color(0xFF1976A8))
          .withValues(alpha: isDark ? 0.34 : 0.24)
      ..strokeWidth = isDark ? 1.35 : 1.15
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < 64; index++) {
      final xSeed = ((index * 47) % 101) / 101;
      final ySeed = ((index * 71) % 97) / 97;
      final speed = 0.78 + (index % 7) * 0.065;
      final y = (ySeed + progress * speed) % 1.12 - 0.06;
      final x = (xSeed + progress * 0.035 + sin(index * 1.7) * 0.012) % 1;
      final start = Offset(x * size.width, y * size.height);
      final length = 9.0 + (index % 6) * 1.35;
      canvas.drawLine(start, start + Offset(-3.5, length), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RainAmbiencePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}

class _SnowAmbiencePainter extends CustomPainter {
  const _SnowAmbiencePainter({required this.progress, required this.isDark});

  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFFB6DDF7)).withValues(
        alpha: isDark ? 0.56 : 0.48,
      );

    for (var index = 0; index < 46; index++) {
      final xSeed = ((index * 43) % 103) / 103;
      final ySeed = ((index * 67) % 101) / 101;
      final speed = 0.22 + (index % 6) * 0.035;
      final y = (ySeed + progress * speed) % 1.08 - 0.04;
      final drift =
          sin(progress * pi * 2 + index * 0.83) * (5.0 + (index % 4) * 1.5);
      final center = Offset(xSeed * size.width + drift, y * size.height);
      canvas.drawCircle(center, 1.35 + (index % 5) * 0.34, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowAmbiencePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}

class _WeatherRetryChip extends StatelessWidget {
  const _WeatherRetryChip({required this.isRefreshing, required this.onTap});

  final bool isRefreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: isRefreshing ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRefreshing)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                const Icon(Icons.cloud_off_rounded, size: 20),
              const SizedBox(width: 8),
              LocalizedText(
                isRefreshing ? 'Обновляю погоду…' : 'Погода · повторить',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  const _WeatherChip({
    required this.weather,
    required this.isRefreshing,
    required this.onTap,
  });

  final WeatherSnapshot weather;
  final bool isRefreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.9 : 0.94),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: weather.color.withValues(alpha: isDark ? 0.24 : 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isRefreshing
                    ? Padding(
                        padding: const EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: weather.color,
                        ),
                      )
                    : Icon(weather.icon, color: weather.color, size: 21),
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LocalizedText(
                    '${weather.temperature.round()}° · '
                    '${context.l10n.translate(weather.condition)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  LocalizedText(
                    weather.cityName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
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

class _WeatherDetailsSheet extends StatelessWidget {
  const _WeatherDetailsSheet({
    required this.weather,
    required this.isRefreshing,
    required this.hasError,
    required this.onRefresh,
  });

  final WeatherSnapshot weather;
  final bool isRefreshing;
  final bool hasError;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: weather.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(weather.icon, color: weather.color, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        weather.cityName,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      LocalizedText(
                        '${weather.temperature.round()}° · '
                        '${context.l10n.translate(weather.condition)}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.translate('Обновить погоду'),
                  onPressed: isRefreshing ? null : onRefresh,
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (hasError) ...[
              const SizedBox(height: 14),
              LocalizedText(
                'Погода временно недоступна',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (!hasError && weather.hasPedestrianWeatherWarning) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: weather.color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: weather.color.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.directions_walk_rounded,
                      color: weather.color,
                      size: 21,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: LocalizedText(
                        weather.pedestrianAdvice!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _WeatherMetric(
                  icon: Icons.thermostat_rounded,
                  label: 'Ощущается',
                  value: '${weather.apparentTemperature.round()}°',
                ),
                _WeatherMetric(
                  icon: Icons.unfold_more_rounded,
                  label: 'Мин / макс',
                  value:
                      '${weather.minimumTemperature.round()}° / ${weather.maximumTemperature.round()}°',
                ),
                _WeatherMetric(
                  icon: Icons.water_drop_rounded,
                  label: 'Вероятность осадков',
                  value: '${weather.precipitationProbability}%',
                ),
                _WeatherMetric(
                  icon: Icons.air_rounded,
                  label: 'Ветер',
                  value: '${weather.windSpeed.round()} км/ч',
                ),
              ],
            ),
            const SizedBox(height: 14),
            LocalizedText(
              'Погода по центру карты · данные Open-Meteo',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 158,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                LocalizedText(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
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

class _PedestrianAlertMarker extends StatelessWidget {
  const _PedestrianAlertMarker({required this.alert, required this.onTap});

  final PedestrianAlert alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${context.l10n.translate(alert.type.label)}: '
          '${context.l10n.translate(alert.type.description)}',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 35,
              child: Transform.rotate(
                angle: 0.785,
                child: Container(
                  width: 15,
                  height: 15,
                  color: alert.type.color,
                ),
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: alert.type.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(alert.type.icon, color: Colors.white, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _PedestrianAlertFormSheet extends StatefulWidget {
  const _PedestrianAlertFormSheet({required this.position});

  final LatLng position;

  @override
  State<_PedestrianAlertFormSheet> createState() =>
      _PedestrianAlertFormSheetState();
}

class _PedestrianAlertFormSheetState extends State<_PedestrianAlertFormSheet> {
  final TextEditingController _descriptionController = TextEditingController();
  PedestrianAlertType _selectedType = PedestrianAlertType.ice;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 4, 18, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalizedText(
              'Пешеходная обстановка',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 5),
            LocalizedText(
              'Выбери, что происходит на этом участке. Данные временные и обновляются людьми рядом.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PedestrianAlertType.values
                  .map(
                    (type) => ChoiceChip(
                      selected: _selectedType == type,
                      selectedColor: type.color.withValues(alpha: 0.16),
                      side: BorderSide(
                        color: _selectedType == type
                            ? type.color
                            : scheme.outlineVariant,
                      ),
                      avatar: Icon(type.icon, size: 18, color: type.color),
                      label: LocalizedText(type.label),
                      onSelected: (_) => setState(() => _selectedType = type),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  _selectedType.color.withValues(alpha: 0.09),
                  scheme.surface,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(_selectedType.icon, color: _selectedType.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LocalizedText(
                      _selectedType.description,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              maxLength: 240,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.translate(
                  'Комментарий — необязательно',
                ),
                hintText: context.l10n.translate(
                  'Например: тропинка у моста полностью во льду',
                ),
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.pin_drop_outlined,
                  size: 17,
                  color: AppPalette.muted,
                ),
                const SizedBox(width: 6),
                LocalizedText(
                  '${widget.position.latitude.toStringAsFixed(5)}, '
                  '${widget.position.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    color: AppPalette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _selectedType.color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  final description = _descriptionController.text.trim();
                  Navigator.of(context).pop(
                    PedestrianAlertDraft(
                      type: _selectedType,
                      description: description.isEmpty ? null : description,
                    ),
                  );
                },
                icon: const Icon(Icons.campaign_rounded),
                label: const LocalizedText('Опубликовать предупреждение'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PedestrianAlertInfoSheet extends StatelessWidget {
  const _PedestrianAlertInfoSheet({required this.alert});

  final PedestrianAlert alert;

  String _expiresLabel() {
    final local = alert.expiresAt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'до ${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')} сегодня';
    }
    return 'до ${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: alert.type.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(alert.type.icon, color: Colors.white, size: 27),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        alert.type.label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      LocalizedText(
                        _expiresLabel(),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LocalizedText(
              alert.description ?? alert.type.description,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 12),
            LocalizedText(
              'Сообщил: ${alert.username}. Проверяй обстановку на месте — она может быстро измениться.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePanel extends StatelessWidget {
  final String distance;
  final String duration;
  final List<PedestrianAlert> alerts;
  final VoidCallback onClose;

  const _RoutePanel({
    required this.distance,
    required this.duration,
    required this.alerts,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                    Icons.directions_walk_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        distance,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      LocalizedText(
                        'Пешком · $duration',
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
            if (alerts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFEA580C),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LocalizedText(
                        alerts.length == 1
                            ? '${alerts.first.type.label} рядом с маршрутом'
                            : '${alerts.length} предупреждения рядом с маршрутом',
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                          fontSize: 12,
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
    );
  }
}

class _QuickNeedsSheet extends StatelessWidget {
  const _QuickNeedsSheet({
    required this.results,
    required this.distanceLabel,
    required this.onSelected,
  });

  final List<QuickNeedResult> results;
  final String Function(double distanceMeters) distanceLabel;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        'Нужно сейчас',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      LocalizedText(
                        'Самые близкие полезные места',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (results.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: LocalizedText(
                  'Рядом пока нет подтверждённых мест. Можно приблизить карту или добавить новую точку.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              )
            else
              ...results.map(
                (result) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _QuickNeedCard(
                    result: result,
                    distance: distanceLabel(result.distanceMeters),
                    onTap: () => onSelected(result.place),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LocalizedText(
                    'Показываем опубликованные точки. Для воды — только места, отмеченные как питьевые.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNeedCard extends StatelessWidget {
  const _QuickNeedCard({
    required this.result,
    required this.distance,
    required this.onTap,
  });

  final QuickNeedResult result;
  final String distance;
  final VoidCallback onTap;

  Color get _color => switch (result.kind) {
    QuickNeedKind.toilet => const Color(0xFF16A34A),
    QuickNeedKind.drinkingWater => const Color(0xFF0284C7),
    QuickNeedKind.phoneCharging => const Color(0xFF4F46E5),
  };

  IconData get _icon => switch (result.kind) {
    QuickNeedKind.toilet => Icons.wc_rounded,
    QuickNeedKind.drinkingWater => Icons.water_drop_rounded,
    QuickNeedKind.phoneCharging => Icons.battery_charging_full_rounded,
  };

  String get _title => switch (result.kind) {
    QuickNeedKind.toilet => 'Ближайший туалет',
    QuickNeedKind.drinkingWater => 'Питьевая вода',
    QuickNeedKind.phoneCharging => 'Зарядить телефон',
  };

  String get _detail => switch (result.kind) {
    QuickNeedKind.toilet =>
      PlaceInfo.feeKnown(result.place)
          ? (PlaceInfo.feeStatus(result.place) == true ? 'Бесплатно' : 'Платно')
          : 'Стоимость уточняется',
    QuickNeedKind.drinkingWater => PlaceInfo.waterTypeLabel(result.place),
    QuickNeedKind.phoneCharging => PlaceInfo.accessLabel(result.place),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final freshness = PlaceFreshnessResolver.resolve(result.place);

    return Material(
      color: Color.alphaBlend(_color.withValues(alpha: 0.08), scheme.surface),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _color.withValues(alpha: 0.24),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(_icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      _title,
                      style: TextStyle(
                        color: _color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    LocalizedText(
                      PlaceInfo.titleOf(result.place),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LocalizedText(
                      '$_detail · $distance · ${freshness.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: _color, size: 27),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// CARD / BOTTOM SHEET ТУАЛЕТА
// =============================================================

enum _CommunityReviewAction { confirm, reject, route }

class _CommunityReviewSheet extends StatelessWidget {
  const _CommunityReviewSheet({
    required this.title,
    required this.kindLabel,
    required this.distance,
    required this.confirmations,
    required this.rejections,
    required this.isOwnSubmission,
    required this.onConfirm,
    required this.onReject,
    required this.onRoute,
    required this.onClose,
  });

  final String title;
  final String kindLabel;
  final String distance;
  final int confirmations;
  final int rejections;
  final bool isOwnSubmission;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final VoidCallback onRoute;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const reviewColor = Color(0xFF475569);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
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
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: reviewColor.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: reviewColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LocalizedText(
                          '$kindLabel · $distance',
                          style: const TextStyle(
                            color: AppPalette.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.22),
                  ),
                ),
                child: const LocalizedText(
                  'Администратор не ответил за 24 часа. Заявка стала нейтральной: люди рядом могут проверить, существует ли это место. Для публикации нужны независимые подтверждения.',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ReviewCountTile(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Подтвердили',
                      count: confirmations,
                      color: const Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReviewCountTile(
                      icon: Icons.help_outline_rounded,
                      label: 'Не нашли',
                      count: rejections,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              if (isOwnSubmission) ...[
                const SizedBox(height: 14),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFFD97706)),
                    SizedBox(width: 9),
                    Expanded(
                      child: LocalizedText(
                        'Это твоя заявка. Чтобы проверка была честной, подтвердить её должен другой человек со своего телефона.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isOwnSubmission ? null : onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                      ),
                      icon: const Icon(Icons.check_rounded),
                      label: const LocalizedText('Место есть'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isOwnSubmission ? null : onReject,
                      icon: const Icon(Icons.close_rounded),
                      label: const LocalizedText('Не нашёл'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRoute,
                  icon: const Icon(Icons.directions_rounded),
                  label: const LocalizedText('Построить маршрут для проверки'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCountTile extends StatelessWidget {
  const _ReviewCountTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: LocalizedText(
              '$label: $count',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToiletInfoSheet extends StatelessWidget {
  final String title;
  final String kindLabel;
  final PlaceKind placeKind;
  final bool isPending;
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
  final bool? drinkingWater;
  final bool? waterRefill;
  final String waterTypeLabel;
  final PlaceFreshness freshness;
  final bool hasActivePaperHelp;
  final int reportCount;
  final int likes;
  final int dislikes;
  final bool isBuildingRoute;
  final bool isSubmittingReport;
  final bool isSubmittingLocationCorrection;
  final bool isSubmittingVote;
  final bool isSubmittingHelp;
  final bool isFavorite;
  final Future<bool> Function() onFavorite;
  final VoidCallback onShare;
  final ValueChanged<bool> onVote;
  final VoidCallback onReport;
  final VoidCallback onMove;
  final VoidCallback onPaperHelp;
  final VoidCallback onRoute;
  final VoidCallback onClose;

  const _ToiletInfoSheet({
    required this.title,
    required this.kindLabel,
    required this.placeKind,
    required this.isPending,
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
    required this.drinkingWater,
    required this.waterRefill,
    required this.waterTypeLabel,
    required this.freshness,
    required this.hasActivePaperHelp,
    required this.reportCount,
    required this.likes,
    required this.dislikes,
    required this.isBuildingRoute,
    required this.isSubmittingReport,
    required this.isSubmittingLocationCorrection,
    required this.isSubmittingVote,
    required this.isSubmittingHelp,
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
    required this.onVote,
    required this.onReport,
    required this.onMove,
    required this.onPaperHelp,
    required this.onRoute,
    required this.onClose,
  });

  IconData get placeIcon {
    return switch (placeKind) {
      PlaceKind.communityToilet || PlaceKind.publicToilet => Icons.wc_rounded,
      PlaceKind.phoneCharging => Icons.battery_charging_full_rounded,
      PlaceKind.evCharging => Icons.ev_station_rounded,
      PlaceKind.water => Icons.water_drop_rounded,
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

  bool get isWater => placeKind == PlaceKind.water;

  Color get waterSafetyColor => switch (drinkingWater) {
    true => const Color(0xFF16A34A),
    false => const Color(0xFFDC2626),
    null => const Color(0xFFD97706),
  };

  String get waterSafetyLabel => switch (drinkingWater) {
    true => 'Подтверждено',
    false => 'Не для питья',
    null => 'Не проверено',
  };

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

  Color get freshnessColor => switch (freshness.level) {
    PlaceFreshnessLevel.recent => const Color(0xFF16A34A),
    PlaceFreshnessLevel.aging => const Color(0xFFD97706),
    PlaceFreshnessLevel.stale => const Color(0xFFDC2626),
    PlaceFreshnessLevel.unknown => Colors.blueGrey.shade600,
  };

  IconData get freshnessIcon => switch (freshness.level) {
    PlaceFreshnessLevel.recent => Icons.verified_rounded,
    PlaceFreshnessLevel.aging => Icons.schedule_rounded,
    PlaceFreshnessLevel.stale => Icons.update_disabled_rounded,
    PlaceFreshnessLevel.unknown => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                          LocalizedText(
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
                          LocalizedText(
                            kindLabel,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _FavoriteButton(
                      initialValue: isFavorite,
                      onToggle: onFavorite,
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: context.l10n.translate(
                        'Скопировать ссылку на место',
                      ),
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                if (isPending) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          color: Color(0xFFD97706),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: LocalizedText(
                            'Заявка отправлена. Пока точку видишь только ты на этом устройстве; после одобрения она появится у всех.',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Информация
                if (isWater) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCard(
                          icon: Icons.water_drop_rounded,
                          iconColor: placeColor,
                          title: 'Тип точки',
                          value: waterTypeLabel,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InfoCard(
                          icon: drinkingWater == true
                              ? Icons.verified_rounded
                              : Icons.warning_amber_rounded,
                          iconColor: waterSafetyColor,
                          title: 'Для питья',
                          value: waterSafetyLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
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
                          title: 'Стоимость воды',
                          value: !feeKnown
                              ? 'Не указано'
                              : isFree
                              ? 'Бесплатно'
                              : 'Платно',
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
                ] else ...[
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
                ],

                const SizedBox(height: 10),

                _InfoCard(
                  icon: Icons.door_front_door_rounded,
                  iconColor: placeColor,
                  title: 'Доступ',
                  value: accessLabel,
                ),

                if (isWater && drinkingWater != true) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: waterSafetyColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: waterSafetyColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_rounded, color: waterSafetyColor),
                        const SizedBox(width: 9),
                        Expanded(
                          child: LocalizedText(
                            drinkingWater == false
                                ? 'Эта вода отмечена как непитьевая.'
                                : 'Без подтверждения не пей воду прямо из источника.',
                            style: TextStyle(
                              color: waterSafetyColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                _InfoCard(
                  icon: Icons.near_me_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Расстояние по прямой',
                  value: distance,
                ),

                const SizedBox(height: 10),

                _InfoCard(
                  icon: freshnessIcon,
                  iconColor: freshnessColor,
                  title: freshness.label,
                  value: freshness.detail,
                ),

                const SizedBox(height: 18),

                const LocalizedText(
                  'Что есть на месте',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isWater)
                      _AmenityStatusChip(
                        icon: Icons.local_drink_rounded,
                        label: 'Можно пить',
                        value: drinkingWater,
                      ),
                    if (isWater)
                      _AmenityStatusChip(
                        icon: Icons.water_drop_outlined,
                        label: 'Набрать в тару',
                        value: waterRefill,
                      ),
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
                    if (!isWater)
                      _AmenityStatusChip(
                        icon: Icons.bolt_rounded,
                        label: 'Зарядка телефона',
                        value: phoneCharging,
                      ),
                  ],
                ),

                if (!isPending &&
                    hasToilet &&
                    (hasPaper == false || hasActivePaperHelp)) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText(
                          hasActivePaperHelp
                              ? '🆘 Сейчас здесь нужна бумага'
                              : 'Нет бумаги? Попроси помощи рядом',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        LocalizedText(
                          hasActivePaperHelp
                              ? 'Сигнал уже виден на карте и сам исчезнет через 45 минут.'
                              : 'TMaps отметит туалет красным значком на 45 минут. Не используй эту кнопку для экстренных ситуаций.',
                          style: const TextStyle(
                            color: AppPalette.muted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: hasActivePaperHelp || isSubmittingHelp
                                ? null
                                : onPaperHelp,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                            ),
                            icon: const Icon(Icons.sos_rounded),
                            label: LocalizedText(
                              hasActivePaperHelp
                                  ? 'Сигнал помощи активен'
                                  : '🆘 Нужна бумага',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
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
                            LocalizedText(
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
                        LocalizedText(
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

                if (!isPending) ...[
                  const SizedBox(height: 20),

                  const LocalizedText(
                    'Точка актуальна?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: isSubmittingVote
                              ? null
                              : () => onVote(true),
                          icon: const Icon(Icons.thumb_up_alt_rounded),
                          label: LocalizedText('Да · $likes'),
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
                          label: LocalizedText('Нет на месте · $dislikes'),
                          style: FilledButton.styleFrom(
                            foregroundColor: const Color(0xFFB45309),
                            backgroundColor: const Color(0xFFFFF7ED),
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (!isWater) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isSubmittingReport ? null : onReport,
                        icon: const Icon(Icons.rate_review_outlined),
                        label: LocalizedText(
                          reportCount == 0
                              ? 'Обновить информацию или оставить отзыв'
                              : 'Отзывы и обновления: $reportCount · Добавить',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isSubmittingLocationCorrection ? null : onMove,
                      icon: const Icon(Icons.edit_location_alt_rounded),
                      label: const LocalizedText(
                        'Исправить положение на карте',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

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
                        : const Icon(Icons.directions_walk_rounded),
                    label: LocalizedText(
                      isBuildingRoute
                          ? 'Строим маршрут...'
                          : 'Пешком по дорожкам',
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

class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.initialValue, required this.onToggle});

  final bool initialValue;
  final Future<bool> Function() onToggle;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  late bool _isFavorite = widget.initialValue;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: context.l10n.translate(
        _isFavorite ? 'Убрать из избранного' : 'Сохранить место',
      ),
      style: IconButton.styleFrom(
        backgroundColor: _isFavorite
            ? AppPalette.pink.withValues(alpha: 0.13)
            : scheme.surfaceContainerHighest,
        foregroundColor: _isFavorite ? AppPalette.pink : AppPalette.muted,
      ),
      onPressed: _isSaving
          ? null
          : () async {
              setState(() => _isSaving = true);
              final savedValue = await widget.onToggle();
              if (!mounted) return;
              setState(() {
                _isFavorite = savedValue;
                _isSaving = false;
              });
            },
      icon: _isSaving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                _isFavorite
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                key: ValueKey(_isFavorite),
              ),
            ),
    );
  }
}

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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
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
                LocalizedText(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                LocalizedText(
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
          LocalizedText(
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
                LocalizedText(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                LocalizedText(
                  text,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
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
  final bool? isFree;
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
    required this.isFree,
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
  final bool? initialIsFree;
  final bool canEditFee;
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
    required this.initialIsFree,
    required this.canEditFee,
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
  late bool? isFree;
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
    isFree = widget.initialIsFree;
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
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: LocalizedText(issue),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _PlaceReportDraft(
        cleanliness: cleanliness,
        condition: condition,
        isFree: isFree,
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const LocalizedText(
                  'Обновить информацию',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                LocalizedText(
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
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('Состояние'),
                    prefixIcon: const Icon(Icons.health_and_safety_outlined),
                  ),
                  items: conditions
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: LocalizedText(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => condition = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accessType,
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('Кому можно зайти'),
                    prefixIcon: const Icon(Icons.door_front_door_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'public',
                      child: LocalizedText('Всем'),
                    ),
                    DropdownMenuItem(
                      value: 'customers',
                      child: LocalizedText('Только клиентам'),
                    ),
                    DropdownMenuItem(
                      value: 'permissive',
                      child: LocalizedText('Обычно пускают'),
                    ),
                    DropdownMenuItem(
                      value: 'destination',
                      child: LocalizedText('Только посетителям'),
                    ),
                    DropdownMenuItem(
                      value: 'unknown',
                      child: LocalizedText('Не знаю'),
                    ),
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
                if (widget.canEditFee || hasToilet == true) ...[
                  DropdownButtonFormField<String>(
                    initialValue: isFree == null
                        ? 'unknown'
                        : isFree!
                        ? 'free'
                        : 'paid',
                    decoration: InputDecoration(
                      labelText: context.l10n.translate('Стоимость туалета'),
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'free',
                        child: LocalizedText('Бесплатный'),
                      ),
                      DropdownMenuItem(
                        value: 'paid',
                        child: LocalizedText('Платный'),
                      ),
                      DropdownMenuItem(
                        value: 'unknown',
                        child: LocalizedText('Не знаю'),
                      ),
                    ],
                    onChanged: (selection) {
                      setState(() {
                        isFree = switch (selection) {
                          'free' => true,
                          'paid' => false,
                          _ => null,
                        };
                      });
                    },
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
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('Отзыв или уточнение'),
                    hintText: context.l10n.translate(
                      'Например: бумага есть, вход со двора',
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
                LocalizedText(
                  'Обновление будет видно всем пользователям TMaps.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: submit,
                    icon: const Icon(Icons.check_rounded),
                    label: const LocalizedText('Опубликовать обновление'),
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
      key: ValueKey('$label-${value ?? 'unknown'}'),
      initialValue: value == null
          ? 'unknown'
          : value!
          ? 'yes'
          : 'no',
      decoration: InputDecoration(
        labelText: context.l10n.translate(label),
        prefixIcon: Icon(icon),
      ),
      items: const [
        DropdownMenuItem(value: 'yes', child: LocalizedText('Есть')),
        DropdownMenuItem(value: 'no', child: LocalizedText('Нет')),
        DropdownMenuItem(value: 'unknown', child: LocalizedText('Не знаю')),
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

class _SubmissionHistorySheet extends StatelessWidget {
  const _SubmissionHistorySheet({
    required this.submissions,
    required this.onSelect,
  });

  final List<TrackedSubmission> submissions;
  final ValueChanged<TrackedSubmission> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.fact_check_rounded,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText(
                          'Мои заявки',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        LocalizedText(
                          'Точки, отправленные с этого устройства',
                          style: TextStyle(color: AppPalette.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFFD97706)),
                    SizedBox(width: 10),
                    Expanded(
                      child: LocalizedText(
                        'Сначала заявку видишь только ты. Через 24 часа без ответа она станет нейтральной и появится у людей рядом для проверки.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (submissions.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 30,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.add_location_alt_outlined,
                        size: 38,
                        color: AppPalette.muted,
                      ),
                      SizedBox(height: 10),
                      LocalizedText(
                        'Пока заявок нет',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      LocalizedText(
                        'Нажми зелёный плюс, выбери точку и отправь её на проверку.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppPalette.muted),
                      ),
                    ],
                  ),
                )
              else
                ...submissions.map((submission) {
                  final date = submission.createdAt.toLocal();
                  final place = <String, dynamic>{
                    'place_kind': submission.placeKind,
                  };
                  final categoryTitle =
                      submission.name?.trim().isNotEmpty == true
                      ? submission.name!
                      : switch (PlaceInfo.kindOf(place)) {
                          PlaceKind.cafe => 'Новое кафе',
                          PlaceKind.fuel => 'Новая АЗС',
                          PlaceKind.organization => 'Новая организация',
                          PlaceKind.phoneCharging => 'Зарядка телефона',
                          PlaceKind.evCharging => 'Электрозарядка',
                          PlaceKind.water => 'Точка питьевой воды',
                          _ => 'Новый туалет',
                        };
                  final (
                    statusLabel,
                    statusIcon,
                    statusColor,
                  ) = switch (submission.status) {
                    'approved' => (
                      'Одобрено и опубликовано',
                      Icons.verified_rounded,
                      const Color(0xFF15803D),
                    ),
                    'rejected' => (
                      'Нужно уточнение',
                      Icons.info_outline_rounded,
                      const Color(0xFFDC2626),
                    ),
                    'community_review' => (
                      'Нужна проверка людьми рядом',
                      Icons.groups_rounded,
                      const Color(0xFF2563EB),
                    ),
                    _ => (
                      'Ожидает проверки',
                      Icons.hourglass_top_rounded,
                      const Color(0xFFD97706),
                    ),
                  };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelect(submission),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(statusIcon, color: statusColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LocalizedText(
                                      '$categoryTitle #${submission.id}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    LocalizedText(
                                      '$statusLabel · '
                                      '${date.day.toString().padLeft(2, '0')}.'
                                      '${date.month.toString().padLeft(2, '0')}.'
                                      '${date.year}',
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    LocalizedText(
                                      '${submission.latitude.toStringAsFixed(5)}, '
                                      '${submission.longitude.toStringAsFixed(5)}',
                                      style: const TextStyle(
                                        color: AppPalette.muted,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppPalette.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// ФОРМА ДОБАВЛЕНИЯ
// =============================================================

class _AddPlaceSheet extends StatelessWidget {
  final LatLng position;
  final PlaceKind placeKind;
  final bool categoryChosen;
  final String placeName;
  final bool outdoorToilet;
  final bool isFree;
  final int cleanliness;
  final String condition;
  final bool? hasPaper;
  final bool? hasSoap;
  final bool? wheelchairAccessible;
  final bool? phoneCharging;
  final String accessType;
  final String comment;

  final ValueChanged<PlaceKind> onPlaceKindChanged;
  final ValueChanged<String> onPlaceNameChanged;
  final ValueChanged<bool> onOutdoorToiletChanged;
  final ValueChanged<bool> onFreeChanged;
  final ValueChanged<int> onCleanlinessChanged;
  final ValueChanged<String> onConditionChanged;
  final ValueChanged<bool?> onPaperChanged;
  final ValueChanged<bool?> onSoapChanged;
  final ValueChanged<bool?> onWheelchairChanged;
  final ValueChanged<bool?> onPhoneChargingChanged;
  final ValueChanged<String> onAccessTypeChanged;
  final ValueChanged<String> onCommentChanged;

  final VoidCallback onCancel;
  final VoidCallback onAdd;

  const _AddPlaceSheet({
    required this.position,
    required this.placeKind,
    required this.categoryChosen,
    required this.placeName,
    required this.outdoorToilet,
    required this.isFree,
    required this.cleanliness,
    required this.condition,
    required this.hasPaper,
    required this.hasSoap,
    required this.wheelchairAccessible,
    required this.phoneCharging,
    required this.accessType,
    required this.comment,
    required this.onPlaceKindChanged,
    required this.onPlaceNameChanged,
    required this.onOutdoorToiletChanged,
    required this.onFreeChanged,
    required this.onCleanlinessChanged,
    required this.onConditionChanged,
    required this.onPaperChanged,
    required this.onSoapChanged,
    required this.onWheelchairChanged,
    required this.onPhoneChargingChanged,
    required this.onAccessTypeChanged,
    required this.onCommentChanged,
    required this.onCancel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToilet = categoryChosen && placeKind == PlaceKind.communityToilet;
    final (placeIcon, placeColor, placeTitle) = !categoryChosen
        ? (
            Icons.category_rounded,
            const Color(0xFF475569),
            'Сначала выбери категорию',
          )
        : switch (placeKind) {
            PlaceKind.cafe => (
              Icons.restaurant_rounded,
              const Color(0xFFEA580C),
              'Кафе или ресторан',
            ),
            PlaceKind.fuel => (
              Icons.local_gas_station_rounded,
              const Color(0xFF7C3AED),
              'Автозаправка',
            ),
            PlaceKind.organization => (
              Icons.apartment_rounded,
              const Color(0xFF0F766E),
              'Организация',
            ),
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
            PlaceKind.water => (
              Icons.water_drop_rounded,
              const Color(0xFF0284C7),
              'Питьевая вода',
            ),
            _ => (Icons.wc_rounded, const Color(0xFF15803D), 'Туалет'),
          };

    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                        LocalizedText(
                          'Отправить место',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        LocalizedText(
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

              if (!categoryChosen) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.touch_app_rounded, color: Color(0xFFEA580C)),
                      SizedBox(width: 10),
                      Expanded(
                        child: LocalizedText(
                          'Нажми, что именно ты добавляешь. Так кафе не попадёт в туалеты.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterCategoryChip(
                    label: 'Туалет',
                    icon: Icons.wc_rounded,
                    color: const Color(0xFF15803D),
                    selected:
                        categoryChosen &&
                        placeKind == PlaceKind.communityToilet,
                    onSelected: () =>
                        onPlaceKindChanged(PlaceKind.communityToilet),
                  ),
                  _FilterCategoryChip(
                    label: 'Кафе',
                    icon: Icons.restaurant_rounded,
                    color: const Color(0xFFEA580C),
                    selected: categoryChosen && placeKind == PlaceKind.cafe,
                    onSelected: () => onPlaceKindChanged(PlaceKind.cafe),
                  ),
                  _FilterCategoryChip(
                    label: 'Организация',
                    icon: Icons.apartment_rounded,
                    color: const Color(0xFF0F766E),
                    selected:
                        categoryChosen && placeKind == PlaceKind.organization,
                    onSelected: () =>
                        onPlaceKindChanged(PlaceKind.organization),
                  ),
                  _FilterCategoryChip(
                    label: 'АЗС',
                    icon: Icons.local_gas_station_rounded,
                    color: const Color(0xFF7C3AED),
                    selected: categoryChosen && placeKind == PlaceKind.fuel,
                    onSelected: () => onPlaceKindChanged(PlaceKind.fuel),
                  ),
                  _FilterCategoryChip(
                    label: 'Вода',
                    icon: Icons.water_drop_rounded,
                    color: const Color(0xFF0284C7),
                    selected: categoryChosen && placeKind == PlaceKind.water,
                    onSelected: () => onPlaceKindChanged(PlaceKind.water),
                  ),
                  _FilterCategoryChip(
                    label: 'Телефон',
                    icon: Icons.battery_charging_full_rounded,
                    color: const Color(0xFF2563EB),
                    selected:
                        categoryChosen && placeKind == PlaceKind.phoneCharging,
                    onSelected: () =>
                        onPlaceKindChanged(PlaceKind.phoneCharging),
                  ),
                  _FilterCategoryChip(
                    label: 'Электро',
                    icon: Icons.ev_station_rounded,
                    color: const Color(0xFF0891B2),
                    selected:
                        categoryChosen && placeKind == PlaceKind.evCharging,
                    onSelected: () => onPlaceKindChanged(PlaceKind.evCharging),
                  ),
                ],
              ),

              if (categoryChosen) ...[
                if (!isToilet) ...[
                  const SizedBox(height: 18),
                  TextFormField(
                    initialValue: placeName,
                    onChanged: onPlaceNameChanged,
                    decoration: InputDecoration(
                      labelText: context.l10n.translate(
                        placeKind == PlaceKind.water
                            ? 'Название или тип точки'
                            : 'Название места',
                      ),
                      hintText: context.l10n.translate(
                        placeKind == PlaceKind.cafe
                            ? 'Например: Кофейня у парка'
                            : placeKind == PlaceKind.organization
                            ? 'Например: Библиотека'
                            : 'Как называется это место?',
                      ),
                      prefixIcon: Icon(placeIcon),
                    ),
                  ),
                ],

                if (isToilet) ...[
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.park_outlined,
                    title: 'Тип туалета',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ChoiceButton(
                            selected: !outdoorToilet,
                            icon: Icons.wc_rounded,
                            text: 'Обычный',
                            color: const Color(0xFF15803D),
                            onTap: () => onOutdoorToiletChanged(false),
                          ),
                        ),
                        Expanded(
                          child: _ChoiceButton(
                            selected: outdoorToilet,
                            icon: Icons.park_rounded,
                            text: 'Уличный / парковый',
                            color: const Color(0xFFD97706),
                            onTap: () => onOutdoorToiletChanged(true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (outdoorToilet) ...[
                    const SizedBox(height: 9),
                    const LocalizedText(
                      'Шаблон поставит 3 звезды, плохое состояние, отсутствие бумаги и мыла. Всё можно изменить ниже.',
                      style: TextStyle(
                        color: AppPalette.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 24),

                // Стоимость
                if (isToilet) ...[
                  const _SectionTitle(
                    icon: Icons.payments_outlined,
                    title: 'Стоимость',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
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
                ],

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
                        child: LocalizedText(
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
                  key: ValueKey('condition-$condition'),
                  initialValue: condition,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.cleaning_services_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Хорошее',
                      child: LocalizedText('🟢  Хорошее'),
                    ),
                    DropdownMenuItem(
                      value: 'Среднее',
                      child: LocalizedText('🟡  Среднее'),
                    ),
                    DropdownMenuItem(
                      value: 'Плохое',
                      child: LocalizedText('🔴  Плохое'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onConditionChanged(value);
                    }
                  },
                ),

                const SizedBox(height: 22),

                const _SectionTitle(
                  icon: Icons.door_front_door_outlined,
                  title: 'Доступ',
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('access-$accessType'),
                  initialValue: accessType,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.meeting_room_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'public',
                      child: LocalizedText('Для всех'),
                    ),
                    DropdownMenuItem(
                      value: 'customers',
                      child: LocalizedText('Только клиентам'),
                    ),
                    DropdownMenuItem(
                      value: 'permissive',
                      child: LocalizedText('Обычно пускают'),
                    ),
                    DropdownMenuItem(
                      value: 'destination',
                      child: LocalizedText('Только посетителям'),
                    ),
                    DropdownMenuItem(
                      value: 'unknown',
                      child: LocalizedText('Не знаю'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onAccessTypeChanged(value);
                  },
                ),

                if (isToilet) ...[
                  const SizedBox(height: 22),
                  const _SectionTitle(
                    icon: Icons.checklist_rounded,
                    title: 'Что есть внутри',
                  ),
                  const SizedBox(height: 10),
                  _TriStateField(
                    label: 'Туалетная бумага',
                    icon: Icons.receipt_long_outlined,
                    value: hasPaper,
                    onChanged: onPaperChanged,
                  ),
                  const SizedBox(height: 10),
                  _TriStateField(
                    label: 'Мыло',
                    icon: Icons.soap_outlined,
                    value: hasSoap,
                    onChanged: onSoapChanged,
                  ),
                  const SizedBox(height: 10),
                  _TriStateField(
                    label: 'Доступ для коляски',
                    icon: Icons.accessible_outlined,
                    value: wheelchairAccessible,
                    onChanged: onWheelchairChanged,
                  ),
                ] else if (placeKind != PlaceKind.phoneCharging) ...[
                  const SizedBox(height: 14),
                  _TriStateField(
                    label: 'Можно зарядить телефон',
                    icon: Icons.bolt_outlined,
                    value: phoneCharging,
                    onChanged: onPhoneChargingChanged,
                  ),
                ],

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
                    hintText: context.l10n.translate(
                      isToilet
                          ? 'Например: находится внутри ТЦ'
                          : 'Например: розетка у стойки, работает круглосуточно',
                    ),
                    alignLabelWithHint: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 55),
                      child: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                ),
              ],

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
                      child: const LocalizedText('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: categoryChosen ? onAdd : null,
                      icon: const Icon(Icons.send_rounded),
                      label: const LocalizedText('Отправить на проверку'),
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
        LocalizedText(
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
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
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
              color: selected ? color : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: LocalizedText(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
