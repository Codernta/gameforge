import 'dart:async';
import 'dart:math' as math;

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../persistence/serialization.dart';
import '../utils/game_clock.dart';
import 'damage_event.dart';
import 'health_state.dart';

/// Manages player health, lives, damage, healing, respawns, and invincibility
/// windows.
class HealthManager extends GameModule {
  /// Creates a [HealthManager] using [config].
  HealthManager({
    HealthConfig config = const HealthConfig(),
    GameEventBus? eventBus,
    GameClock clock = const SystemGameClock(),
    void Function(HealthState state)? onStateChanged,
  }) : _config = config,
       _eventBus = eventBus,
       _clock = clock,
       _onStateChanged = onStateChanged {
    _config.validate();
    _state = HealthState(
      currentHealth: _config.effectiveInitialHealth,
      maxHealth: _config.maxHealth,
      lives: _config.supportsLives ? _config.initialLives : 0,
      maxLives: _config.maxLives,
      supportsLives: _config.supportsLives,
    );
  }

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'health';

  final HealthConfig _config;
  GameEventBus? _eventBus;
  GameClock _clock;
  final void Function(HealthState state)? _onStateChanged;
  final StreamController<HealthState> _stateController =
      StreamController<HealthState>.broadcast();

  late HealthState _state;
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Configuration for this health manager.
  HealthConfig get config => _config;

  /// Current [HealthState] snapshot with real-time invincibility evaluation.
  HealthState get state {
    _syncInvincibilityExpiration();
    return _state;
  }

  /// Current health value.
  double get currentHealth => _state.currentHealth;

  /// Maximum health capacity.
  double get maxHealth => _state.maxHealth;

  /// Remaining lives.
  int get lives => _state.lives;

  /// Whether the player is permanently dead.
  bool get isDead => _state.isDead;

  /// Whether the player is alive.
  bool get isAlive => _state.isAlive;

  /// Whether temporary invincibility is currently active according to [GameClock].
  bool get isInvincible {
    _syncInvincibilityExpiration();
    return _state.isInvincible;
  }

  /// Broadcast stream emitting whenever health, lives, or invincibility change.
  Stream<HealthState> get stream => _stateController.stream;

  @override
  void onInitialize(GameModuleContext context) {
    _eventBus ??= context.events;
    _clock = context.clock;
  }

  @override
  void onReset() {
    reset();
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Applies [amount] damage to the player, returning the actual health lost.
  ///
  /// Throws [HealthValidationException] if [amount] is negative or non-finite.
  double takeDamage(
    num amount, {
    String? source,
    bool ignoreInvincibility = false,
  }) {
    _ensureNotDisposed();
    final damage = amount.toDouble();
    if (!damage.isFinite || damage < 0) {
      throw HealthValidationException(
        'Damage amount must be finite and non-negative (got $amount).',
      );
    }
    if (damage == 0 || isDead) {
      return 0.0;
    }

    final currentlyInvincible = isInvincible;
    if (currentlyInvincible && !ignoreInvincibility) {
      _emitEvent(
        DamageTakenEvent(
          requestedAmount: damage,
          appliedAmount: 0.0,
          previousHealth: _state.currentHealth,
          newHealth: _state.currentHealth,
          source: source,
          wasBlockedByInvincibility: true,
          timestamp: _clock.now(),
        ),
      );
      return 0.0;
    }

    final previousHealth = _state.currentHealth;
    final clampedNewHealth = math.max(0.0, previousHealth - damage);
    final applied = previousHealth - clampedNewHealth;
    final now = _clock.now();

    _state = _state.copyWith(currentHealth: clampedNewHealth);
    _emitState();
    _emitEvent(
      DamageTakenEvent(
        requestedAmount: damage,
        appliedAmount: applied,
        previousHealth: previousHealth,
        newHealth: clampedNewHealth,
        source: source,
        timestamp: now,
      ),
    );

    if (clampedNewHealth <= 0.0) {
      _handleHealthDepleted(now);
    } else if (_config.invincibilityOnDamage &&
        _config.invincibilityDuration != null &&
        _config.invincibilityDuration! > Duration.zero) {
      grantInvincibility(_config.invincibilityDuration!);
    }

    return applied;
  }

  /// Restores up to [amount] health (clamped at [maxHealth]), returning the
  /// actual amount healed.
  ///
  /// Does nothing when the player is permanently dead unless [allowWhenDead]
  /// is `true`.
  double heal(num amount, {bool allowWhenDead = false}) {
    _ensureNotDisposed();
    final healAmount = amount.toDouble();
    if (!healAmount.isFinite || healAmount < 0) {
      throw HealthValidationException(
        'Heal amount must be finite and non-negative (got $amount).',
      );
    }
    if (healAmount == 0 || (isDead && !allowWhenDead)) {
      return 0.0;
    }

    final previousHealth = _state.currentHealth;
    final nextHealth = math.min(_state.maxHealth, previousHealth + healAmount);
    final applied = nextHealth - previousHealth;

    if (applied <= 0) {
      return 0.0;
    }

    _state = _state.copyWith(currentHealth: nextHealth);
    _emitState();
    _emitEvent(
      HealedEvent(
        requestedAmount: healAmount,
        appliedAmount: applied,
        previousHealth: previousHealth,
        newHealth: nextHealth,
        timestamp: _clock.now(),
      ),
    );
    return applied;
  }

  /// Grants [count] extra lives (clamped at [HealthConfig.maxLives] if set).
  void addLife({int count = 1}) {
    _ensureNotDisposed();
    if (count <= 0) {
      throw HealthValidationException(
        'Life count to add must be positive (got $count).',
      );
    }
    if (!_state.supportsLives) {
      throw const HealthValidationException(
        'Cannot add lives when HealthConfig.supportsLives is false.',
      );
    }

    final previousLives = _state.lives;
    var nextLives = previousLives + count;
    if (_state.maxLives != null) {
      nextLives = math.min(nextLives, _state.maxLives!);
    }
    if (nextLives == previousLives) {
      return;
    }

    _state = _state.copyWith(lives: nextLives);
    _emitState();
    _emitEvent(
      LifeAddedEvent(
        previousLives: previousLives,
        newLives: nextLives,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Decrements one life directly.
  ///
  /// When lives remain and [resetHealthOnSurvive] is `true`, health resets to
  /// [HealthConfig.effectiveRespawnHealth]. When lives reach zero, health is
  /// set to `0.0` and [PlayerDiedEvent] is emitted.
  void loseLife({bool resetHealthOnSurvive = true}) {
    _ensureNotDisposed();
    if (!_state.supportsLives) {
      throw const HealthValidationException(
        'Cannot lose lives when HealthConfig.supportsLives is false.',
      );
    }
    if (_state.lives <= 0) {
      return;
    }

    final now = _clock.now();
    final previousLives = _state.lives;
    final remainingLives = previousLives - 1;
    final survived = remainingLives > 0;
    final nextHealth = survived
        ? (resetHealthOnSurvive
              ? math.min(_state.maxHealth, _config.effectiveRespawnHealth)
              : _state.currentHealth)
        : 0.0;

    _state = _state.copyWith(lives: remainingLives, currentHealth: nextHealth);
    _emitState();
    _emitEvent(
      LifeLostEvent(
        previousLives: previousLives,
        remainingLives: remainingLives,
        timestamp: now,
      ),
    );

    if (survived) {
      if (resetHealthOnSurvive) {
        _emitEvent(
          PlayerRespawnedEvent(
            restoredHealth: nextHealth,
            remainingLives: remainingLives,
            timestamp: now,
          ),
        );
      }
      if (_config.invincibilityOnRespawn &&
          _config.invincibilityDuration != null &&
          _config.invincibilityDuration! > Duration.zero) {
        grantInvincibility(_config.invincibilityDuration!);
      }
    } else {
      _emitEvent(PlayerDiedEvent(remainingLives: 0, timestamp: now));
    }
  }

  /// Activates temporary invincibility for [duration].
  void grantInvincibility(Duration duration) {
    _ensureNotDisposed();
    if (duration < Duration.zero) {
      throw const HealthValidationException(
        'Invincibility duration cannot be negative.',
      );
    }
    if (duration == Duration.zero) {
      clearInvincibility();
      return;
    }
    final now = _clock.now();
    final until = now.add(duration);
    _state = _state.copyWith(invincibleUntil: until, isInvincible: true);
    _emitState();
    _emitEvent(
      InvincibilityStartedEvent(
        duration: duration,
        until: until,
        timestamp: now,
      ),
    );
  }

  /// Immediately clears any active invincibility window.
  void clearInvincibility() {
    _ensureNotDisposed();
    if (!_state.isInvincible && _state.invincibleUntil == null) {
      return;
    }
    _state = _state.copyWith(clearInvincibleUntil: true, isInvincible: false);
    _emitState();
    _emitEvent(InvincibilityEndedEvent(timestamp: _clock.now()));
  }

  /// Updates [maxHealth] dynamically, optionally healing to full capacity.
  void setMaxHealth(num maxHealth, {bool healToFull = false}) {
    _ensureNotDisposed();
    final nextMax = maxHealth.toDouble();
    if (!nextMax.isFinite || nextMax <= 0) {
      throw HealthValidationException(
        'maxHealth must be finite and greater than zero (got $maxHealth).',
      );
    }
    final nextCurrent = healToFull
        ? nextMax
        : math.min(_state.currentHealth, nextMax);
    _state = _state.copyWith(maxHealth: nextMax, currentHealth: nextCurrent);
    _emitState();
  }

  /// Revives a dead player or sets explicit [health] and [lives].
  void revive({double? health, int? lives}) {
    _ensureNotDisposed();
    final nextHealth = health ?? _state.maxHealth;
    if (!nextHealth.isFinite ||
        nextHealth <= 0 ||
        nextHealth > _state.maxHealth) {
      throw HealthValidationException(
        'Revive health ($nextHealth) must be within (0, ${_state.maxHealth}].',
      );
    }
    final nextLives = _state.supportsLives
        ? (lives ?? math.max(1, _config.initialLives))
        : 0;
    if (nextLives < 0 ||
        (_state.maxLives != null && nextLives > _state.maxLives!)) {
      throw HealthValidationException(
        'Invalid revive lives count: $nextLives.',
      );
    }

    _state = _state.copyWith(
      currentHealth: nextHealth,
      lives: nextLives,
      clearInvincibleUntil: true,
      isInvincible: false,
    );
    _emitState();
    _emitEvent(
      PlayerRespawnedEvent(
        restoredHealth: nextHealth,
        remainingLives: nextLives,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Resets health, lives, and invincibility back to initial configuration.
  void reset() {
    _ensureNotDisposed();
    _state = HealthState(
      currentHealth: _config.effectiveInitialHealth,
      maxHealth: _config.maxHealth,
      lives: _config.supportsLives ? _config.initialLives : 0,
      maxLives: _config.maxLives,
      supportsLives: _config.supportsLives,
    );
    _emitState();
  }

  @override
  Map<String, Object?> toSaveData() {
    _syncInvincibilityExpiration();
    return _state.toJson();
  }

  @override
  void fromSaveData(Map<String, Object?> data) {
    _ensureNotDisposed();
    final currentHealth = GameSerialization.readDouble(data, 'currentHealth');
    final maxHealth = GameSerialization.readDouble(data, 'maxHealth');
    final lives = GameSerialization.readInt(data, 'lives');
    final maxLivesRaw = data['maxLives'];
    final maxLives = maxLivesRaw == null
        ? null
        : GameSerialization.readInt(data, 'maxLives');
    final supportsLives = GameSerialization.readBool(
      data,
      'supportsLives',
      defaultValue: _config.supportsLives,
    );
    final untilStr = GameSerialization.readOptionalString(
      data,
      'invincibleUntil',
    );
    final invincibleUntil = untilStr == null
        ? null
        : DateTime.tryParse(untilStr);
    if (untilStr != null && invincibleUntil == null) {
      throw CorruptSaveDataException(
        'Invalid invincibleUntil timestamp: $untilStr.',
      );
    }

    if (maxHealth <= 0 || currentHealth < 0 || currentHealth > maxHealth) {
      throw SaveValidationException(
        'Saved health ($currentHealth/$maxHealth) is invalid.',
      );
    }
    if (lives < 0 || (maxLives != null && lives > maxLives)) {
      throw SaveValidationException('Saved lives ($lives) is invalid.');
    }

    final activeInvincibility =
        invincibleUntil != null && _clock.now().isBefore(invincibleUntil);
    _state = HealthState(
      currentHealth: currentHealth,
      maxHealth: maxHealth,
      lives: lives,
      maxLives: maxLives,
      supportsLives: supportsLives,
      invincibleUntil: activeInvincibility ? invincibleUntil : null,
      isInvincible: activeInvincibility,
    );
    _emitState();
  }

  /// Releases resources owned by this manager.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _stateController.close();
  }

  void _handleHealthDepleted(DateTime now) {
    if (!_state.supportsLives) {
      _emitEvent(PlayerDiedEvent(remainingLives: 0, timestamp: now));
      return;
    }

    final previousLives = _state.lives;
    if (previousLives <= 0) {
      _emitEvent(PlayerDiedEvent(remainingLives: 0, timestamp: now));
      return;
    }

    final remainingLives = previousLives - 1;
    _state = _state.copyWith(lives: remainingLives);
    _emitState();
    _emitEvent(
      LifeLostEvent(
        previousLives: previousLives,
        remainingLives: remainingLives,
        timestamp: now,
      ),
    );

    if (remainingLives > 0 && _config.autoRespawnOnDeath) {
      final restored = math.min(
        _state.maxHealth,
        _config.effectiveRespawnHealth,
      );
      _state = _state.copyWith(currentHealth: restored);
      _emitState();
      _emitEvent(
        PlayerRespawnedEvent(
          restoredHealth: restored,
          remainingLives: remainingLives,
          timestamp: now,
        ),
      );
      if (_config.invincibilityOnRespawn &&
          _config.invincibilityDuration != null &&
          _config.invincibilityDuration! > Duration.zero) {
        grantInvincibility(_config.invincibilityDuration!);
      }
    } else if (remainingLives <= 0) {
      _emitEvent(PlayerDiedEvent(remainingLives: 0, timestamp: now));
    }
  }

  void _syncInvincibilityExpiration() {
    final until = _state.invincibleUntil;
    if (_state.isInvincible && until != null && !_clock.now().isBefore(until)) {
      _state = _state.copyWith(clearInvincibleUntil: true, isInvincible: false);
      _emitState();
      _emitEvent(InvincibilityEndedEvent(timestamp: _clock.now()));
    }
  }

  void _emitState() {
    _onStateChanged?.call(_state);
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _emitEvent(GameEvent event) {
    final bus = _eventBus;
    if (bus != null && !bus.isDisposed) {
      bus.emit(event);
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot use HealthManager after it has been disposed.',
      );
    }
  }
}
