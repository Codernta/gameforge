import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('RewardManager', () {
    test('grants coins, points, items, xp, custom rewards, and bundles', () {
      final score = ScoreManager();
      final inventory = InventoryManager();
      final rewards = RewardManager(
        scoreManager: score,
        inventoryManager: inventory,
      );

      String? customBadge;
      rewards.registerHandler('badge', (reward) {
        customBadge = reward.customData['badgeId'] as String?;
      });

      rewards.grant(GameReward.coins(100));
      expect(rewards.coinBalance, 100);

      rewards.grant(GameReward.points(50));
      expect(score.currentScore, 50);

      rewards.grant(
        GameReward.item(const GameItem(id: 'shield', name: 'Shield')),
      );
      expect(inventory.hasItem('shield'), isTrue);

      rewards.grant(GameReward.experience(250));
      expect(rewards.totalExperience, 250);

      rewards.grant(
        GameReward.custom(
          id: 'badge_1',
          customType: 'badge',
          data: const {'badgeId': 'founder'},
        ),
      );
      expect(customBadge, 'founder');

      rewards.grant(
        GameReward.bundle(
          id: 'starter_pack',
          oneTime: true,
          rewards: [
            GameReward.coins(25),
            GameReward.points(75),
            GameReward.experience(50),
          ],
        ),
      );
      expect(rewards.coinBalance, 125);
      expect(score.currentScore, 125);
      expect(rewards.totalExperience, 300);

      // Spend coins
      expect(rewards.spendCoins(45, reason: 'upgrade'), 80);
      expect(() => rewards.spendCoins(200), throwsA(isA<RewardException>()));
    });

    test(
      'prevents duplicate claims on one-time rewards and supports offer/claim',
      () {
        final rewards = RewardManager();

        final oneTime = GameReward.coins(
          50,
          id: 'welcome_bonus',
          oneTime: true,
        );
        rewards.grant(oneTime);
        expect(rewards.isClaimed('welcome_bonus'), isTrue);
        expect(
          () => rewards.grant(oneTime),
          throwsA(isA<RewardAlreadyClaimedException>()),
        );

        final offered = rewards.offer(GameReward.coins(20));
        expect(rewards.pendingRewards, hasLength(1));
        rewards.claim(offered.id!);
        expect(rewards.pendingRewards, isEmpty);
        expect(rewards.coinBalance, 70);

        rewards.offer(GameReward.coins(10, id: 'p1'));
        rewards.offer(GameReward.coins(15, id: 'p2'));
        rewards.claimAll();
        expect(rewards.coinBalance, 95);
      },
    );
  });
}
