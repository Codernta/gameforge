import 'package:meta/meta.dart';

/// Immutable progress snapshot for a single [Achievement].
@immutable
class AchievementProgress {
  /// Creates an [AchievementProgress].
  const AchievementProgress({
    required this.achievementId,
    required this.currentValue,
    required this.targetValue,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  /// Identifier of the associated [Achievement].
  final String achievementId;

  /// Current accumulated progress clamped to `[0, targetValue]`.
  final int currentValue;

  /// Target progress required to unlock.
  final int targetValue;

  /// Whether the achievement has been unlocked.
  final bool isUnlocked;

  /// Timestamp when the achievement was unlocked, or `null` if locked.
  final DateTime? unlockedAt;

  /// Normalized completion ratio in `[0.0, 1.0]`.
  double get progress => isUnlocked
      ? 1.0
      : (targetValue <= 0 ? 0.0 : (currentValue / targetValue).clamp(0.0, 1.0));

  /// Returns a modified copy of this progress snapshot.
  AchievementProgress copyWith({
    int? currentValue,
    int? targetValue,
    bool? isUnlocked,
    DateTime? unlockedAt,
    bool clearUnlockedAt = false,
  }) {
    return AchievementProgress(
      achievementId: achievementId,
      currentValue: currentValue ?? this.currentValue,
      targetValue: targetValue ?? this.targetValue,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: clearUnlockedAt ? null : (unlockedAt ?? this.unlockedAt),
    );
  }

  /// Serializes this progress snapshot into JSON-compatible data.
  Map<String, Object?> toJson() => {
    'achievementId': achievementId,
    'currentValue': currentValue,
    'targetValue': targetValue,
    'isUnlocked': isUnlocked,
    'unlockedAt': unlockedAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AchievementProgress &&
        other.achievementId == achievementId &&
        other.currentValue == currentValue &&
        other.targetValue == targetValue &&
        other.isUnlocked == isUnlocked &&
        other.unlockedAt == unlockedAt;
  }

  @override
  int get hashCode => Object.hash(
    achievementId,
    currentValue,
    targetValue,
    isUnlocked,
    unlockedAt,
  );
}

/// Immutable snapshot of all registered achievement progress entries.
@immutable
class AchievementState {
  /// Creates an [AchievementState].
  AchievementState({required Map<String, AchievementProgress> entries})
    : entries = Map<String, AchievementProgress>.unmodifiable(entries);

  /// Unmodifiable map of progress entries keyed by achievement ID.
  final Map<String, AchievementProgress> entries;

  /// Number of unlocked achievements.
  int get unlockedCount => entries.values.where((p) => p.isUnlocked).length;

  /// Total number of registered achievements.
  int get totalCount => entries.length;

  /// Serializes all achievement progress entries into JSON-compatible data.
  Map<String, Object?> toJson() => {
    'entries': {
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    },
  };
}
