import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web startup retires legacy cache before loading Flutter', () {
    final index = File('web/index.html').readAsStringSync();
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();

    expect(index, contains('tmapsPrepareForLatestBuild'));
    expect(index, contains('registration.unregister()'));
    expect(index, contains('window.location.reload()'));
    expect(bootstrap, contains('tmapsPrepareForLatestBuild'));
    expect(bootstrap, contains('_flutter.loader.load()'));
  });

  test('retirement worker clears only requests inside its app scope', () {
    final worker = File('web/flutter_service_worker.js').readAsStringSync();

    expect(worker, contains('self.registration.scope'));
    expect(worker, contains('pathname.startsWith(scopePath)'));
    expect(worker, contains('self.registration.unregister()'));
    expect(worker, isNot(contains('caches.delete(cacheName)')));
  });
}
