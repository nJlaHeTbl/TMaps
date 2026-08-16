import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmaps/services/favorites_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('сохраняет избранные места между открытиями', () async {
    const service = FavoritesService();

    await service.save({'osm:2', 'osm:1'});

    expect(await service.load(), {'osm:1', 'osm:2'});
  });

  test('позволяет удалить место из избранного', () async {
    const service = FavoritesService();
    await service.save({'osm:1', 'osm:2'});

    await service.save({'osm:2'});

    expect(await service.load(), {'osm:2'});
  });
}
