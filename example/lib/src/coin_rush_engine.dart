import 'dart:async';
import 'dart:math' as math;

import 'package:gameforge/gameforge.dart';

/// Collectible coin entity inside the Coin Rush arena.
class ArenaCoin {
  ArenaCoin({
    required this.id,
    required this.x,
    required this.y,
    this.radius = 0.032,
    this.value = 10,
    this.isBonus = false,
  });

  final String id;
  final double x;
  final double y;
  final double radius;
  final int value;
  final bool isBonus;
}

/// Moving spiked obstacle inside the Coin Rush arena.
class ArenaObstacle {
  ArenaObstacle({
    required this.id,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.radius = 0.038,
  });

  final String id;
  double x;
  double y;
  double vx;
  double vy;
  final double radius;
}

/// Shop reward item that players can purchase using collected coins.
class ShopRewardOffer {
  const ShopRewardOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.costCoins,
  });

  final String id;
  final String title;
  final String description;
  final int costCoins;
}

/// Playable Coin Rush simulation powered by [GameForge].
///
/// Normalized arena coordinates span `[0.0, 1.0]` on both X and Y axes.
class CoinRushEngine {
  CoinRushEngine({
    required GameStorage storage,
    GameClock clock = const SystemGameClock(),
    GameTicker ticker = const SystemGameTicker(),
    math.Random? random,
  }) : _random = random ?? math.Random(),
       game = GameForge(
         config: GameConfig(
           initialLives: 3,
           maxLives: 5,
           initialHealth: 1,
           maxHealth: 1,
           initialScore: 0,
           invincibilityDuration: const Duration(seconds: 2),
           levelConfigs: _buildLevels(),
           saveKey: 'coin_rush_profile',
           saveVersion: 1,
         ),
         storage: storage,
         clock: clock,
         ticker: ticker,
         achievements: [
           Achievement(
             id: 'first_coin',
             name: 'First Sparkle',
             description: 'Collect your first coin.',
             targetValue: 1,
             reward: GameReward.coins(15, id: 'ach_first_coin', oneTime: true),
           ),
           Achievement(
             id: 'century_scorer',
             name: 'Century Rush',
             description: 'Reach 100 points in Coin Rush.',
             targetValue: 100,
             reward: GameReward.coins(25, id: 'ach_century', oneTime: true),
           ),
           Achievement(
             id: 'level_clearer',
             name: 'Trailblazer',
             description: 'Complete your first level.',
             targetValue: 1,
             reward: GameReward.points(50, id: 'ach_clearer', oneTime: true),
           ),
         ],
       );

  static const List<ShopRewardOffer> shopOffers = [
    ShopRewardOffer(
      id: 'extra_life',
      title: 'Extra Heart (+1 Life)',
      description: 'Restores 1 player life (up to max 5).',
      costCoins: 20,
    ),
    ShopRewardOffer(
      id: 'speed_charm',
      title: 'Turbo Boots Item',
      description: 'Adds +15% player speed for the run.',
      costCoins: 30,
    ),
    ShopRewardOffer(
      id: 'score_boost',
      title: 'Golden Multiplier (2.0x)',
      description: 'Activates a 2x score multiplier for collected coins.',
      costCoins: 35,
    ),
  ];

  static List<LevelConfig> _buildLevels() {
    return const [
      LevelConfig(
        id: 'level_1',
        number: 1,
        name: 'Meadow Dash',
        unlockedByDefault: true,
        metadata: {'targetCoins': 6, 'durationSeconds': 35, 'obstacles': 2},
      ),
      LevelConfig(
        id: 'level_2',
        number: 2,
        name: 'Vault Crossing',
        prerequisiteIds: ['level_1'],
        metadata: {'targetCoins': 10, 'durationSeconds': 40, 'obstacles': 3},
      ),
      LevelConfig(
        id: 'level_3',
        number: 3,
        name: 'Inferno Sprint',
        prerequisiteIds: ['level_2'],
        metadata: {'targetCoins': 14, 'durationSeconds': 45, 'obstacles': 4},
      ),
      LevelConfig(
        id: 'level_4',
        number: 4,
        name: 'Crown Gauntlet',
        prerequisiteIds: ['level_3'],
        metadata: {'targetCoins': 18, 'durationSeconds': 50, 'obstacles': 5},
      ),
    ];
  }

  /// Underlying [GameForge] controller managing all gameplay systems.
  final GameForge game;
  final math.Random _random;

  final List<ArenaCoin> coins = [];
  final List<ArenaObstacle> obstacles = [];
  final List<String> recentEvents = [];

  double playerX = 0.5;
  double playerY = 0.5;
  final double playerRadius = 0.04;
  int levelCoinsCollected = 0;

  CountdownTimer? _levelTimer;
  StreamSubscription<GameEvent>? _eventSub;
  final List<StreamSubscription<Object?>> _inputSubs = [];
  InputVector2D _inputVelocity = InputVector2D.zero;
  double? _targetX;
  double? _targetY;
  int _spawnSequence = 0;
  bool _hasLoadedSavedProgress = false;

  /// Active level countdown timer.
  CountdownTimer get levelTimer => _levelTimer!;

  /// Number of coins required to clear the current level.
  int get currentLevelTargetCoins =>
      (game.levels.currentLevel.metadata['targetCoins'] as int?) ?? 6;

  /// Initializes [GameForge], restores persisted progress if present, and
  /// prepares the active level entities.
  Future<void> initialize() async {
    await game.initialize();
    _eventSub = game.events.on<GameEvent>((event) {
      final label = switch (event) {
        ScoreChangedEvent(:final newScore, :final delta) =>
          'Score ${delta >= 0 ? '+' : ''}$delta -> $newScore',
        DamageTakenEvent(:final wasBlockedByInvincibility) =>
          wasBlockedByInvincibility
              ? 'Shielded from obstacle!'
              : 'Hit obstacle (-1 life)',
        LevelCompletedEvent(:final levelId, :final stars) =>
          'Cleared $levelId ($stars★)!',
        AchievementUnlockedEvent(:final achievement) =>
          'Achievement: ${achievement.name}!',
        RewardGrantedEvent(:final reward) =>
          'Reward: ${reward.title ?? reward.type.name}',
        _ => null,
      };
      if (label != null) {
        recentEvents.insert(0, label);
        if (recentEvents.length > 12) {
          recentEvents.removeLast();
        }
      }
    });

    _hasLoadedSavedProgress = await game.load();
    _bindInputListeners();
    _setupLevelEntities();
  }

  /// Whether a saved profile was loaded on startup.
  bool get hasLoadedSavedProgress => _hasLoadedSavedProgress;

  void _bindInputListeners() {
    _inputSubs.addAll([
      game.input.on<JoystickInputEvent>().listen((event) {
        _inputVelocity = event.isActive ? event.offset : InputVector2D.zero;
        _targetX = null;
        _targetY = null;
      }),
      game.input.on<TapInputEvent>().listen((event) {
        _targetX = event.position.x.clamp(0.05, 0.95);
        _targetY = event.position.y.clamp(0.05, 0.95);
      }),
      game.input.on<DragInputEvent>().listen((event) {
        if (event.phase == DragPhase.start || event.phase == DragPhase.update) {
          _targetX = event.position.x.clamp(0.05, 0.95);
          _targetY = event.position.y.clamp(0.05, 0.95);
        }
      }),
      game.input.on<KeyInputEvent>().listen((_) => _recomputeKeyboardVector()),
    ]);
  }

  void _recomputeKeyboardVector() {
    var dx = 0.0;
    var dy = 0.0;
    final keys = game.input.pressedKeys;
    if (keys.contains('Arrow Left') ||
        keys.contains('A') ||
        keys.contains('a')) {
      dx -= 1;
    }
    if (keys.contains('Arrow Right') ||
        keys.contains('D') ||
        keys.contains('d')) {
      dx += 1;
    }
    if (keys.contains('Arrow Up') || keys.contains('W') || keys.contains('w')) {
      dy -= 1;
    }
    if (keys.contains('Arrow Down') ||
        keys.contains('S') ||
        keys.contains('s')) {
      dy += 1;
    }
    _inputVelocity = InputVector2D(dx, dy).normalized;
    if (_inputVelocity != InputVector2D.zero) {
      _targetX = null;
      _targetY = null;
    }
  }

  /// Starts or restarts the active level and countdown timer.
  void startRun() {
    if (game.status == GameStatus.ready) {
      game.start();
    } else if (game.status == GameStatus.gameOver ||
        game.status == GameStatus.completed) {
      game.restart(autoStart: true);
    } else if (game.status == GameStatus.paused) {
      game.resume();
    }
    _setupLevelEntities();
    _levelTimer?.start();
  }

  /// Switches to an unlocked level by [levelId] and prepares the arena.
  Future<void> selectLevel(String levelId) async {
    game.levels.selectById(levelId);
    if (game.status == GameStatus.completed ||
        game.status == GameStatus.gameOver) {
      game.restart(autoStart: true);
      game.levels.selectById(levelId);
    } else if (game.status == GameStatus.ready) {
      game.start();
    }
    _setupLevelEntities();
    _levelTimer?.start();
    await game.save();
  }

  /// Purchases a [ShopRewardOffer] by spending coins from [RewardManager].
  Future<bool> purchaseOffer(ShopRewardOffer offer) async {
    if (game.rewards.coinBalance < offer.costCoins) {
      return false;
    }
    if (offer.id == 'extra_life') {
      if (game.health.lives >= (game.config.maxLives ?? 5)) {
        return false;
      }
      game.rewards.spendCoins(offer.costCoins, reason: offer.id);
      game.health.addLife();
    } else if (offer.id == 'speed_charm') {
      game.rewards.spendCoins(offer.costCoins, reason: offer.id);
      game.inventory.add(
        const GameItem(
          id: 'turbo_boots',
          name: 'Turbo Boots',
          description: '+15% movement speed',
          type: 'equipment',
        ),
      );
    } else if (offer.id == 'score_boost') {
      game.rewards.spendCoins(offer.costCoins, reason: offer.id);
      game.score.setMultiplier(2.0);
    }
    await game.save();
    return true;
  }

  /// Advances the arena simulation by [dtSeconds] seconds.
  void step(double dtSeconds) {
    if (game.status != GameStatus.running) {
      return;
    }
    final dt = dtSeconds.clamp(0.0, 0.05);
    final charmCount = game.inventory.quantityOf('turbo_boots');
    final speed = 0.52 * (1.0 + math.min(charmCount, 3) * 0.15);

    if (_inputVelocity != InputVector2D.zero) {
      playerX = (playerX + _inputVelocity.x * speed * dt).clamp(0.05, 0.95);
      playerY = (playerY + _inputVelocity.y * speed * dt).clamp(0.05, 0.95);
    } else if (_targetX != null && _targetY != null) {
      final dx = _targetX! - playerX;
      final dy = _targetY! - playerY;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 0.015) {
        _targetX = null;
        _targetY = null;
      } else {
        final move = math.min(dist, speed * dt);
        playerX = (playerX + (dx / dist) * move).clamp(0.05, 0.95);
        playerY = (playerY + (dy / dist) * move).clamp(0.05, 0.95);
      }
    }

    // Move obstacles and bounce off walls.
    for (final obstacle in obstacles) {
      obstacle.x += obstacle.vx * dt;
      obstacle.y += obstacle.vy * dt;
      if (obstacle.x < 0.06 || obstacle.x > 0.94) {
        obstacle.vx = -obstacle.vx;
        obstacle.x = obstacle.x.clamp(0.06, 0.94);
      }
      if (obstacle.y < 0.06 || obstacle.y > 0.94) {
        obstacle.vy = -obstacle.vy;
        obstacle.y = obstacle.y.clamp(0.06, 0.94);
      }

      final dist = _distance(playerX, playerY, obstacle.x, obstacle.y);
      if (dist < playerRadius + obstacle.radius) {
        game.score.resetCombo();
        game.health.takeDamage(1, source: 'obstacle');
        if (game.status == GameStatus.gameOver) {
          _levelTimer?.stop();
          unawaited(game.save());
          return;
        }
      }
    }

    // Collect coins on overlap.
    for (var i = coins.length - 1; i >= 0; i--) {
      final coin = coins[i];
      if (_distance(playerX, playerY, coin.x, coin.y) <
          playerRadius + coin.radius) {
        coins.removeAt(i);
        levelCoinsCollected += 1;
        game.score.incrementCombo();
        game.score.add(coin.value);
        game.rewards.grant(GameReward.coins(coin.isBonus ? 5 : 2));
        game.inventory.add(
          GameItem(
            id: 'coin',
            name: 'Gold Coin',
            type: 'currency',
            quantity: coin.isBonus ? 5 : 2,
          ),
        );
        game.achievements.increment('first_coin');
        game.achievements.setProgress(
          'century_scorer',
          game.score.currentScore,
        );

        if (levelCoinsCollected >= currentLevelTargetCoins) {
          _handleLevelCleared();
          return;
        }
        _spawnCoin();
      }
    }
  }

  void _handleLevelCleared() {
    _levelTimer?.stop();
    final remaining = _levelTimer?.remaining ?? Duration.zero;
    final stars = remaining >= const Duration(seconds: 20)
        ? 3
        : (remaining >= const Duration(seconds: 10) ? 2 : 1);
    game.levels.complete(
      levelId: game.levels.currentLevelId,
      stars: stars,
      score: game.score.currentScore,
    );
    game.achievements.increment('level_clearer');
    final next = game.levels.next();
    if (next == null) {
      game.complete();
    } else {
      _setupLevelEntities();
      _levelTimer?.start();
    }
    unawaited(game.save());
  }

  void _setupLevelEntities() {
    playerX = 0.5;
    playerY = 0.5;
    _targetX = null;
    _targetY = null;
    levelCoinsCollected = 0;
    coins.clear();
    obstacles.clear();

    final meta = game.levels.currentLevel.metadata;
    final obstacleCount = (meta['obstacles'] as int?) ?? 2;
    final seconds = (meta['durationSeconds'] as int?) ?? 35;

    final existingTimer = _levelTimer;
    if (existingTimer != null) {
      unawaited(game.timers.remove(existingTimer.id));
    }
    _levelTimer = game.timers.countdown(
      id: 'level_countdown_${++_spawnSequence}',
      duration: Duration(seconds: seconds),
      tickInterval: const Duration(milliseconds: 100),
      onComplete: () {
        if (game.status == GameStatus.running) {
          game.triggerGameOver(reason: 'time_up');
          unawaited(game.save());
        }
      },
    );

    for (var i = 0; i < 4; i++) {
      _spawnCoin();
    }
    for (var i = 0; i < obstacleCount; i++) {
      final angle = (i + 1) * 1.3;
      final speed = 0.22 + (i * 0.05);
      obstacles.add(
        ArenaObstacle(
          id: 'obs_$i',
          x: i.isEven ? 0.16 : 0.84,
          y: 0.16 + (i * 0.18).clamp(0.0, 0.68),
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
        ),
      );
    }
  }

  void _spawnCoin() {
    var x = 0.12 + _random.nextDouble() * 0.76;
    var y = 0.12 + _random.nextDouble() * 0.76;
    if (_distance(x, y, playerX, playerY) < 0.16) {
      x = playerX > 0.5 ? 0.2 : 0.8;
      y = playerY > 0.5 ? 0.2 : 0.8;
    }
    final isBonus = _random.nextDouble() < 0.2;
    coins.add(
      ArenaCoin(
        id: 'coin_${++_spawnSequence}',
        x: x,
        y: y,
        value: isBonus ? 25 : 10,
        isBonus: isBonus,
      ),
    );
  }

  double _distance(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Disposes subscriptions and the underlying [GameForge] instance.
  Future<void> dispose() async {
    final gameDisposeFuture = game.dispose();
    await _eventSub?.cancel();
    for (final sub in _inputSubs) {
      await sub.cancel();
    }
    _inputSubs.clear();
    await gameDisposeFuture;
  }
}
