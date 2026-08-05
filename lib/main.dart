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
      title: 'TMaps KZ',
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

  final List<LatLng> toilets = [
    const LatLng(45.02061927734114, 78.40205998100085),
    const LatLng(45.027421506503714, 78.39149158031506),
    const LatLng(45.02743056417113, 78.39146797621179),
    const LatLng(45.022541818055785, 78.39949128481774),
    const LatLng(45.01680365476963, 78.38120726556873),
    const LatLng(45.004216400888026, 78.34705805210724),
  ];

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

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

  void _addToilet(LatLng point) {
    setState(() {
      toilets.add(point);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🚻 Туалет добавлен!"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("TMaps"),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _getLocation,
        child: const Icon(Icons.my_location),
      ),

      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentPosition,
          initialZoom: 15,

          onLongPress: (tapPosition, point) {
            _addToilet(point);
          },
        ),

        children: [
          TileLayer(
            urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.tmaps.app',
          ),

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

          MarkerLayer(
            markers: [
              Marker(
                point: _currentPosition,
                width: 45,
                height: 45,
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