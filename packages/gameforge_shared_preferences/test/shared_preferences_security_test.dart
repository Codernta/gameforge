import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';
import 'package:gameforge_shared_preferences/gameforge_shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesGameStorage security hardening', () {
    test(
      'rejects unsafe keyPrefix, path traversal keys, and oversized payloads',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        expect(
          () => SharedPreferencesGameStorage(
            preferences: prefs,
            keyPrefix: '../evil:',
          ),
          throwsA(isA<PersistenceException>()),
        );
        expect(
          () =>
              SharedPreferencesGameStorage(preferences: prefs, maxSaveBytes: 0),
          throwsA(isA<GameConfigurationException>()),
        );

        final storage = SharedPreferencesGameStorage(
          preferences: prefs,
          maxSaveBytes: 128,
          maxNestingDepth: 8,
        );

        await expectLater(
          storage.save('../escape', {'a': 1}),
          throwsA(isA<PersistenceException>()),
        );
        await expectLater(
          storage.read('/etc/passwd'),
          throwsA(isA<PersistenceException>()),
        );
        await expectLater(
          storage.delete('bad\x00key'),
          throwsA(isA<PersistenceException>()),
        );
        await expectLater(
          storage.save('oversized', {'blob': 'x' * 256}),
          throwsA(isA<PersistenceException>()),
        );
      },
    );
  });
}
