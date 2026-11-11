import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';
import 'package:gameforge_shared_preferences/gameforge_shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesGameStorage', () {
    test('persists, reads, deletes, and clears only prefixed keys', () async {
      SharedPreferences.setMockInitialValues({'unrelated_app_key': 'keep_me'});
      final prefs = await SharedPreferences.getInstance();
      final storage = SharedPreferencesGameStorage(preferences: prefs);

      final game = GameForge(storage: storage);
      await game.initialize();
      game.start();
      game.score.add(250);
      await game.save();
      await game.dispose();

      final restored = GameForge(storage: storage);
      await restored.initialize();
      expect(await restored.load(), isTrue);
      expect(restored.score.currentScore, 250);

      await storage.clear();
      expect(await storage.read(restored.config.saveKey), isNull);
      expect(prefs.getString('unrelated_app_key'), 'keep_me');

      await restored.dispose();
    });
  });
}
