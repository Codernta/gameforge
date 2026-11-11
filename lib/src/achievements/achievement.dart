import 'package:meta/meta.dart';

import '../core/game_event.dart';
import '../core/game_exception.dart';
import '../rewards/reward.dart';

/// Read-only context passed to [AchievementCondition] implementations when
/// evaluating dynamic unlock conditions.
class AchievementEvaluationContext {
  /// Creates an [AchievementEvaluationContext].
  const AchievementEvaluationContext({
    required this.currentProgress,
    required this.targetValue,
    this.score,
    this.highScore,
    this.completedLevelsCount,
    this.totalCoinsEarned,
    this.customData = const {},
  });

  /// Current numeric progress recorded for the achievement being evaluated.
  final int currentProgress;

  /// Target progress value configured on the achievement.
  final int targetValue;

  /// Current score snapshot, if available.
  final int? score;

  /// Current high score snapshot, if available.
  final int? highScore;

  /// Number of completed levels, if available.
  final int? completedLevelsCount;

  /// Total coins earned, if available.
  final int? totalCoinsEarned;

  /// Additional arbitrary values supplied to [AchievementManager.evaluate].
  final Map<String, Object?> customData;
}

/// Extensible interface for custom achievement unlock conditions.
abstract interface class AchievementCondition {
  /// Returns `true` when the achievement should unlock under [context].
  bool isSatisfied(AchievementEvaluationContext context);

  /// Optionally computes an updated progress value from [context].
  ///
  /// Returns `null` when progress is tracked externally via `increment` or
  /// `setProgress`.
  int? computeProgress(AchievementEvaluationContext context) => null;
}

/// Default numeric threshold condition unlocking once `currentProgress >= targetValue`.
class ThresholdAchievementCondition implements AchievementCondition {
  /// Creates a [ThresholdAchievementCondition].
  const ThresholdAchievementCondition();

  @override
  bool isSatisfied(AchievementEvaluationContext context) =>
      context.currentProgress >= context.targetValue;

  @override
  int? computeProgress(AchievementEvaluationContext context) => null;
}

/// Callback-based [AchievementCondition] for concise custom unlock rules.
class PredicateAchievementCondition implements AchievementCondition {
  /// Creates a [PredicateAchievementCondition].
  const PredicateAchievementCondition(
    this._predicate, {
    int? Function(AchievementEvaluationContext context)? progressResolver,
  }) : _progressResolver = progressResolver;

  final bool Function(AchievementEvaluationContext context) _predicate;
  final int? Function(AchievementEvaluationContext context)? _progressResolver;

  @override
  bool isSatisfied(AchievementEvaluationContext context) => _predicate(context);

  @override
  int? computeProgress(AchievementEvaluationContext context) =>
      _progressResolver?.call(context);
}

/// Immutable achievement definition.
@immutable
class Achievement {
  /// Creates an [Achievement].
  const Achievement({
    required this.id,
    required this.name,
    this.description = '',
    this.targetValue = 1,
    this.condition = const ThresholdAchievementCondition(),
    this.reward,
    this.hidden = false,
    this.metadata = const {},
  });

  /// Unique achievement identifier.
  final String id;

  /// Display title of the achievement.
  final String name;

  /// Description shown to the player.
  final String description;

  /// Target progress required to complete this achievement (`>= 1`).
  final int targetValue;

  /// Condition determining when this achievement unlocks.
  final AchievementCondition condition;

  /// Optional reward granted automatically when unlocked.
  final GameReward? reward;

  /// Whether this achievement is hidden until unlocked.
  final bool hidden;

  /// Optional custom metadata.
  final Map<String, Object?> metadata;

  /// Validates invariants on this achievement definition.
  void validate() {
    if (id.trim().isEmpty) {
      throw const AchievementException('Achievement id cannot be empty.');
    }
    if (name.trim().isEmpty) {
      throw AchievementException('Achievement "$id" name cannot be empty.');
    }
    if (targetValue < 1) {
      throw AchievementException(
        'Achievement "$id" targetValue ($targetValue) must be >= 1.',
      );
    }
  }
}

/// Emitted whenever an achievement's progress value updates.
final class AchievementProgressEvent extends GameEvent {
  /// Creates an [AchievementProgressEvent].
  AchievementProgressEvent({
    required this.achievement,
    required this.previousValue,
    required this.currentValue,
    required this.targetValue,
    super.timestamp,
  });

  /// Definition of the updated achievement.
  final Achievement achievement;

  /// Progress value prior to update.
  final int previousValue;

  /// Updated progress value.
  final int currentValue;

  /// Target threshold for unlocking.
  final int targetValue;
}

/// Emitted once when an achievement transitions to unlocked.
final class AchievementUnlockedEvent extends GameEvent {
  /// Creates an [AchievementUnlockedEvent].
  AchievementUnlockedEvent({
    required this.achievement,
    required this.unlockedAt,
    super.timestamp,
  });

  /// Unlocked achievement definition.
  final Achievement achievement;

  /// Timestamp when the achievement was unlocked.
  final DateTime unlockedAt;
}
