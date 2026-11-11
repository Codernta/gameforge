import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

class _V1ToV2Migration implements SaveMigration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) {
    final copy = GameSerialization.normalizeMap(data);
    final payload = GameSerialization.readMap(copy, 'payload');
    final score = GameSerialization.readMap(payload, 'score');
    score['currentScore'] = (score['currentScore'] as int) + 100;
    score['highScore'] = (score['highScore'] as int) + 100;
    payload['score'] = score;
    copy['payload'] = payload;
    return copy;
  }
}

void main() {
  group('Persistence, SaveData, Checksums & Migrations', () {
    test('saves and restores full GameForge progression state', () async {
      final storage = MemoryGameStorage();
      final clock = FakeGameClock();
      final achievements = [
        const Achievement(id: 'hero', name: 'Hero', targetValue: 1),
      ];

      final game1 = GameForge(
        storage: storage,
        clock: clock,
        ticker: clock,
        achievements: achievements,
      );
      await game1.initialize();
      game1.start();

      game1.score.add(250);
      game1.score.setMultiplier(1.5);
      game1.score.incrementCombo(by: 3);
      game1.health.takeDamage(30);
      game1.levels.complete(levelId: 'level_1', stars: 3, score: 250);
      game1.levels.select(2);
      game1.inventory.add(
        const GameItem(id: 'ruby', name: 'Ruby', quantity: 4),
      );
      game1.rewards.grant(GameReward.coins(75, id: 'chest_1', oneTime: true));
      game1.achievements.unlock('hero');

      await game1.save();
      await game1.dispose();

      final game2 = GameForge(
        storage: storage,
        clock: clock,
        ticker: clock,
        achievements: achievements,
      );
      await game2.initialize();
      expect(await game2.load(), isTrue);

      expect(game2.score.currentScore, 250);
      expect(game2.score.highScore, 250);
      expect(game2.score.multiplier, 1.5);
      expect(game2.score.comboCount, 3);
      expect(game2.health.currentHealth, 70);
      expect(game2.levels.currentLevelId, 'level_2');
      expect(game2.levels.isCompleted('level_1'), isTrue);
      expect(game2.levels.progressFor('level_1')!.stars, 3);
      expect(game2.inventory.quantityOf('ruby'), 4);
      expect(game2.rewards.coinBalance, 75);
      expect(game2.rewards.isClaimed('chest_1'), isTrue);
      expect(game2.achievements.isUnlocked('hero'), isTrue);

      await game2.dispose();
    });

    test(
      'detects corrupt JSON, tampered checksums, and atomic load rollback',
      () async {
        expect(
          () => GameSerialization.decodeJson('{bad json'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.decodeJson('[1, 2, 3]'),
          throwsA(isA<CorruptSaveDataException>()),
        );

        final storage = MemoryGameStorage();
        final game = GameForge(storage: storage);
        await game.initialize();
        game.score.add(100);
        await game.save();

        // Tamper with stored score without updating checksum
        final raw = (await storage.read(game.config.saveKey))!;
        final payload = Map<String, Object?>.of(
          raw['payload']! as Map<String, Object?>,
        );
        final scoreMap = Map<String, Object?>.of(
          payload['score']! as Map<String, Object?>,
        );
        scoreMap['currentScore'] = 999999;
        payload['score'] = scoreMap;
        raw['payload'] = payload;
        await storage.save(game.config.saveKey, raw);

        await expectLater(
          game.load(),
          throwsA(isA<CorruptSaveDataException>()),
        );

        // Semantic failure rolls back all modules cleanly
        final validButBadHigh = GameSaveData(
          version: 1,
          savedAt: DateTime.utc(2026, 1, 1),
          score: const ScoreState(currentScore: 200, highScore: 100).toJson(),
          inventory: InventoryState(
            slots: const [GameItem(id: 'potion', name: 'Potion', quantity: 9)],
          ).toJson(),
        );
        await storage.save('bad_semantic', validButBadHigh.toJson());
        await expectLater(
          game.load(key: 'bad_semantic'),
          throwsA(isA<SaveValidationException>()),
        );
        expect(game.score.currentScore, 100);
        expect(game.inventory.hasItem('potion'), isFalse);

        await game.dispose();
      },
    );

    test(
      'migrates save data across versions and rejects missing paths/downgrades',
      () async {
        final storage = MemoryGameStorage();

        // Save with version 1
        final v1Game = GameForge(
          config: const GameConfig(saveVersion: 1),
          storage: storage,
        );
        await v1Game.initialize();
        v1Game.score.add(50);
        await v1Game.save();
        await v1Game.dispose();

        // Load with version 2 + migration
        final v2Game = GameForge(
          config: const GameConfig(saveVersion: 2),
          storage: storage,
          saveMigrations: [_V1ToV2Migration()],
        );
        await v2Game.initialize();
        expect(await v2Game.load(), isTrue);
        expect(v2Game.score.currentScore, 150);
        await v2Game.dispose();

        // Missing migration fails cleanly
        final v3Game = GameForge(
          config: const GameConfig(saveVersion: 3),
          storage: storage,
          saveMigrations: [_V1ToV2Migration()],
        );
        await v3Game.initialize();
        await expectLater(
          v3Game.load(),
          throwsA(isA<SaveMigrationException>()),
        );
        await v3Game.dispose();
      },
    );
  });
}
