import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  test('GameForge end-to-end gameplay smoke integration', () async {
    final clock = FakeGameClock();
    final storage = MemoryGameStorage();
    final game = GameForge(
      config: const GameConfig(initialLives: 3, initialScore: 0, maxLevels: 10),
      storage: storage,
      clock: clock,
      ticker: clock,
      achievements: const [
        Achievement(id: 'first_win', name: 'First Win', targetValue: 1),
      ],
    );

    await game.initialize();
    game.start();

    game.score.add(100);
    game.health.takeDamage(10);
    game.inventory.add(
      const GameItem(id: 'coin', name: 'Gold Coin', quantity: 5),
    );
    game.rewards.grant(GameReward.coins(25));
    game.levels.complete(levelId: 'level_1', stars: 3, score: 100);
    game.levels.next();
    game.achievements.unlock('first_win');

    await game.save();
    await game.dispose();

    final restored = GameForge(
      config: const GameConfig(maxLevels: 10),
      storage: storage,
      clock: clock,
      ticker: clock,
      achievements: const [
        Achievement(id: 'first_win', name: 'First Win', targetValue: 1),
      ],
    );
    await restored.initialize();
    expect(await restored.load(), isTrue);
    expect(restored.score.currentScore, 100);
    expect(restored.health.currentHealth, 90);
    expect(restored.inventory.quantityOf('coin'), 5);
    expect(restored.rewards.coinBalance, 25);
    expect(restored.levels.currentLevelId, 'level_2');
    expect(restored.achievements.isUnlocked('first_win'), isTrue);
    await restored.dispose();
  });
}
