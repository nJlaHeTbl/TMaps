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
  const RouteService({this.client});

  final http.Client? client;

  Future<RouteResult> build({required LatLng from, required LatLng to}) async {
    if (!_validCoordinate(from.latitude, from.longitude) ||
        !_validCoordinate(to.latitude, to.longitude)) {
      throw const FormatException('Invalid route endpoints');
    }
    final uri = Uri.parse(
      '${AppConfig.routingBaseUrl}/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );

    final response = await (client?.get(uri) ?? http.get(uri)).timeout(
      const Duration(seconds: 18),
    );
    if (response.statusCode != 200) {
      throw Exception('Ошибка маршрутизатора: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid route response');
    }
    if (data['code'] != 'Ok') {
      throw Exception('Маршрут не найден');
    }

    final routes = data['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw Exception('Маршрут не найден');
    }

    final route = routes.first as Map;
    final geometry = route['geometry'];
    final distance = route['distance'];
    final duration = route['duration'];
    if (geometry is! Map ||
        geometry['type'] != 'LineString' ||
        geometry['coordinates'] is! List ||
        distance is! num ||
        !distance.isFinite ||
        distance < 0 ||
        duration is! num ||
        !duration.isFinite ||
        duration < 0) {
      throw const FormatException('Invalid route geometry or estimates');
    }
    final coordinates = geometry['coordinates'] as List;
    if (coordinates.length < 2) {
      throw const FormatException('Route has too few points');
    }
    final points = coordinates.map((coordinate) {
      if (coordinate is! List ||
          coordinate.length < 2 ||
          coordinate[0] is! num ||
          coordinate[1] is! num) {
        throw const FormatException('Invalid route coordinate');
      }
      final latitude = (coordinate[1] as num).toDouble();
      final longitude = (coordinate[0] as num).toDouble();
      if (!_validCoordinate(latitude, longitude)) {
        throw const FormatException('Invalid route coordinate');
      }
      return LatLng(latitude, longitude);
    }).toList();

    return RouteResult(
      points: List.unmodifiable(points),
      distance: distance.toDouble(),
      duration: duration.toDouble(),
    );
  }

  bool _validCoordinate(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
}
