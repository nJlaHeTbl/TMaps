import 'package:flutter_test/flutter_test.dart';
import 'package:tmaps/core/content_guard.dart';

void main() {
  group('ContentGuard', () {
    test('accepts a normal username and useful comment', () {
      expect(ContentGuard.validateUsername('Мирас'), isNull);
      expect(
        ContentGuard.validateComment('Находится внутри ТЦ, рядом с аптекой'),
        isNull,
      );
    });

    test('rejects links and abusive content', () {
      expect(ContentGuard.validateUsername('https://spam.kz'), isNotNull);
      expect(
        ContentGuard.validateComment('Здесь оставили закладку'),
        isNotNull,
      );
    });

    test('hides unsafe community rows', () {
      expect(
        ContentGuard.isSafeCommunityToilet({'username': null, 'comment': null}),
        isTrue,
      );
      expect(
        ContentGuard.isSafeCommunityToilet({
          'username': 'Нормальный пользователь',
          'comment': 'Первый этаж',
        }),
        isTrue,
      );
      expect(
        ContentGuard.isSafeCommunityToilet({
          'username': 'Спамер',
          'comment': 'Переходи на https://spam.kz',
        }),
        isFalse,
      );
    });
  });
}
