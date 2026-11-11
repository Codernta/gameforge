import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

class _MinimalModule extends GameModule {
  @override
  String get id => 'minimal';
}

void main() {
  group('Models, Config Validation & Serialization Roundtrips', () {
    test('GameConfig validate and copyWith cover edge cases', () {
      const base = GameConfig(
        initialScore: 10,
        maxScore: 100,
        maxHealth: 80,
        initialHealth: 60,
        initialLives: 2,
        maxLives: 4,
      );
      final copied = base.copyWith(
        initialScore: 20,
        maxLevels: 5,
        autoStartSession: false,
      );
      expect(copied.initialScore, 20);
      expect(copied.maxLevels, 5);
      expect(copied.autoStartSession, isFalse);

      expect(
        () => const GameConfig(initialHealth: 150, maxHealth: 100).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const GameConfig(initialLives: 5, maxLives: 3).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const GameConfig(
          invincibilityDuration: Duration(seconds: -1),
        ).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
    });

    test('ScoreRules & ScoreState validate, copyWith, equality, and JSON', () {
      expect(
        () => const ScoreRules(minScore: 50, maxScore: 10).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const ScoreRules(initialScore: 200, maxScore: 100).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const ScoreRules(comboMultiplierStep: -0.5).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const ScoreRules(maxComboMultiplier: 0.5).validate(),
        throwsA(isA<GameConfigurationException>()),
      );

      final rules = const ScoreRules().copyWith(maxScore: 999);
      expect(rules.maxScore, 999);

      const s1 = ScoreState(currentScore: 10, highScore: 20, multiplier: 2.0);
      final s2 = s1.copyWith(currentScore: 10);
      expect(s1, s2);
      expect(s1.hashCode, s2.hashCode);
      expect(s1.toString(), contains('currentScore: 10'));
      expect(s1.toJson()['multiplier'], 2.0);
    });

    test('HealthConfig & HealthState validate, copyWith, and equality', () {
      expect(
        () => const HealthConfig(maxHealth: -1).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const HealthConfig(respawnHealth: 0).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const HealthConfig(initialLives: -1).validate(),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => const HealthConfig(maxLives: -1).validate(),
        throwsA(isA<GameConfigurationException>()),
      );

      final hc = const HealthConfig().copyWith(initialLives: 5);
      expect(hc.initialLives, 5);

      final t = DateTime.utc(2026, 2, 1);
      final h1 = HealthState(
        currentHealth: 50,
        maxHealth: 100,
        lives: 2,
        invincibleUntil: t,
        isInvincible: true,
      );
      final h2 = h1.copyWith(currentHealth: 50);
      expect(h1, h2);
      expect(h1.hashCode, h2.hashCode);
      expect(h1.toString(), contains('50.0/100.0'));
      expect(h1.copyWith(clearInvincibleUntil: true).invincibleUntil, isNull);
    });

    test(
      'LevelConfig, LevelProgress, LevelState, and OpenLevelProgression',
      () {
        expect(
          () => const LevelConfig(id: ' ', number: 1).validate(),
          throwsA(isA<GameConfigurationException>()),
        );
        expect(
          () => const LevelConfig(id: 'l0', number: 0).validate(),
          throwsA(isA<GameConfigurationException>()),
        );
        expect(
          () => const LevelConfig(id: 'l1', number: 1, maxStars: -1).validate(),
          throwsA(isA<GameConfigurationException>()),
        );

        final openLevels = LevelManager(
          maxLevels: 3,
          progressionStrategy: const OpenLevelProgression(),
        );
        expect(openLevels.isNumberUnlocked(3), isTrue);
        expect(openLevels.next()?.id, 'level_2');
        expect(openLevels.next()?.id, 'level_3');
        expect(openLevels.next(), isNull);
        expect(openLevels.next(unlockNext: true), isNull);

        openLevels.complete(levelId: 'level_1', stars: 3);
        expect(openLevels.state.completionRatio, closeTo(1 / 3, 0.01));
        expect(openLevels.state.completedLevelIds, {'level_1'});
        expect(openLevels.state.unlockedLevelIds, {
          'level_1',
          'level_2',
          'level_3',
        });

        const p1 = LevelProgress(levelId: 'a', isUnlocked: true, stars: 2);
        final p2 = p1.copyWith(stars: 2);
        expect(p1, p2);
        expect(p1.hashCode, p2.hashCode);
      },
    );

    test('GameItem validation, equality, and JSON serialization', () {
      expect(
        () => const GameItem(id: '', name: 'A').validate(),
        throwsA(isA<InvalidItemException>()),
      );
      expect(
        () => const GameItem(id: 'a', name: '').validate(),
        throwsA(isA<InvalidItemException>()),
      );
      expect(
        () => const GameItem(id: 'a', name: 'A', type: '').validate(),
        throwsA(isA<InvalidItemException>()),
      );
      expect(
        () => const GameItem(id: 'a', name: 'A', quantity: 0).validate(),
        throwsA(isA<InvalidItemException>()),
      );
      expect(
        () => const GameItem(id: 'a', name: 'A', maxStackSize: 0).validate(),
        throwsA(isA<InvalidItemException>()),
      );
      expect(
        () => const GameItem(
          id: 'a',
          name: 'A',
          stackable: false,
          quantity: 2,
        ).validate(),
        throwsA(isA<InvalidItemException>()),
      );

      const item = GameItem(
        id: 'orb',
        name: 'Orb',
        description: 'Shiny',
        type: 'relic',
        quantity: 3,
        maxStackSize: 5,
        metadata: {'rarity': 'rare'},
      );
      final restored = GameItem.fromJson(item.toJson());
      expect(restored, item);
      expect(restored.hashCode, item.hashCode);
      expect(restored.toString(), contains('Orb'));
    });

    test(
      'GameReward JSON serialization and validation across all reward types',
      () {
        expect(() => GameReward.coins(0), throwsA(isA<RewardException>()));
        expect(
          () => GameReward.coins(10, oneTime: true),
          throwsA(isA<RewardException>()),
        );
        expect(
          () => GameReward.custom(id: '', customType: 't'),
          throwsA(isA<RewardException>()),
        );
        expect(
          () => GameReward.custom(id: 'id', customType: ''),
          throwsA(isA<RewardException>()),
        );
        expect(
          () => GameReward.bundle(id: 'b', rewards: []),
          throwsA(isA<RewardException>()),
        );

        final bundle = GameReward.bundle(
          id: 'pack',
          oneTime: true,
          rewards: [
            GameReward.coins(10),
            GameReward.points(20),
            GameReward.experience(30),
            GameReward.item(const GameItem(id: 'gem', name: 'Gem')),
            GameReward.custom(
              id: 'c1',
              customType: 'skin',
              data: const {'color': 'gold'},
            ),
          ],
        );
        final decoded = GameReward.fromJson(bundle.toJson());
        expect(decoded.type, GameRewardType.bundle);
        expect(decoded.rewards, hasLength(5));
        expect(decoded.rewards[1].type, GameRewardType.points);
        expect(decoded.rewards[2].type, GameRewardType.experience);
        expect(decoded.rewards[3].type, GameRewardType.item);
        expect(decoded.rewards[4].customType, 'skin');
      },
    );

    test(
      'Achievement & AchievementProgress validation, equality, and stats',
      () {
        expect(
          () => const Achievement(id: '', name: 'A').validate(),
          throwsA(isA<AchievementException>()),
        );
        expect(
          () => const Achievement(id: 'a', name: '').validate(),
          throwsA(isA<AchievementException>()),
        );
        expect(
          () =>
              const Achievement(id: 'a', name: 'A', targetValue: 0).validate(),
          throwsA(isA<AchievementException>()),
        );

        const p1 = AchievementProgress(
          achievementId: 'x',
          currentValue: 5,
          targetValue: 10,
          isUnlocked: false,
        );
        final p2 = p1.copyWith(currentValue: 5);
        expect(p1, p2);
        expect(p1.hashCode, p2.hashCode);
        expect(p1.progress, 0.5);

        final state = AchievementState(
          entries: {
            'x': p1,
            'y': p1.copyWith(isUnlocked: true, unlockedAt: DateTime.utc(2026)),
          },
        );
        expect(state.unlockedCount, 1);
        expect(state.totalCount, 2);
      },
    );

    test('AudioSettings JSON roundtrip, equality, and validation', () {
      const settings = AudioSettings(
        masterVolume: 0.7,
        musicVolume: 0.5,
        sfxVolume: 0.9,
        isMusicMuted: true,
      );
      final decoded = AudioSettings.fromJson(settings.toJson());
      expect(decoded, settings);
      expect(decoded.hashCode, settings.hashCode);

      expect(
        () => AudioSettings.fromJson(const {'masterVolume': 2.0}),
        throwsA(isA<SaveValidationException>()),
      );
    });

    test(
      'GameSerialization strict type guards and MemoryGameStorage methods',
      () async {
        expect(
          () => GameSerialization.readInt({}, 'missing'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readInt({'k': 'nope'}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readDouble({'k': double.nan}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readBool({'k': 1}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readString({'k': 123}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readOptionalString({'k': 123}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readDateTime({'k': 'bad-date'}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readMap({'k': []}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.readList({'k': {}}, 'k'),
          throwsA(isA<CorruptSaveDataException>()),
        );

        final storage = MemoryGameStorage(
          initialEntries: {
            'slot1': {'a': 1},
          },
        );
        expect(storage.containsKey('slot1'), isTrue);
        expect(storage.keys, ['slot1']);
        await storage.delete('slot1');
        expect(storage.containsKey('slot1'), isFalse);
        await storage.save('slot2', {'b': 2});
        await storage.clear();
        expect(storage.keys, isEmpty);
      },
    );

    test('InputVector2D, InputDirection vectors, and input events', () {
      const a = InputVector2D(3, 4);
      const b = InputVector2D(1, 2);
      expect(a.magnitude, 5.0);
      expect(a.normalized.magnitude, closeTo(1.0, 0.0001));
      expect(a + b, const InputVector2D(4, 6));
      expect(a - b, const InputVector2D(2, 2));
      expect(b * 2, const InputVector2D(2, 4));
      expect(a.toString(), 'InputVector2D(3.0, 4.0)');

      for (final dir in InputDirection.values) {
        final v = dir.toVector();
        if (dir == InputDirection.none) {
          expect(v, InputVector2D.zero);
        } else {
          expect(v.magnitude, closeTo(1.0, 0.0001));
        }
      }
    });

    test(
      'TimerState, GameTimerManager, and FakeGameClock edge cases',
      () async {
        final clock = FakeGameClock();
        clock.setTime(DateTime.utc(2026, 3, 1));
        expect(clock.now(), DateTime.utc(2026, 3, 1));
        expect(
          () => clock.advance(const Duration(seconds: -1)),
          throwsA(isA<ArgumentError>()),
        );

        final manager = GameTimerManager(ticker: clock, clock: clock);
        final timer = manager.countdown(
          id: 't1',
          duration: const Duration(seconds: 10),
          tickInterval: const Duration(seconds: 1),
          emitTickEvents: true,
          autoStart: true,
        );
        expect(manager.get('t1'), same(timer));
        clock.advance(const Duration(seconds: 3));
        expect(timer.state.progress, closeTo(0.3, 0.001));
        expect(timer.state.toString(), contains('t1'));

        await manager.remove('t1');
        expect(manager.get('t1'), isNull);
        await manager.dispose();
      },
    );

    test('GameEventBus once timeout and error paths', () async {
      final bus = GameEventBus();
      await expectLater(
        bus.once<GameStartedEvent>(timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      final received = <GameStartedEvent>[];
      final sub = bus.on<GameStartedEvent>(received.add);
      sub.pause();
      expect(sub.isPaused, isTrue);
      sub.resume();
      sub.onData((event) => received.add(event));
      bus.emit(GameStartedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      await sub.cancel();
      await bus.dispose();
    });

    test(
      'covers GameModule defaults, GameStatus, GameException, NoopAudio, and extra branches',
      () async {
        // GameModule default hooks
        final minimal = _MinimalModule();
        final game = GameForge(modules: [minimal]);
        await game.initialize();
        game.start();
        game.pause();
        game.resume();
        game.complete();
        game.restart();
        expect(minimal.toSaveData(), isNull);
        await minimal.fromSaveData(const {});
        await game.dispose();

        // GameStatus & GameException
        expect(
          GameStatus.ready.allowedNextStatuses,
          contains(GameStatus.running),
        );
        final ex = GameException('oops', cause: StateError('inner'));
        expect(ex.toString(), contains('inner'));

        // NoopGameAudioService
        final noop = NoopGameAudioService();
        await noop.initialize();
        await noop.preload(['a']);
        await noop.playMusic('m');
        await noop.pauseMusic();
        await noop.resumeMusic();
        await noop.stopMusic();
        await noop.playSfx('s');
        await noop.setMasterVolume(0.5);
        await noop.setMusicVolume(0.4);
        await noop.setSfxVolume(0.3);
        await noop.mute();
        await noop.unmute();
        await noop.toggleMute();
        await noop.setMusicMuted(true);
        await noop.setSfxMuted(true);
        expect(noop.settings.isSfxMuted, isTrue);
        await noop.dispose();

        // GameSerialization DateTime/Duration normalization & unsupported error
        final normalized = GameSerialization.normalizeMap({
          'dt': DateTime.utc(2026, 1, 2),
          'dur': const Duration(seconds: 5),
        });
        expect(normalized['dur'], 5000000);
        expect(
          () => GameSerialization.normalizeMap({'bad': Object()}),
          throwsA(isA<CorruptSaveDataException>()),
        );
        expect(
          () => GameSerialization.encodeJson({'bad': Object()}),
          throwsA(isA<PersistenceException>()),
        );

        // TimerState equality, Stopwatch/Periodic reset, and SystemGameTicker
        const ts1 = TimerState(
          id: 't',
          status: TimerStatus.idle,
          elapsed: Duration.zero,
          totalDuration: Duration(seconds: 5),
          remaining: Duration(seconds: 5),
        );
        const ts2 = TimerState(
          id: 't',
          status: TimerStatus.idle,
          elapsed: Duration.zero,
          totalDuration: Duration(seconds: 5),
          remaining: Duration(seconds: 5),
        );
        expect(ts1, ts2);
        expect(ts1.hashCode, ts2.hashCode);
        expect(ts1.isRunning, isFalse);
        expect(ts1.isPaused, isFalse);
        expect(ts1.isCompleted, isFalse);

        final clock = FakeGameClock();
        final sw = StopwatchTimer(id: 'sw', ticker: clock, clock: clock);
        sw.start();
        clock.advance(const Duration(milliseconds: 500));
        sw.reset();
        expect(sw.elapsed, Duration.zero);
        await sw.dispose();

        final pt = PeriodicTimer(
          id: 'pt',
          period: const Duration(seconds: 1),
          ticker: clock,
          clock: clock,
        );
        pt.start();
        clock.advance(const Duration(seconds: 1));
        pt.reset();
        expect(pt.state.tickCount, 0);
        await pt.dispose();

        // Inventory clear, slotsFor, getItem, and allowSplitStacks: false
        final inv = InventoryManager(allowSplitStacks: false);
        inv.add(
          const GameItem(
            id: 'potion',
            name: 'Potion',
            quantity: 3,
            maxStackSize: 5,
          ),
        );
        expect(inv.getItem('potion')?.quantity, 3);
        expect(inv.slotsFor('potion'), hasLength(1));
        expect(
          () => inv.add(
            const GameItem(
              id: 'potion',
              name: 'Potion',
              quantity: 4,
              maxStackSize: 5,
            ),
          ),
          throwsA(isA<InventoryFullException>()),
        );
        inv.clear();
        expect(inv.state.isEmpty, isTrue);
        await inv.dispose();

        // AchievementManager helpers & reset
        final ach = AchievementManager(
          achievements: const [
            Achievement(id: 'a1', name: 'A1', targetValue: 5),
          ],
        );
        expect(ach.definitions, hasLength(1));
        expect(ach.allProgress, hasLength(1));
        ach.increment('a1', amount: 5);
        expect(ach.isUnlocked('a1'), isTrue);
        ach.reset();
        expect(ach.isUnlocked('a1'), isFalse);
        expect(
          () => ach.unlock('missing'),
          throwsA(isA<AchievementNotFoundException>()),
        );
        await ach.dispose();
      },
    );
  });
}
