import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('AchievementManager', () {
    test(
      'tracks progress, unlocks at target, grants reward, and is idempotent',
      () async {
        final bus = GameEventBus();
        final unlockedEvents = <AchievementUnlockedEvent>[];
        final sub = bus.on<AchievementUnlockedEvent>(unlockedEvents.add);

        final rewards = RewardManager(eventBus: bus);
        final achievements = AchievementManager(
          rewardManager: rewards,
          eventBus: bus,
          achievements: [
            Achievement(
              id: 'first_100_points',
              name: 'First 100',
              targetValue: 100,
              reward: GameReward.coins(50, id: 'ach_100', oneTime: true),
            ),
            const Achievement(
              id: 'first_win',
              name: 'First Win',
              targetValue: 1,
            ),
          ],
        );

        achievements.increment('first_100_points', amount: 40);
        expect(achievements.isUnlocked('first_100_points'), isFalse);
        expect(
          achievements.getProgress('first_100_points')!.progress,
          closeTo(0.4, 0.001),
        );

        achievements.increment('first_100_points', amount: 100);
        expect(achievements.isUnlocked('first_100_points'), isTrue);
        expect(rewards.coinBalance, 50);

        // Idempotent unlock does not re-grant reward or emit duplicate event
        achievements.unlock('first_100_points');
        achievements.unlock('first_win');
        achievements.unlock('first_win');

        await Future<void>.delayed(Duration.zero);
        expect(unlockedEvents, hasLength(2));
        expect(rewards.coinBalance, 50);

        await sub.cancel();
        await achievements.dispose();
        await rewards.dispose();
        await bus.dispose();
      },
    );

    test('evaluates custom AchievementCondition implementations', () {
      final achievements = AchievementManager(
        achievements: [
          Achievement(
            id: 'high_roller',
            name: 'High Roller',
            targetValue: 500,
            condition: PredicateAchievementCondition(
              (ctx) =>
                  (ctx.score ?? 0) >= 500 &&
                  (ctx.completedLevelsCount ?? 0) >= 2,
              progressResolver: (ctx) => ctx.score,
            ),
          ),
        ],
      );

      expect(
        achievements.evaluate(score: 300, completedLevelsCount: 2),
        isEmpty,
      );
      expect(achievements.getProgress('high_roller')!.currentValue, 300);

      final unlocked = achievements.evaluate(
        score: 600,
        completedLevelsCount: 2,
      );
      expect(unlocked.map((a) => a.id), ['high_roller']);
      expect(achievements.isUnlocked('high_roller'), isTrue);
    });
  });
}
