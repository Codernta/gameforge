import 'package:meta/meta.dart';

import '../core/game_exception.dart';

/// Configuration rules governing [ScoreManager] calculations and boundaries.
@immutable
class ScoreRules {
  /// Creates [ScoreRules].
  const ScoreRules({
    this.initialScore = 0,
    this.allowNegativeScore = false,
    this.minScore,
    this.maxScore,
    this.clampOnOverflow = false,
    this.clampBelowMin = true,
    this.comboMultiplierStep = 0.1,
    this.maxComboMultiplier,
  });

  /// Maximum safe integer value for cross-platform score arithmetic.
  static const int maxSafeScore = 9007199254740991;

  /// Minimum safe integer value for cross-platform score arithmetic.
  static const int minSafeScore = -9007199254740991;

  /// Starting score used upon initialization and [ScoreManager.reset].
  final int initialScore;

  /// Whether negative score values are permitted.
  final bool allowNegativeScore;

  /// Explicit lower bound; defaults to `0` when [allowNegativeScore] is `false`.
  final int? minScore;

  /// Explicit upper bound; defaults to [maxSafeScore] when omitted.
  final int? maxScore;

  /// If `true`, values exceeding [effectiveMaxScore] are clamped rather than
  /// throwing [ScoreValidationException].
  final bool clampOnOverflow;

  /// If `true`, subtraction below [effectiveMinScore] clamps at the minimum;
  /// otherwise [ScoreValidationException] is thrown.
  final bool clampBelowMin;

  /// Multiplier increment added per combo step (`1.0 + comboCount * step`).
  final double comboMultiplierStep;

  /// Optional ceiling on the combo multiplier.
  final double? maxComboMultiplier;

  /// Effective minimum permitted score derived from configuration.
  int get effectiveMinScore =>
      minScore ?? (allowNegativeScore ? minSafeScore : 0);

  /// Effective maximum permitted score derived from configuration.
  int get effectiveMaxScore => maxScore ?? maxSafeScore;

  /// Validates the consistency of this rules configuration.
  void validate() {
    if (effectiveMinScore > effectiveMaxScore) {
      throw GameConfigurationException(
        'ScoreRules minScore ($effectiveMinScore) cannot exceed '
        'maxScore ($effectiveMaxScore).',
      );
    }
    if (initialScore < effectiveMinScore || initialScore > effectiveMaxScore) {
      throw GameConfigurationException(
        'ScoreRules initialScore ($initialScore) must be within '
        '[$effectiveMinScore, $effectiveMaxScore].',
      );
    }
    if (!comboMultiplierStep.isFinite || comboMultiplierStep < 0) {
      throw GameConfigurationException(
        'ScoreRules comboMultiplierStep ($comboMultiplierStep) must be finite '
        'and non-negative.',
      );
    }
    if (maxComboMultiplier != null &&
        (!maxComboMultiplier!.isFinite || maxComboMultiplier! < 1.0)) {
      throw GameConfigurationException(
        'ScoreRules maxComboMultiplier ($maxComboMultiplier) must be >= 1.0.',
      );
    }
  }

  /// Creates a copy of these rules with the provided overrides.
  ScoreRules copyWith({
    int? initialScore,
    bool? allowNegativeScore,
    int? minScore,
    int? maxScore,
    bool? clampOnOverflow,
    bool? clampBelowMin,
    double? comboMultiplierStep,
    double? maxComboMultiplier,
  }) {
    return ScoreRules(
      initialScore: initialScore ?? this.initialScore,
      allowNegativeScore: allowNegativeScore ?? this.allowNegativeScore,
      minScore: minScore ?? this.minScore,
      maxScore: maxScore ?? this.maxScore,
      clampOnOverflow: clampOnOverflow ?? this.clampOnOverflow,
      clampBelowMin: clampBelowMin ?? this.clampBelowMin,
      comboMultiplierStep: comboMultiplierStep ?? this.comboMultiplierStep,
      maxComboMultiplier: maxComboMultiplier ?? this.maxComboMultiplier,
    );
  }
}

/// Immutable snapshot of player score, high score, and active multipliers.
@immutable
class ScoreState {
  /// Creates a [ScoreState].
  const ScoreState({
    required this.currentScore,
    required this.highScore,
    this.multiplier = 1.0,
    this.comboCount = 0,
    this.comboMultiplier = 1.0,
    this.lastDelta = 0,
  });

  /// Current active score.
  final int currentScore;

  /// Highest score recorded across resets or restored saves.
  final int highScore;

  /// Explicit score multiplier applied to [ScoreManager.add].
  final double multiplier;

  /// Current combo streak count.
  final int comboCount;

  /// Multiplier contributed by the current [comboCount].
  final double comboMultiplier;

  /// Delta applied by the most recent score change.
  final int lastDelta;

  /// Combined multiplier applied when adding points.
  double get effectiveMultiplier => multiplier * comboMultiplier;

  /// Returns a modified copy of this state.
  ScoreState copyWith({
    int? currentScore,
    int? highScore,
    double? multiplier,
    int? comboCount,
    double? comboMultiplier,
    int? lastDelta,
  }) {
    return ScoreState(
      currentScore: currentScore ?? this.currentScore,
      highScore: highScore ?? this.highScore,
      multiplier: multiplier ?? this.multiplier,
      comboCount: comboCount ?? this.comboCount,
      comboMultiplier: comboMultiplier ?? this.comboMultiplier,
      lastDelta: lastDelta ?? this.lastDelta,
    );
  }

  /// Serializes this state into a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'currentScore': currentScore,
    'highScore': highScore,
    'multiplier': multiplier,
    'comboCount': comboCount,
    'comboMultiplier': comboMultiplier,
    'lastDelta': lastDelta,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScoreState &&
        other.currentScore == currentScore &&
        other.highScore == highScore &&
        other.multiplier == multiplier &&
        other.comboCount == comboCount &&
        other.comboMultiplier == comboMultiplier &&
        other.lastDelta == lastDelta;
  }

  @override
  int get hashCode => Object.hash(
    currentScore,
    highScore,
    multiplier,
    comboCount,
    comboMultiplier,
    lastDelta,
  );

  @override
  String toString() =>
      'ScoreState(currentScore: $currentScore, highScore: $highScore, '
      'multiplier: $multiplier, comboCount: $comboCount, '
      'comboMultiplier: $comboMultiplier)';
}
