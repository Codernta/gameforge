import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('ScoreManager', () {
    test(
      'supports add, multiply, subtract, setScore, and high score tracking',
      () async {
        final bus = GameEventBus();
        final events = <GameEvent>[];
        final sub = bus.on<GameEvent>(events.add);

        final score = ScoreManager(eventBus: bus);

        expect(score.add(100), 100);
        expect(score.multiply(2), 200);
        expect(score.subtract(50), 150);
        expect(score.highScore, 200);

        score.reset();
        expect(score.currentScore, 0);
        expect(score.highScore, 200);

        score.setScore(350);
        expect(score.currentScore, 350);
        expect(score.highScore, 350);

        score.reset(resetHighScore: true);
        expect(score.highScore, 0);

        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<HighScoreAchievedEvent>().length, 3);
        expect(events.whereType<ScoreResetEvent>().length, 2);

        await sub.cancel();
        await score.dispose();
        await bus.dispose();
      },
    );

    test('applies base multipliers and combo multipliers accurately', () {
      final score = ScoreManager(
        rules: const ScoreRules(
          comboMultiplierStep: 0.25,
          maxComboMultiplier: 2.0,
        ),
      );

      score.setMultiplier(2.0);
      score.incrementCombo(by: 2); // 1.0 + 0.5 = 1.5 -> effective 3.0
      expect(score.comboMultiplier, 1.5);
      expect(score.effectiveMultiplier, 3.0);
      expect(score.add(10), 30);

      score.incrementCombo(by: 10); // capped at 2.0 -> effective 4.0
      expect(score.comboMultiplier, 2.0);
      expect(score.add(10), 40 + 30);

      score.resetCombo();
      score.resetMultiplier();
      expect(score.effectiveMultiplier, 1.0);
    });

    test('validates negative inputs, bounds, and integer overflow', () {
      final score = ScoreManager(
        rules: const ScoreRules(
          maxScore: 500,
          clampOnOverflow: false,
          clampBelowMin: false,
        ),
      );

      expect(() => score.add(-10), throwsA(isA<ScoreValidationException>()));
      expect(
        () => score.subtract(-5),
        throwsA(isA<ScoreValidationException>()),
      );
      expect(
        () => score.multiply(-2),
        throwsA(isA<ScoreValidationException>()),
      );
      expect(
        () => score.multiply(double.nan),
        throwsA(isA<ScoreValidationException>()),
      );
      expect(
        () => score.setMultiplier(-1),
        throwsA(isA<ScoreValidationException>()),
      );
      expect(
        () => score.setCombo(-1),
        throwsA(isA<ScoreValidationException>()),
      );
      expect(
        () => score.subtract(10),
        throwsA(isA<ScoreValidationException>()),
      );

      score.setScore(400);
      expect(() => score.add(200), throwsA(isA<ScoreValidationException>()));
      expect(() => score.multiply(2), throwsA(isA<ScoreValidationException>()));
      expect(score.currentScore, 400);
    });

    test('clamps overflow and negative subtraction when configured', () {
      final score = ScoreManager(
        rules: const ScoreRules(
          maxScore: 100,
          clampOnOverflow: true,
          clampBelowMin: true,
        ),
      );
      score.add(250);
      expect(score.currentScore, 100);
      score.subtract(500);
      expect(score.currentScore, 0);

      final allowNeg = ScoreManager(
        rules: const ScoreRules(
          allowNegativeScore: true,
          minScore: -50,
          clampBelowMin: true,
        ),
      );
      allowNeg.subtract(30);
      expect(allowNeg.currentScore, -30);
      allowNeg.subtract(100);
      expect(allowNeg.currentScore, -50);
    });
  });
}
