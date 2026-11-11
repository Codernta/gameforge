import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

class _TrackingModule extends GameModule {
  _TrackingModule(this.id, {this.failOnInit = false, this.failOnLoad = false});

  @override
  final String id;

  final bool failOnInit;
  final bool failOnLoad;

  final List<String> calls = [];
  int counter = 0;

  @override
  Future<void> onInitialize(GameModuleContext context) async {
    calls.add('initialize');
    if (failOnInit) {
      throw const GameModuleException('Init boom');
    }
  }

  @override
  void onStart() => calls.add('start');

  @override
  void onPause() => calls.add('pause');

  @override
  void onResume() => calls.add('resume');

  @override
  void onComplete() => calls.add('complete');

  @override
  void onGameOver() => calls.add('gameOver');

  @override
  void onReset() {
    calls.add('reset');
    counter = 0;
  }

  @override
  Future<void> onDispose() async {
    calls.add('dispose');
  }

  @override
  Map<String, Object?> toSaveData() => {'counter': counter};

  @override
  void fromSaveData(Map<String, Object?> data) {
    if (failOnLoad) {
      throw const SaveValidationException('Module save invalid');
    }
    counter = GameSerialization.readInt(data, 'counter');
  }
}

void main() {
  group('GameForge lifecycle & core controller', () {
    test('supports full happy-path lifecycle and status transitions', () async {
      final clock = FakeGameClock();
      final audio = RecordingGameAudioService();
      final module = _TrackingModule('custom');
      final game = GameForge(
        config: const GameConfig(
          initialLives: 3,
          initialScore: 0,
          maxLevels: 50,
        ),
        clock: clock,
        ticker: clock,
        audio: audio,
        modules: [module],
      );

      final statuses = <GameStatus>[];
      final sub = game.statusStream.listen(statuses.add);

      expect(game.status, GameStatus.uninitialized);
      expect(game.getModule<_TrackingModule>(), same(module));
      expect(game.getModuleById('custom'), same(module));

      await game.initialize();
      expect(game.status, GameStatus.ready);
      expect(audio.isInitialized, isTrue);

      game.start();
      expect(game.status, GameStatus.running);
      expect(game.session.status, SessionStatus.active);

      await audio.playMusic('theme');
      game.pause();
      expect(game.status, GameStatus.paused);
      expect(audio.isMusicPaused, isTrue);
      expect(game.session.status, SessionStatus.paused);

      game.resume();
      expect(game.status, GameStatus.running);
      expect(audio.isMusicPlaying, isTrue);
      expect(game.session.status, SessionStatus.active);

      game.score.add(100);
      game.health.takeDamage(1);
      game.levels.unlock(2);
      module.counter = 42;

      await game.save();
      game.restart();
      expect(game.status, GameStatus.running);
      expect(game.score.currentScore, 0);
      expect(module.counter, 0);

      expect(await game.load(), isTrue);
      expect(game.score.currentScore, 100);
      expect(game.health.currentHealth, 99);
      expect(game.levels.isNumberUnlocked(2), isTrue);
      expect(module.counter, 42);

      game.complete();
      expect(game.status, GameStatus.completed);
      expect(game.session.status, SessionStatus.completed);

      game.restart(autoStart: false);
      expect(game.status, GameStatus.ready);
      game.start();
      game.triggerGameOver(reason: 'boss');
      expect(game.status, GameStatus.gameOver);
      expect(game.session.status, SessionStatus.abandoned);

      await game.dispose();
      // Idempotent second dispose
      await game.dispose();
      expect(game.status, GameStatus.disposed);
      expect(module.calls, [
        'initialize',
        'start',
        'pause',
        'resume',
        'reset',
        'start',
        'complete',
        'reset',
        'start',
        'gameOver',
        'dispose',
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(statuses, [
        GameStatus.initializing,
        GameStatus.ready,
        GameStatus.running,
        GameStatus.paused,
        GameStatus.running,
        GameStatus.ready,
        GameStatus.running,
        GameStatus.completed,
        GameStatus.ready,
        GameStatus.running,
        GameStatus.gameOver,
        GameStatus.disposed,
      ]);
      await sub.cancel();
    });

    test('prevents invalid lifecycle transitions', () async {
      final game = GameForge();

      expect(
        () => game.start(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.pause(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.resume(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.complete(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.triggerGameOver(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.restart(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      await expectLater(
        game.save(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );

      await game.initialize();
      expect(
        () => game.initialize(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.pause(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.resume(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.registerModule(_TrackingModule('late')),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );

      game.start();
      expect(
        () => game.start(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.resume(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );

      game.pause();
      expect(
        () => game.pause(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );

      await game.dispose();
      expect(
        () => game.start(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.attachModule(_TrackingModule('after_dispose')),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
      expect(
        () => game.deleteSave(),
        throwsA(isA<InvalidLifecycleTransitionException>()),
      );
    });

    test(
      'rolls back to uninitialized when module initialization fails',
      () async {
        final failing = _TrackingModule('bad', failOnInit: true);
        final game = GameForge(modules: [failing]);

        await expectLater(
          game.initialize(),
          throwsA(isA<GameModuleException>()),
        );
        expect(game.status, GameStatus.uninitialized);
        await game.dispose();

        // Custom module load failure rolls back cleanly
        final storage = MemoryGameStorage();
        final source = GameForge(
          storage: storage,
          modules: [_TrackingModule('mod')],
        );
        await source.initialize();
        source.score.add(50);
        await source.save();
        await source.dispose();

        final target = GameForge(
          storage: storage,
          modules: [_TrackingModule('mod', failOnLoad: true)],
        );
        await target.initialize();
        target.score.add(10);
        await expectLater(
          target.load(),
          throwsA(isA<SaveValidationException>()),
        );
        expect(target.score.currentScore, 10);
        await target.dispose();
      },
    );

    test('validates duplicate or empty custom module registrations', () async {
      final game = GameForge();
      expect(
        () => game.registerModule(_TrackingModule('  ')),
        throwsA(isA<GameModuleException>()),
      );
      expect(
        () => game.registerModule(_TrackingModule(ScoreManager.moduleId)),
        throwsA(isA<GameModuleException>()),
      );

      await game.initialize();
      final dynamicModule = _TrackingModule('late_attach');
      await game.attachModule(dynamicModule);
      expect(dynamicModule.calls, ['initialize']);
      expect(game.getModuleById('late_attach'), same(dynamicModule));
      await game.dispose();
    });

    test(
      'supports multiple independent simultaneous GameForge instances',
      () async {
        final gameA = GameForge(config: const GameConfig(initialScore: 10));
        final gameB = GameForge(config: const GameConfig(initialScore: 500));

        await Future.wait([gameA.initialize(), gameB.initialize()]);
        gameA.start();
        gameB.start();

        gameA.score.add(25);
        gameB.score.subtract(100);
        gameA.health.takeDamage(30);

        expect(gameA.score.currentScore, 35);
        expect(gameB.score.currentScore, 400);
        expect(gameA.health.currentHealth, 70);
        expect(gameB.health.currentHealth, 100);

        await gameA.dispose();
        expect(gameA.status, GameStatus.disposed);
        expect(gameB.status, GameStatus.running);
        gameB.score.add(50);
        expect(gameB.score.currentScore, 450);

        await gameB.dispose();
      },
    );

    test('auto-triggers gameOver when all lives are exhausted', () async {
      final game = GameForge(
        config: const GameConfig(
          initialLives: 2,
          initialHealth: 50,
          maxHealth: 50,
        ),
      );
      await game.initialize();
      game.start();

      game.health.takeDamage(50);
      expect(game.health.lives, 1);
      expect(game.status, GameStatus.running);

      game.health.takeDamage(50);
      expect(game.health.lives, 0);
      expect(game.health.isDead, isTrue);
      expect(game.status, GameStatus.gameOver);

      await game.dispose();
    });

    test('validates GameConfig boundaries', () {
      expect(
        () => GameForge(config: const GameConfig(maxHealth: 0)),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => GameForge(config: const GameConfig(maxLevels: 0)),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => GameForge(config: const GameConfig(levelConfigs: [])),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => GameForge(config: const GameConfig(inventoryCapacity: -1)),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => GameForge(config: const GameConfig(saveKey: '')),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => GameForge(config: const GameConfig(saveVersion: 0)),
        throwsA(isA<GameConfigurationException>()),
      );
    });
  });
}
