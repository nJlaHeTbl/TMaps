import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const TMapsApp());
}

class TMapsApp extends StatelessWidget {
  const TMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TMaps',
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
  final MapController _mapController = MapController();

  LatLng _currentPosition = const LatLng(45.0156, 78.3731);

  Future<void> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition();

    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });

    _mapController.move(_currentPosition, 16);
  }

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  final List<LatLng> toilets = const [
    LatLng(45.02061927734114, 78.40205998100085),
    LatLng(45.027421506503714, 78.39149158031506),
    LatLng(45.02743056417113, 78.39146797621179),
    LatLng(45.022541818055785, 78.39949128481774),
    LatLng(45.01680365476963, 78.38120726556873),
    LatLng(45.004216400888026, 78.34705805210724),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("TMaps"),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentPosition,
          initialZoom: 15,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.tmaps.app',
          ),

          // Маркеры туалетов
          MarkerLayer(
            markers: toilets
                .map(
                  (toilet) => Marker(
                    point: toilet,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.wc,
                      color: Colors.green,
                      size: 35,
                    ),
                  ),
                )
                .toList(),
          ),

          // Текущее местоположение
          MarkerLayer(
            markers: [
              Marker(
                point: _currentPosition,
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}