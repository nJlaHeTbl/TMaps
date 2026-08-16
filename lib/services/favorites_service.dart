import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  const FavoritesService();

  static const _storageKey = 'favorite_place_keys';

  Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_storageKey) ?? const <String>[]).toSet();
  }

  Future<void> save(Set<String> placeKeys) async {
    final preferences = await SharedPreferences.getInstance();
    final sortedKeys = placeKeys.toList()..sort();
    await preferences.setStringList(_storageKey, sortedKeys);
  }
}
