import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';
import 'package:gameforge_flame/gameforge_flame.dart';

class _TestFlameGame extends FlameGame with GameForgeFlameMixin {
  _TestFlameGame(this.gameForge);

  @override
  final GameForge gameForge;
}

void main() {
  group('gameforge_flame integration', () {
    testWidgets(
      'GameForgeFlameMixin synchronizes lifecycle, pause/resume, and disposal',
      (tester) async {
        final controller = GameForge();
        final flameGame = _TestFlameGame(controller);

        await tester.pumpWidget(GameWidget(game: flameGame));
        await tester.pump();
        await tester.runAsync(() => flameGame.ready());
        await tester.pump();

        expect(controller.status, GameStatus.running);
        expect(flameGame.paused, isFalse);

        // GameForge pause -> Flame engine pauses
        controller.pause();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(flameGame.paused, isTrue);

        // GameForge resume -> Flame engine resumes
        controller.resume();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(flameGame.paused, isFalse);

        // Flame pauseEngine -> GameForge pauses without circular loop
        flameGame.pauseEngine();
        expect(flameGame.paused, isTrue);
        expect(controller.status, GameStatus.paused);

        // Flame resumeEngine -> GameForge resumes without circular loop
        flameGame.resumeEngine();
        expect(flameGame.paused, isFalse);
        expect(controller.status, GameStatus.running);

        await tester.pumpWidget(const SizedBox.shrink());
        flameGame.dispose();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(controller.status, GameStatus.disposed);
      },
    );

    testWidgets(
      'Score, Health, and EventListener components sync and unsubscribe on remove',
      (tester) async {
        final controller = GameForge();
        await controller.initialize();
        controller.start();

        final flameGame = FlameGame();
        final scoreSnapshots = <int>[];
        final healthSnapshots = <double>[];
        final receivedEvents = <ScoreChangedEvent>[];

        final scoreComp = GameForgeScoreComponent(
          scoreManager: controller.score,
          onScoreChanged: (s) => scoreSnapshots.add(s.currentScore),
        );
        final healthComp = GameForgeHealthComponent(
          healthManager: controller.health,
          onHealthChanged: (h) => healthSnapshots.add(h.currentHealth),
        );
        final eventComp = GameForgeEventListenerComponent<ScoreChangedEvent>(
          eventBus: controller.events,
          onEvent: receivedEvents.add,
        );

        await tester.pumpWidget(GameWidget(game: flameGame));
        await tester.pump();
        await flameGame.addAll([scoreComp, healthComp, eventComp]);
        await tester.runAsync(() => flameGame.ready());
        await tester.pump();

        controller.score.add(40);
        controller.health.takeDamage(15);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(scoreComp.currentScore, 40);
        expect(healthComp.currentHealth, 85);
        expect(scoreSnapshots, [0, 40]);
        expect(healthSnapshots, [100, 85]);
        expect(receivedEvents, hasLength(1));

        // Removing components unsubscribes safely
        flameGame.removeAll([scoreComp, healthComp, eventComp]);
        await tester.runAsync(() => flameGame.ready());
        await tester.pump();

        controller.score.add(100);
        controller.health.takeDamage(10);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(scoreSnapshots, [0, 40]);
        expect(healthSnapshots, [100, 85]);
        expect(receivedEvents, hasLength(1));

        await tester.pumpWidget(const SizedBox.shrink());
        flameGame.dispose();
        await tester.runAsync(() => controller.dispose());
      },
    );
  });
}
