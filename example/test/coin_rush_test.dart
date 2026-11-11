import 'dart:math' as math;

import 'package:coin_rush_example/src/coin_rush_engine.dart';
import 'package:coin_rush_example/src/coin_rush_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  test(
    'CoinRushEngine collects coins, takes damage, purchases rewards, and persists',
    () async {
      final storage = MemoryGameStorage();
      final clock = FakeGameClock();
      final engine = CoinRushEngine(
        storage: storage,
        clock: clock,
        ticker: clock,
        random: math.Random(42),
      );

      await engine.initialize();
      expect(engine.game.status, GameStatus.ready);
      engine.startRun();
      expect(engine.game.status, GameStatus.running);

      // Move player directly onto the first coin to test collection.
      final coin = engine.coins.first;
      engine.playerX = coin.x;
      engine.playerY = coin.y;
      engine.step(0.016);

      expect(engine.game.score.currentScore, greaterThan(0));
      expect(engine.game.rewards.coinBalance, greaterThan(0));
      expect(engine.game.achievements.isUnlocked('first_coin'), isTrue);

      // Grant extra coins and buy a reward from the shop.
      engine.game.rewards.grant(GameReward.coins(40));
      final bought = await engine.purchaseOffer(CoinRushEngine.shopOffers.last);
      expect(bought, isTrue);
      expect(engine.game.score.multiplier, 2.0);

      // Simulate obstacle collision -> loses 1 life and becomes invincible.
      final obstacle = engine.obstacles.first;
      engine.playerX = obstacle.x;
      engine.playerY = obstacle.y;
      engine.step(0.016);
      expect(engine.game.health.lives, 2);
      expect(engine.game.health.isInvincible, isTrue);

      // Persistence across engine restart.
      await engine.game.save();
      await engine.dispose();

      final restored = CoinRushEngine(
        storage: storage,
        clock: clock,
        ticker: clock,
        random: math.Random(42),
      );
      await restored.initialize();
      expect(restored.hasLoadedSavedProgress, isTrue);
      expect(restored.game.score.currentScore, greaterThan(0));
      expect(restored.game.health.lives, 2);
      await restored.dispose();
    },
  );

  testWidgets('CoinRushScreen renders HUD widgets and starts gameplay', (
    tester,
  ) async {
    final storage = MemoryGameStorage();
    await tester.pumpWidget(
      MaterialApp(home: CoinRushScreen(storage: storage)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Coin Rush'), findsWidgets);
    expect(find.text('Start Game'), findsOneWidget);

    await tester.tap(find.text('Start Game'));
    await tester.pump();

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
  });
}
