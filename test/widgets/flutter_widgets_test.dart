import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/flutter.dart';

void main() {
  group('GameForge Flutter widgets & adapters', () {
    testWidgets(
      'GameScoreWidget animates and displays multiplier, combo, and high score',
      (tester) async {
        final game = GameForge();
        await game.initialize();
        game.start();

        await tester.pumpWidget(
          MaterialApp(
            home: GameForgeScope(
              game: game,
              child: const Scaffold(
                body: GameScoreWidget(
                  showMultiplier: true,
                  showCombo: true,
                  showHighScore: true,
                  animationDuration: Duration(milliseconds: 100),
                ),
              ),
            ),
          ),
        );

        expect(find.text('0'), findsOneWidget);

        game.score.setMultiplier(2.0);
        game.score.incrementCombo();
        game.score.add(50);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.text('110'), findsOneWidget);
        expect(find.text('2.0x'), findsOneWidget);
        expect(find.text('1x combo'), findsOneWidget);
        expect(find.text('Best: 110'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => game.dispose());
      },
    );

    testWidgets('GameHealthWidget renders hearts and bar modes reactively', (
      tester,
    ) async {
      final game = GameForge(
        config: const GameConfig(
          initialLives: 3,
          maxLives: 3,
          initialHealth: 100,
          maxHealth: 100,
        ),
      );
      await game.initialize();
      game.start();

      await tester.pumpWidget(
        MaterialApp(
          home: GameForgeScope(
            game: game,
            child: const Scaffold(
              body: GameHealthWidget(mode: GameHealthDisplayMode.both),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsNWidgets(3));
      expect(find.text('100/100'), findsOneWidget);

      game.health.takeDamage(40);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('60/100'), findsOneWidget);

      game.health.loseLife();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => game.dispose());
    });

    testWidgets(
      'GameTimerWidget formats remaining countdown and updates on FakeGameClock',
      (tester) async {
        final clock = FakeGameClock();
        final game = GameForge(clock: clock, ticker: clock);
        await game.initialize();
        game.start();

        final timer = game.timers.countdown(
          duration: const Duration(seconds: 65),
          tickInterval: const Duration(seconds: 1),
          autoStart: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GameTimerWidget(
                timer: timer,
                warningThreshold: const Duration(seconds: 10),
                showProgressBar: true,
              ),
            ),
          ),
        );

        expect(find.text('01:05'), findsOneWidget);

        clock.advance(const Duration(seconds: 60));
        await tester.pump();
        expect(find.text('00:05'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => game.dispose());
      },
    );

    testWidgets(
      'GameForgeInputRegion and VirtualJoystickWidget dispatch input events',
      (tester) async {
        final game = GameForge();
        await game.initialize();

        final events = <GameInputEvent>[];
        final sub = game.input.stream.listen(events.add);

        await tester.pumpWidget(
          MaterialApp(
            home: GameForgeScope(
              game: game,
              child: const Scaffold(
                body: Column(
                  children: [
                    SizedBox(
                      width: 200,
                      height: 100,
                      child: GameForgeInputRegion(
                        child: ColoredBox(color: Colors.blue),
                      ),
                    ),
                    VirtualJoystickWidget(size: 100),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(GameForgeInputRegion));
        await tester.pump(const Duration(milliseconds: 350));

        await tester.tap(find.byType(GameForgeInputRegion));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byType(GameForgeInputRegion));
        await tester.pump(const Duration(milliseconds: 350));

        await tester.longPress(find.byType(GameForgeInputRegion));
        await tester.pump();

        await tester.fling(
          find.byType(GameForgeInputRegion),
          const Offset(200, 0),
          1000,
        );
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.pump();

        await tester.drag(
          find.byType(VirtualJoystickWidget),
          const Offset(30, 0),
        );
        await tester.pump();

        expect(events.whereType<TapInputEvent>(), isNotEmpty);
        expect(events.whereType<DoubleTapInputEvent>(), isNotEmpty);
        expect(events.whereType<LongPressInputEvent>(), isNotEmpty);
        expect(events.whereType<DragInputEvent>(), isNotEmpty);
        expect(events.whereType<SwipeInputEvent>(), isNotEmpty);
        expect(events.whereType<KeyInputEvent>(), isNotEmpty);
        expect(events.whereType<JoystickInputEvent>(), isNotEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => sub.cancel());
        await tester.runAsync(() => game.dispose());
      },
    );

    testWidgets('GameForgeBuilder, GameForgeStatusBuilder, and scope lookups', (
      tester,
    ) async {
      final game = GameForge();
      await game.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: GameForgeScope(
            game: game,
            child: Scaffold(
              body: Column(
                children: [
                  GameForgeStatusBuilder(
                    builder: (context, status, _) =>
                        Text('status:${status.name}'),
                  ),
                  GameForgeBuilder(
                    builder: (context, state, _) =>
                        Text('score:${state.score.currentScore}'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('status:ready'), findsOneWidget);
      expect(find.text('score:0'), findsOneWidget);

      game.start();
      game.score.add(42);
      await tester.pump();
      expect(find.text('status:running'), findsOneWidget);
      expect(find.text('score:42'), findsOneWidget);

      // Verify GameForgeScope.of throws helpful FlutterError when missing
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(GameForgeScope.maybeOf(context), isNull);
              expect(
                () => GameForgeScope.of(context),
                throwsA(isA<FlutterError>()),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => game.dispose());
    });
  });
}
