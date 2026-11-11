import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('LevelManager', () {
    test('supports sequential unlock, stars, best score, and next()', () {
      final levels = LevelManager(maxLevels: 5);

      expect(levels.currentLevelId, 'level_1');
      expect(levels.isUnlocked('level_1'), isTrue);
      expect(levels.isNumberUnlocked(2), isFalse);

      expect(() => levels.select(2), throwsA(isA<LevelLockedException>()));

      levels.complete(levelId: 'level_1', stars: 2, score: 150);
      expect(levels.isCompleted('level_1'), isTrue);
      expect(levels.isNumberUnlocked(2), isTrue);

      // Replaying with fewer stars retains best stars & score
      levels.complete(levelId: 'level_1', stars: 1, score: 120);
      expect(levels.progressFor('level_1')!.stars, 2);
      expect(levels.progressFor('level_1')!.bestScore, 150);

      final next = levels.next();
      expect(next?.id, 'level_2');
      expect(levels.currentLevelId, 'level_2');

      levels.unlock(5);
      expect(levels.isNumberUnlocked(5), isTrue);
      levels.lock(5);
      expect(levels.isNumberUnlocked(5), isFalse);
    });

    test('supports non-sequential PrerequisiteLevelProgression', () {
      const configs = [
        LevelConfig(id: 'hub', number: 1, unlockedByDefault: true),
        LevelConfig(id: 'forest', number: 2, prerequisiteIds: ['hub']),
        LevelConfig(id: 'desert', number: 3, prerequisiteIds: ['hub']),
        LevelConfig(
          id: 'citadel',
          number: 4,
          prerequisiteIds: ['forest', 'desert'],
        ),
      ];

      final levels = LevelManager(
        levels: configs,
        progressionStrategy: const PrerequisiteLevelProgression(),
      );

      levels.complete(levelId: 'hub', stars: 3);
      expect(levels.isUnlocked('forest'), isTrue);
      expect(levels.isUnlocked('desert'), isTrue);
      expect(levels.isUnlocked('citadel'), isFalse);

      levels.selectById('forest');
      levels.complete(levelId: 'forest', stars: 3);
      expect(levels.isUnlocked('citadel'), isFalse);

      final next = levels.next();
      expect(next?.id, 'desert');
      levels.complete(levelId: 'desert', stars: 2);
      expect(levels.isUnlocked('citadel'), isTrue);
      expect(levels.state.totalStars, 8);
    });

    test('validates unknown levels, locked completion, and invalid stars', () {
      final levels = LevelManager(maxLevels: 3);
      expect(() => levels.unlock(99), throwsA(isA<LevelNotFoundException>()));
      expect(
        () => levels.unlockById('missing'),
        throwsA(isA<LevelNotFoundException>()),
      );
      expect(
        () => levels.complete(levelId: 'level_2', stars: 1),
        throwsA(isA<LevelLockedException>()),
      );
      expect(
        () => levels.complete(levelId: 'level_1', stars: 4),
        throwsA(isA<LevelException>()),
      );
    });
  });
}
