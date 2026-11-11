import 'dart:async';
import 'dart:math' as math;

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../persistence/serialization.dart';
import '../utils/game_clock.dart';
import 'score_event.dart';
import 'score_state.dart';

/// Manages player score, high score, score multipliers, and combo streaks.
///
/// Can be used standalone or orchestrated automatically by [GameForge].
class ScoreManager extends GameModule {
  /// Creates a [ScoreManager] configured with [rules].
  ScoreManager({
    ScoreRules rules = const ScoreRules(),
    GameEventBus? eventBus,
    GameClock clock = const SystemGameClock(),
    int? initialHighScore,
    void Function(ScoreState state)? onStateChanged,
  }) : _rules = rules,
       _eventBus = eventBus,
       _clock = clock,
       _onStateChanged = onStateChanged {
    _rules.validate();
    final startScore = _rules.initialScore;
    final highScore = math.max(startScore, initialHighScore ?? startScore);
    _state = ScoreState(currentScore: startScore, highScore: highScore);
  }

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'score';

  final ScoreRules _rules;
  GameEventBus? _eventBus;
  GameClock _clock;
  final void Function(ScoreState state)? _onStateChanged;
  final StreamController<ScoreState> _stateController =
      StreamController<ScoreState>.broadcast();

  late ScoreState _state;
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Configuration rules governing score boundaries and combos.
  ScoreRules get rules => _rules;

  /// Current immutable [ScoreState].
  ScoreState get state => _state;

  /// Current active score.
  int get currentScore => _state.currentScore;

  /// Highest recorded score.
  int get highScore => _state.highScore;

  /// Active base multiplier.
  double get multiplier => _state.multiplier;

  /// Current combo streak count.
  int get comboCount => _state.comboCount;

  /// Multiplier contributed by the current combo streak.
  double get comboMultiplier => _state.comboMultiplier;

  /// Combined base and combo multiplier.
  double get effectiveMultiplier => _state.effectiveMultiplier;

  /// Broadcast stream emitting whenever [state] updates.
  Stream<ScoreState> get stream => _stateController.stream;

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

  /// Adds [points] to the current score, multiplied by [effectiveMultiplier]
  /// unless [applyMultiplier] is `false`.
  ///
  /// Throws [ScoreValidationException] if [points] is negative or overflows
  /// [ScoreRules.effectiveMaxScore] when [ScoreRules.clampOnOverflow] is
  /// `false`.
  int add(int points, {bool applyMultiplier = true}) {
    _ensureNotDisposed();
    if (points < 0) {
      throw ScoreValidationException(
        'Cannot add negative points ($points). Use subtract() instead.',
      );
    }

    final rawDelta = applyMultiplier
        ? (points * _state.effectiveMultiplier).round()
        : points;

    final nextScore = _checkedAdd(_state.currentScore, rawDelta);
    _updateScore(nextScore);
    return _state.currentScore;
  }

  /// Subtracts non-negative [points] from the current score.
  ///
  /// Clamps at [ScoreRules.effectiveMinScore] if [ScoreRules.clampBelowMin]
  /// is `true`; otherwise throws [ScoreValidationException].
  int subtract(int points) {
    _ensureNotDisposed();
    if (points < 0) {
      throw ScoreValidationException(
        'Cannot subtract negative points ($points).',
      );
    }

    final minScore = _rules.effectiveMinScore;
    final current = _state.currentScore;

    // Guard against signed integer underflow when current is near minSafeScore.
    final int nextScore;
    if (current - minScore < points) {
      if (_rules.clampBelowMin) {
        nextScore = minScore;
      } else {
        throw ScoreValidationException(
          'Subtracting $points from $current falls below minimum score '
          '$minScore.',
        );
      }
    } else {
      nextScore = current - points;
    }

    _updateScore(nextScore);
    return _state.currentScore;
  }

  /// Multiplies the current score by non-negative finite [factor].
  ///
  /// To configure a multiplier applied to subsequent [add] calls, use
  /// [setMultiplier].
  int multiply(num factor) {
    _ensureNotDisposed();
    final factorDouble = factor.toDouble();
    if (!factorDouble.isFinite || factorDouble < 0) {
      throw ScoreValidationException(
        'Score multiplication factor must be finite and non-negative '
        '(got $factor).',
      );
    }

    final product = _state.currentScore * factorDouble;
    if (!product.isFinite) {
      throw ScoreValidationException(
        'Multiplying score ${_state.currentScore} by $factor causes overflow.',
      );
    }

    final maxScore = _rules.effectiveMaxScore;
    final minScore = _rules.effectiveMinScore;
    final int nextScore;
    if (product > maxScore) {
      if (_rules.clampOnOverflow) {
        nextScore = maxScore;
      } else {
        throw ScoreValidationException(
          'Multiplying score ${_state.currentScore} by $factor exceeds '
          'maxScore ($maxScore).',
        );
      }
    } else if (product < minScore) {
      if (_rules.clampBelowMin) {
        nextScore = minScore;
      } else {
        throw ScoreValidationException(
          'Multiplying score ${_state.currentScore} by $factor falls below '
          'minScore ($minScore).',
        );
      }
    } else {
      nextScore = product.round();
    }

    _updateScore(nextScore);
    return _state.currentScore;
  }

  /// Sets the current score directly to [value].
  void setScore(int value) {
    _ensureNotDisposed();
    final minScore = _rules.effectiveMinScore;
    final maxScore = _rules.effectiveMaxScore;
    if (value < minScore || value > maxScore) {
      throw ScoreValidationException(
        'Score $value is outside allowed range [$minScore, $maxScore].',
      );
    }
    _updateScore(value);
  }

  /// Sets the base [multiplier] applied to future [add] calls.
  void setMultiplier(double multiplier) {
    _ensureNotDisposed();
    if (!multiplier.isFinite || multiplier < 0) {
      throw ScoreValidationException(
        'Multiplier must be finite and non-negative (got $multiplier).',
      );
    }
    final previous = _state.multiplier;
    if (previous == multiplier) {
      return;
    }
    _state = _state.copyWith(multiplier: multiplier, lastDelta: 0);
    _emitState();
    _emitEvent(
      ScoreMultiplierChangedEvent(
        previousMultiplier: previous,
        newMultiplier: multiplier,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Resets the base multiplier back to `1.0`.
  void resetMultiplier() => setMultiplier(1.0);

  /// Increments the active combo counter by [by] and recalculates
  /// [comboMultiplier].
  void incrementCombo({int by = 1}) {
    _ensureNotDisposed();
    if (by <= 0) {
      throw ScoreValidationException(
        'Combo increment must be greater than zero (got $by).',
      );
    }
    setCombo(_state.comboCount + by);
  }

  /// Sets the active combo count to [count] and updates [comboMultiplier].
  void setCombo(int count) {
    _ensureNotDisposed();
    if (count < 0) {
      throw ScoreValidationException(
        'Combo count must be non-negative (got $count).',
      );
    }
    final previous = _state.comboCount;
    var nextMultiplier = 1.0 + count * _rules.comboMultiplierStep;
    if (_rules.maxComboMultiplier != null) {
      nextMultiplier = math.min(nextMultiplier, _rules.maxComboMultiplier!);
    }
    if (previous == count && _state.comboMultiplier == nextMultiplier) {
      return;
    }
    _state = _state.copyWith(
      comboCount: count,
      comboMultiplier: nextMultiplier,
      lastDelta: 0,
    );
    _emitState();
    _emitEvent(
      ComboChangedEvent(
        previousCombo: previous,
        newCombo: count,
        comboMultiplier: nextMultiplier,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Resets the active combo streak back to zero (`1.0x`).
  void resetCombo() => setCombo(0);

  /// Resets score, multiplier, and combo to initial values.
  ///
  /// High score is preserved unless [resetHighScore] is `true`.
  void reset({bool resetHighScore = false}) {
    _ensureNotDisposed();
    final previousScore = _state.currentScore;
    final initial = _rules.initialScore;
    final nextHigh = resetHighScore
        ? initial
        : math.max(_state.highScore, initial);
    _state = ScoreState(currentScore: initial, highScore: nextHigh);
    _emitState();
    _emitEvent(
      ScoreResetEvent(
        previousScore: previousScore,
        resetScore: initial,
        highScoreReset: resetHighScore,
        timestamp: _clock.now(),
      ),
    );
  }

  @override
  Map<String, Object?> toSaveData() => _state.toJson();

  @override
  void fromSaveData(Map<String, Object?> data) {
    _ensureNotDisposed();
    final currentScore = GameSerialization.readInt(data, 'currentScore');
    final highScore = GameSerialization.readInt(data, 'highScore');
    final multiplier = GameSerialization.readDouble(
      data,
      'multiplier',
      defaultValue: 1.0,
    );
    final comboCount = GameSerialization.readInt(
      data,
      'comboCount',
      defaultValue: 0,
    );

    final minScore = _rules.effectiveMinScore;
    final maxScore = _rules.effectiveMaxScore;
    if (currentScore < minScore || currentScore > maxScore) {
      throw SaveValidationException(
        'Saved currentScore ($currentScore) is outside [$minScore, $maxScore].',
      );
    }
    if (highScore < currentScore || highScore > maxScore) {
      throw SaveValidationException(
        'Saved highScore ($highScore) is invalid for currentScore '
        '$currentScore and maxScore $maxScore.',
      );
    }
    if (!multiplier.isFinite || multiplier < 0) {
      throw SaveValidationException(
        'Saved score multiplier ($multiplier) is invalid.',
      );
    }
    if (comboCount < 0) {
      throw SaveValidationException(
        'Saved comboCount ($comboCount) must be non-negative.',
      );
    }

    var comboMult = 1.0 + comboCount * _rules.comboMultiplierStep;
    if (_rules.maxComboMultiplier != null) {
      comboMult = math.min(comboMult, _rules.maxComboMultiplier!);
    }

    _state = ScoreState(
      currentScore: currentScore,
      highScore: highScore,
      multiplier: multiplier,
      comboCount: comboCount,
      comboMultiplier: comboMult,
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

  int _checkedAdd(int base, int delta) {
    final maxScore = _rules.effectiveMaxScore;
    if (delta > maxScore - base) {
      if (_rules.clampOnOverflow) {
        return maxScore;
      }
      throw ScoreValidationException(
        'Adding $delta to $base exceeds maxScore ($maxScore).',
      );
    }
    return base + delta;
  }

  void _updateScore(int nextScore) {
    final previousScore = _state.currentScore;
    final previousHigh = _state.highScore;
    final delta = nextScore - previousScore;
    final nextHigh = math.max(previousHigh, nextScore);

    _state = _state.copyWith(
      currentScore: nextScore,
      highScore: nextHigh,
      lastDelta: delta,
    );
    _emitState();

    final now = _clock.now();
    if (delta != 0) {
      _emitEvent(
        ScoreChangedEvent(
          previousScore: previousScore,
          newScore: nextScore,
          delta: delta,
          highScore: nextHigh,
          timestamp: now,
        ),
      );
    }
    if (nextHigh > previousHigh) {
      _emitEvent(
        HighScoreAchievedEvent(
          previousHighScore: previousHigh,
          newHighScore: nextHigh,
          timestamp: now,
        ),
      );
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
        'Cannot use ScoreManager after it has been disposed.',
      );
    }
  }
}
