import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmaps/core/map_base_style.dart';
import 'package:tmaps/services/map_style_preference_service.dart';

void main() {
  const service = MapStylePreferenceService();

  test('по умолчанию открывает обычную карту', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await service.load(), MapBaseStyle.streets);
  });

  test('сохраняет спутниковый слой между открытиями', () async {
    SharedPreferences.setMockInitialValues({});

    await service.save(MapBaseStyle.satellite);

    expect(await service.load(), MapBaseStyle.satellite);
  });
}
