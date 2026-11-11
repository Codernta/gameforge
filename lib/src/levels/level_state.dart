import 'package:meta/meta.dart';

/// Per-level progression metrics for a single level.
@immutable
class LevelProgress {
  /// Creates a [LevelProgress].
  const LevelProgress({
    required this.levelId,
    this.isUnlocked = false,
    this.isCompleted = false,
    this.stars = 0,
    this.bestScore = 0,
    this.attempts = 0,
    this.completedAt,
  });

  /// Identifier of the level.
  final String levelId;

  /// Whether the player can currently access this level.
  final bool isUnlocked;

  /// Whether the player has completed this level at least once.
  final bool isCompleted;

  /// Best star rating achieved for this level.
  final int stars;

  /// Best score achieved for this level.
  final int bestScore;

  /// Number of completions/attempts recorded.
  final int attempts;

  /// Timestamp of the most recent completion, if any.
  final DateTime? completedAt;

  /// Returns an updated copy of this [LevelProgress].
  LevelProgress copyWith({
    bool? isUnlocked,
    bool? isCompleted,
    int? stars,
    int? bestScore,
    int? attempts,
    DateTime? completedAt,
  }) {
    return LevelProgress(
      levelId: levelId,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      isCompleted: isCompleted ?? this.isCompleted,
      stars: stars ?? this.stars,
      bestScore: bestScore ?? this.bestScore,
      attempts: attempts ?? this.attempts,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// Serializes this progress entry into JSON-compatible data.
  Map<String, Object?> toJson() => {
    'levelId': levelId,
    'isUnlocked': isUnlocked,
    'isCompleted': isCompleted,
    'stars': stars,
    'bestScore': bestScore,
    'attempts': attempts,
    'completedAt': completedAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LevelProgress &&
        other.levelId == levelId &&
        other.isUnlocked == isUnlocked &&
        other.isCompleted == isCompleted &&
        other.stars == stars &&
        other.bestScore == bestScore &&
        other.attempts == attempts &&
        other.completedAt == completedAt;
  }

  @override
  int get hashCode => Object.hash(
    levelId,
    isUnlocked,
    isCompleted,
    stars,
    bestScore,
    attempts,
    completedAt,
  );
}

/// Immutable snapshot of progression across all configured levels.
@immutable
class LevelState {
  /// Creates a [LevelState].
  LevelState({
    required this.currentLevelId,
    required Map<String, LevelProgress> progressById,
  }) : progressById = Map<String, LevelProgress>.unmodifiable(progressById);

  /// Identifier of the currently selected level.
  final String currentLevelId;

  /// Unmodifiable map of progress records keyed by level ID.
  final Map<String, LevelProgress> progressById;

  /// Whether [levelId] is currently unlocked.
  bool isUnlocked(String levelId) => progressById[levelId]?.isUnlocked ?? false;

  /// Whether [levelId] has been completed.
  bool isCompleted(String levelId) =>
      progressById[levelId]?.isCompleted ?? false;

  /// Set of unlocked level IDs.
  Set<String> get unlockedLevelIds => {
    for (final entry in progressById.entries)
      if (entry.value.isUnlocked) entry.key,
  };

  /// Set of completed level IDs.
  Set<String> get completedLevelIds => {
    for (final entry in progressById.entries)
      if (entry.value.isCompleted) entry.key,
  };

  /// Total stars earned across all levels.
  int get totalStars =>
      progressById.values.fold<int>(0, (sum, item) => sum + item.stars);

  /// Fraction of levels completed (`0.0` to `1.0`).
  double get completionRatio => progressById.isEmpty
      ? 0.0
      : completedLevelIds.length / progressById.length;

  /// Serializes this state into a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'currentLevelId': currentLevelId,
    'levels': {
      for (final entry in progressById.entries) entry.key: entry.value.toJson(),
    },
  };
}
