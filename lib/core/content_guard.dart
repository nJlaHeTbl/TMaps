class ContentGuard {
  ContentGuard._();

  static final RegExp _urlPattern = RegExp(
    r'(https?://|www\.|t\.me/|wa\.me/)',
    caseSensitive: false,
  );
  static final RegExp _controlCharacters = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
  );

  static const List<String> _blockedFragments = [
    'nigger',
    'nigga',
    'пидор',
    'котак',
    'закладк',
    'наркотик',
    'сдох',
  ];

  static String? validateUsername(String? value) {
    final text = value?.trim() ?? '';

    if (text.length < 2) return 'Имя должно содержать хотя бы 2 символа';
    if (text.length > 30) return 'Имя не должно быть длиннее 30 символов';
    if (_controlCharacters.hasMatch(text) ||
        text.contains(RegExp(r'[\r\n\t]'))) {
      return 'Имя содержит недопустимые символы';
    }
    if (_urlPattern.hasMatch(text)) return 'Ссылки в имени запрещены';
    if (_hasBlockedContent(text)) return 'Выбери другое имя без оскорблений';

    return null;
  }

  static String? validateComment(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) return null;
    if (text.length > 300) {
      return 'Комментарий не должен быть длиннее 300 символов';
    }
    if (_controlCharacters.hasMatch(text)) {
      return 'Комментарий содержит недопустимые символы';
    }
    if (_urlPattern.hasMatch(text)) {
      return 'Ссылки в комментариях пока запрещены';
    }
    if (_hasBlockedContent(text)) {
      return 'Удали оскорбления или опасный текст из комментария';
    }

    return null;
  }

  static bool isSafeCommunityToilet(Map<String, dynamic> toilet) {
    final username = toilet['username']?.toString();
    final hasLegacyAnonymousName = username == null || username.trim().isEmpty;

    return (hasLegacyAnonymousName || validateUsername(username) == null) &&
        validateComment(toilet['comment']?.toString()) == null;
  }

  static bool isSafeReport(Map<String, dynamic> report) {
    return validateUsername(report['username']?.toString()) == null &&
        validateComment(report['comment']?.toString()) == null;
  }

  static bool _hasBlockedContent(String value) {
    final normalized = value.toLowerCase().replaceAll('ё', 'е');
    return _blockedFragments.any(normalized.contains);
  }
}
