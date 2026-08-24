import 'package:shared_preferences/shared_preferences.dart';

import '../core/map_base_style.dart';

class MapStylePreferenceService {
  const MapStylePreferenceService();

  static const _preferenceKey = 'map_base_style';

  Future<MapBaseStyle> load() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_preferenceKey)) {
      'satellite' => MapBaseStyle.satellite,
      _ => MapBaseStyle.streets,
    };
  }

  Future<void> save(MapBaseStyle style) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, style.name);
  }
}
