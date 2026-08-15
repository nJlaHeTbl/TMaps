import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/app_config.dart';

class RouteResult {
  const RouteResult({
    required this.points,
    required this.distance,
    required this.duration,
  });

  final List<LatLng> points;
  final double distance;
  final double duration;
}

class RouteService {
  const RouteService();

  Future<RouteResult> build({required LatLng from, required LatLng to}) async {
    final uri = Uri.parse(
      '${AppConfig.routingBaseUrl}/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Ошибка маршрутизатора: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') {
      throw Exception('Маршрут не найден');
    }

    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) {
      throw Exception('Маршрут не найден');
    }

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final points = coordinates.map((coordinate) {
      final pair = coordinate as List<dynamic>;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();

    return RouteResult(
      points: points,
      distance: (route['distance'] as num).toDouble(),
      duration: (route['duration'] as num).toDouble(),
    );
  }
}
