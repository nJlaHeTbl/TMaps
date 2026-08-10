import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fbvvaozvgledhiidvplw.supabase.co',
    anonKey: 'sb_publishable_DdevGM-RfKW0wdmFezhFhw_23oVq39Y',
  );

  runApp(const TMapsApp());
}

class TMapsApp extends StatelessWidget {
  const TMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    const darkGreen = Color(0xFF15803D);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TMaps',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F8FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: green.withOpacity(0.5),
              width: 1.5,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: green,
          foregroundColor: Colors.white,
        ),
      ),
      
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
  static const Color darkGreen = Color(0xFF15803D);
  static const Color blue = Color(0xFF2563EB);

  final MapController _mapController = MapController();

  LatLng currentPosition = const LatLng(
    45.0156,
    78.3731,
  );

  final List<Map<String, dynamic>> toilets = [];

  String? username;

  bool isAddingToilet = false;
  bool isBuildingRoute = false;

  List<LatLng> routePoints = [];

  double? routeDistance;
  double? routeDuration;

  @override
  void initState() {
    super.initState();

    loadUsername();
    getLocation();
    loadToilets();
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
                    color: green.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wc_rounded,
                    color: green,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Добро пожаловать в TMaps',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Как тебя называть?',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 15,
                  ),
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

                      if (name.isEmpty) return;

                      final prefs =
                          await SharedPreferences.getInstance();

                      await prefs.setString('username', name);

                      if (!mounted) return;

                      setState(() {
                        username = name;
                      });

                      Navigator.of(context).pop();
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

  Future<void> getLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      if (permission == LocationPermission.denied) {
        return;
      }

      final Position position =
          await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final newPosition = LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      setState(() {
        currentPosition = newPosition;
      });

      _mapController.move(
        currentPosition,
        16,
      );
    } catch (e) {
      debugPrint('Ошибка GPS: $e');
    }
  }

  Future<void> centerOnUser() async {
    await getLocation();

    if (!mounted) return;

    _mapController.move(
      currentPosition,
      17,
    );
  }

  // =========================================================
  // ЗАГРУЗКА ТУАЛЕТОВ
  // =========================================================

  Future<void> loadToilets() async {
    try {
      final response = await Supabase.instance.client
          .from('toilets')
          .select();

      if (!mounted) return;

      setState(() {
        toilets.clear();

        for (final toilet in response) {
          toilets.add(
            Map<String, dynamic>.from(toilet),
          );
        }
      });

      debugPrint(
        'Загружено туалетов: ${toilets.length}',
      );
    } catch (e) {
      debugPrint(
        'Ошибка загрузки туалетов: $e',
      );
    }
  }

  // =========================================================
  // ДОБАВЛЕНИЕ ТУАЛЕТА
  // =========================================================

  Future<void> addToilet() async {
    if (isAddingToilet) {
      return;
    }

    if (username == null || username!.trim().isEmpty) {
      await showUsernameDialog();

      if (username == null || username!.trim().isEmpty) {
        return;
      }
    }

    try {
      setState(() {
        isAddingToilet = true;
      });

      await getLocation();

      if (!mounted) return;

      bool isFree = true;
      int cleanliness = 5;
      String condition = 'Хорошее';
      String comment = '';

      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (
              context,
              setDialogState,
            ) {
              return _AddToiletSheet(
                isFree: isFree,
                cleanliness: cleanliness,
                condition: condition,
                comment: comment,
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
                  Navigator.of(context).pop(true);
                },
              );
            },
          );
        },
      );

      if (result != true) {
        if (!mounted) return;

        setState(() {
          isAddingToilet = false;
        });

        return;
      }

      final insertedToilet = await Supabase.instance.client
          .from('toilets')
          .insert({
            'lat': currentPosition.latitude,
            'lng': currentPosition.longitude,
            'username': username,
            'is_free': isFree,
            'cleanliness': cleanliness,
            'condition': condition,
            'comment': comment.trim().isEmpty
                ? null
                : comment.trim(),
          })
          .select()
          .single();

      if (!mounted) return;

      setState(() {
        toilets.add(
          Map<String, dynamic>.from(insertedToilet),
        );

        isAddingToilet = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            '🚻 Туалет добавлен от имени $username',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Ошибка добавления туалета: $e',
      );

      if (!mounted) return;

      setState(() {
        isAddingToilet = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: Colors.red.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            '❌ Ошибка: $e',
          ),
        ),
      );
    }
  }

  // =========================================================
  // КАРТОЧКА ТУАЛЕТА
  // =========================================================

  void showToiletInfo(
    Map<String, dynamic> toilet,
  ) {
    final String author =
        toilet['username']?.toString() ??
            'Неизвестный пользователь';

    final bool isFree =
        toilet['is_free'] == true;

    final int cleanliness =
        (toilet['cleanliness'] as num?)?.toInt() ?? 5;

    final String condition =
        toilet['condition']?.toString() ??
            'Хорошее';

    final String comment =
        toilet['comment']?.toString() ??
            '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ToiletInfoSheet(
          author: author,
          isFree: isFree,
          cleanliness: cleanliness,
          condition: condition,
          comment: comment,
          isBuildingRoute: isBuildingRoute,
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

  // =========================================================
  // ПОСТРОЕНИЕ МАРШРУТА
  // =========================================================

  Future<void> buildRoute(
    Map<String, dynamic> toilet,
  ) async {
    try {
      setState(() {
        isBuildingRoute = true;
        routePoints = [];
        routeDistance = null;
        routeDuration = null;
      });

      await getLocation();

      final double toiletLat =
          (toilet['lat'] as num).toDouble();

      final double toiletLng =
          (toilet['lng'] as num).toDouble();

      final String url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${currentPosition.longitude},'
          '${currentPosition.latitude};'
          '$toiletLng,$toiletLat'
          '?overview=full&geometries=geojson';

      debugPrint('Маршрут: $url');

      final response = await http.get(
        Uri.parse(url),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Ошибка маршрутизатора: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data['code'] != 'Ok') {
        throw Exception('Маршрут не найден');
      }

      final routes = data['routes'] as List;

      if (routes.isEmpty) {
        throw Exception('Маршрут не найден');
      }

      final route = routes.first;

      final geometry = route['geometry'];

      final coordinates =
          geometry['coordinates'] as List;

      final List<LatLng> points = [];

      for (final coordinate in coordinates) {
        final double lng =
            (coordinate[0] as num).toDouble();

        final double lat =
            (coordinate[1] as num).toDouble();

        points.add(
          LatLng(
            lat,
            lng,
          ),
        );
      }

      final double distance =
          (route['distance'] as num).toDouble();

      final double duration =
          (route['duration'] as num).toDouble();

      if (!mounted) return;

      setState(() {
        routePoints = points;
        routeDistance = distance;
        routeDuration = duration;
        isBuildingRoute = false;
      });

      if (routePoints.isNotEmpty) {
        final bounds =
            LatLngBounds.fromPoints(routePoints);

        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(80),
          ),
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
            '🧭 Маршрут построен — '
            '${formatDistance(distance)}',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Ошибка маршрута: $e',
      );

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
          content: Text(
            '❌ Не удалось построить маршрут: $e',
          ),
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
    final int minutes =
        (seconds / 60).round();

    if (minutes < 60) {
      return '$minutes мин';
    }

    final int hours = minutes ~/ 60;

    final int remainingMinutes =
        minutes % 60;

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
              minZoom: 4,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.tmaps.app',
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
                    Polyline(
                      points: routePoints,
                      strokeWidth: 5,
                      color: green,
                    ),
                  ],
                ),

              // =================================================
              // ТУАЛЕТЫ
              // =================================================

              MarkerLayer(
                markers: toilets.map(
                  (toilet) {
                    final double lat =
                        (toilet['lat'] as num).toDouble();

                    final double lng =
                        (toilet['lng'] as num).toDouble();

                    final bool isFree =
                        toilet['is_free'] == true;

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 58,
                      height: 68,
                      child: GestureDetector(
                        onTap: () {
                          showToiletInfo(toilet);
                        },
                        child: _ToiletMarker(
                          isFree: isFree,
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),

              // =================================================
              // ТЕКУЩЕЕ МЕСТОПОЛОЖЕНИЕ
              // =================================================

              MarkerLayer(
                markers: [
                  Marker(
                    point: currentPosition,
                    width: 44,
                    height: 44,
                    child: const _UserLocationMarker(),
                  ),
                ],
              ),
            ],
          ),

          // ===================================================
          // ВЕРХНЯЯ ПАНЕЛЬ
          // ===================================================

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  14,
                  10,
                  14,
                  0,
                ),
                child: _GlassHeader(
                  username: username,
                  toiletCount: toilets.length,
                ),
              ),
            ),
          ),

          // ===================================================
          // КНОПКИ СПРАВА
          // ===================================================

          Positioned(
            right: 16,
            bottom:
                routePoints.length >= 2 ? 150 : 28,
            child: SafeArea(
              child: Column(
                children: [
                  _MapActionButton(
                    icon: Icons.my_location_rounded,
                    onPressed: centerOnUser,
                    tooltip: 'Моё местоположение',
                  ),
                  const SizedBox(height: 12),
                  _MapActionButton(
                    icon: Icons.add_rounded,
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    size: 62,
                    onPressed:
                        isAddingToilet ? null : addToilet,
                    child: isAddingToilet
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child:
                                CircularProgressIndicator(
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

          if (toilets.isNotEmpty)
            Positioned(
              left: 16,
              bottom:
                  routePoints.length >= 2 ? 150 : 28,
              child: SafeArea(
                child: _MapCounter(
                  count: toilets.length,
                ),
              ),
            ),

          // ===================================================
          // ПАНЕЛЬ МАРШРУТА
          // ===================================================

          if (routePoints.length >= 2 &&
              routeDistance != null &&
              routeDuration != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: _RoutePanel(
                  distance:
                      formatDistance(routeDistance!),
                  duration:
                      formatDuration(routeDuration!),
                  onClose: clearRoute,
                ),
              ),
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
  final int toiletCount;

  const _GlassHeader({
    required this.username,
    required this.toiletCount,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      shadowColor: Colors.black.withOpacity(0.15),
      color: Colors.white.withOpacity(0.96),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF22C55E),
                    Color(0xFF15803D),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A)
                        .withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.wc_rounded,
                color: Colors.white,
                size: 29,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TMaps',
                    style: TextStyle(
                      fontSize: 21,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$toiletCount '
                    '${toiletCount == 1 ? 'туалет' : 'туалетов'} '
                    'на карте',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (username != null)
              Container(
                constraints: const BoxConstraints(
                  maxWidth: 125,
                ),
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F3),
                  borderRadius:
                      BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person_rounded,
                      size: 17,
                      color: Color(0xFF15803D),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        username!,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
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

// =============================================================
// МАРКЕР ТУАЛЕТА
// =============================================================

class _ToiletMarker extends StatelessWidget {
  final bool isFree;

  const _ToiletMarker({
    required this.isFree,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isFree ? const Color(0xFF16A34A) : Colors.orange.shade700;

    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.wc_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -5),
          child: CustomPaint(
            size: const Size(12, 8),
            painter: _MarkerTrianglePainter(
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MarkerTrianglePainter
    extends CustomPainter {
  final Color color;

  const _MarkerTrianglePainter({
    required this.color,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = color;

    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(
        size.width,
        size.height,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(
    covariant _MarkerTrianglePainter oldDelegate,
  ) {
    return oldDelegate.color != color;
  }
}

// =============================================================
// МАРКЕР ПОЛЬЗОВАТЕЛЯ
// =============================================================

class _UserLocationMarker
    extends StatelessWidget {
  const _UserLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB)
            .withOpacity(0.16),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 5,
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2563EB),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// =============================================================
// КНОПКА КАРТЫ
// =============================================================

class _MapActionButton
    extends StatelessWidget {
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
    return Material(
      elevation: 9,
      shadowColor:
          Colors.black.withOpacity(0.22),
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: child ??
                Icon(
                  icon,
                  size: 25,
                  color: foregroundColor,
                ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// СЧЕТЧИК
// =============================================================

class _MapCounter extends StatelessWidget {
  final int count;

  const _MapCounter({
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 10,
        ),
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
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
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

class _RoutePanel
    extends StatelessWidget {
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
        padding: const EdgeInsets.fromLTRB(
          14,
          12,
          8,
          12,
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF22C55E),
                    Color(0xFF15803D),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(16),
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
                crossAxisAlignment:
                    CrossAxisAlignment.start,
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
                backgroundColor:
                    const Color(0xFFF3F4F6),
              ),
              icon: const Icon(
                Icons.close_rounded,
              ),
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

class _ToiletInfoSheet
    extends StatelessWidget {
  final String author;
  final bool isFree;
  final int cleanliness;
  final String condition;
  final String comment;
  final bool isBuildingRoute;
  final VoidCallback onRoute;
  final VoidCallback onClose;

  const _ToiletInfoSheet({
    required this.author,
    required this.isFree,
    required this.cleanliness,
    required this.condition,
    required this.comment,
    required this.isBuildingRoute,
    required this.onRoute,
    required this.onClose,
  });

  Color get conditionColor {
    if (condition == 'Хорошее') {
      return const Color(0xFF16A34A);
    }

    if (condition == 'Среднее') {
      return Colors.orange.shade700;
    }

    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius:
                          BorderRadius.circular(10),
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
                        gradient:
                            const LinearGradient(
                          colors: [
                            Color(0xFFDCFCE7),
                            Color(0xFFBBF7D0),
                          ],
                          begin:
                              Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius:
                            BorderRadius.circular(19),
                      ),
                      child: const Icon(
                        Icons.wc_rounded,
                        color: Color(0xFF15803D),
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Туалет',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight:
                                  FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Общественное место',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
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
                        iconColor: Colors.amber.shade700,
                        title: 'Чистота',
                        value:
                            '$cleanliness / 5',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoCard(
                        icon: isFree
                            ? Icons
                                .check_circle_rounded
                            : Icons
                                .payments_rounded,
                        iconColor: isFree
                            ? const Color(
                                0xFF16A34A,
                              )
                            : Colors.orange.shade700,
                        title: 'Стоимость',
                        value: isFree
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
                        icon:
                            Icons.health_and_safety_rounded,
                        iconColor:
                            conditionColor,
                        title: 'Состояние',
                        value: condition,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoCard(
                        icon:
                            Icons.person_rounded,
                        iconColor:
                            const Color(0xFF2563EB),
                        title: 'Добавил',
                        value: author,
                      ),
                    ),
                  ],
                ),

                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFF7F8FA),
                      borderRadius:
                          BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons
                                  .chat_bubble_outline_rounded,
                              size: 19,
                              color: Colors
                                  .grey.shade700,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Комментарий',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.w800,
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
                            color: Colors
                                .grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        isBuildingRoute
                            ? null
                            : onRoute,
                    icon: isBuildingRoute
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons
                                .directions_rounded,
                          ),
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
              color: iconColor.withOpacity(0.12),
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        Colors.grey.shade600,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w800,
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

// =============================================================
// ФОРМА ДОБАВЛЕНИЯ
// =============================================================

class _AddToiletSheet
    extends StatelessWidget {
  final bool isFree;
  final int cleanliness;
  final String condition;
  final String comment;

  final ValueChanged<bool> onFreeChanged;
  final ValueChanged<int> onCleanlinessChanged;
  final ValueChanged<String> onConditionChanged;
  final ValueChanged<String> onCommentChanged;

  final VoidCallback onCancel;
  final VoidCallback onAdd;

  const _AddToiletSheet({
    required this.isFree,
    required this.cleanliness,
    required this.condition,
    required this.comment,
    required this.onFreeChanged,
    required this.onCleanlinessChanged,
    required this.onConditionChanged,
    required this.onCommentChanged,
    required this.onCancel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints:
            const BoxConstraints(
          maxHeight: 700,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius:
                        BorderRadius.circular(10),
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
                      color: const Color(
                        0xFFDCFCE7,
                      ),
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.add_location_alt_rounded,
                      color: Color(0xFF15803D),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Добавить туалет',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Помоги другим найти его',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  color:
                      const Color(0xFFF7F8FA),
                  borderRadius:
                      BorderRadius.circular(16),
                ),
                padding:
                    const EdgeInsets.all(5),
                child: Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        selected: isFree,
                        icon: Icons
                            .check_circle_outline_rounded,
                        text: 'Бесплатный',
                        color:
                            const Color(0xFF16A34A),
                        onTap: () =>
                            onFreeChanged(true),
                      ),
                    ),
                    Expanded(
                      child: _ChoiceButton(
                        selected: !isFree,
                        icon: Icons
                            .payments_outlined,
                        text: 'Платный',
                        color:
                            Colors.orange.shade700,
                        onTap: () =>
                            onFreeChanged(false),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Чистота
              const _SectionTitle(
                icon: Icons.star_outline_rounded,
                title: 'Чистота',
              ),

              const SizedBox(height: 8),

              Row(
                children: List.generate(
                  5,
                  (index) {
                    final star = index + 1;

                    return GestureDetector(
                      onTap: () =>
                          onCleanlinessChanged(
                        star,
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.only(
                          right: 7,
                        ),
                        child: Icon(
                          star <= cleanliness
                              ? Icons
                                  .star_rounded
                              : Icons
                                  .star_border_rounded,
                          color:
                              Colors.amber.shade600,
                          size: 37,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 22),

              // Состояние
              const _SectionTitle(
                icon: Icons
                    .health_and_safety_outlined,
                title: 'Состояние',
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                value: condition,
                decoration:
                    const InputDecoration(
                  prefixIcon: Icon(
                    Icons
                        .cleaning_services_outlined,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Хорошее',
                    child:
                        Text('🟢  Хорошее'),
                  ),
                  DropdownMenuItem(
                    value: 'Среднее',
                    child:
                        Text('🟡  Среднее'),
                  ),
                  DropdownMenuItem(
                    value: 'Плохое',
                    child:
                        Text('🔴  Плохое'),
                  ),
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
                icon: Icons
                    .chat_bubble_outline_rounded,
                title: 'Комментарий',
              ),

              const SizedBox(height: 10),

              TextField(
                maxLines: 3,
                maxLength: 300,
                onChanged: onCommentChanged,
                decoration:
                    const InputDecoration(
                  hintText:
                      'Например: находится внутри ТЦ',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding:
                        EdgeInsets.only(
                      bottom: 55,
                    ),
                    child: Icon(
                      Icons
                          .edit_note_rounded,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style:
                          OutlinedButton.styleFrom(
                        minimumSize:
                            const Size(
                          0,
                          52,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            16,
                          ),
                        ),
                      ),
                      child:
                          const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(
                        Icons
                            .add_location_alt_rounded,
                      ),
                      label:
                          const Text('Добавить'),
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

class _SectionTitle
    extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: const Color(0xFF15803D),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// =============================================================
// КНОПКА ВЫБОРА
// =============================================================

class _ChoiceButton
    extends StatelessWidget {
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
        duration:
            const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(
          vertical: 13,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(13),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(0.07),
                    blurRadius: 8,
                    offset:
                        const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected
                  ? color
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? Colors.black87
                      : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}