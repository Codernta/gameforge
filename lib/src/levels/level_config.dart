import 'package:meta/meta.dart';

import '../core/game_exception.dart';
import 'level_state.dart';

/// Static definition of a single playable level.
@immutable
class LevelConfig {
  /// Creates a [LevelConfig].
  const LevelConfig({
    required this.id,
    required this.number,
    String? name,
    this.maxStars = 3,
    this.unlockedByDefault = false,
    this.prerequisiteIds = const [],
    this.metadata = const {},
  }) : name = name ?? 'Level $number';

  /// Creates sequential default levels numbered `1..count` with IDs
  /// `'level_1'..'level_$count'`.
  static List<LevelConfig> generateSequential(int count, {int maxStars = 3}) {
    if (count < 1) {
      throw GameConfigurationException(
        'Level count must be at least 1 (got $count).',
      );
    }
    return List<LevelConfig>.generate(count, (index) {
      final number = index + 1;
      return LevelConfig(
        id: 'level_$number',
        number: number,
        name: 'Level $number',
        maxStars: maxStars,
        unlockedByDefault: index == 0,
        prerequisiteIds: index == 0 ? const [] : ['level_$index'],
      );
    }, growable: false);
  }

  /// Unique string identifier for this level (for example, `'level_1'`).
  final String id;

  /// Numeric level index/number (for example, `1`, `2`, `3`).
  final int number;

  /// Display title of the level.
  final String name;

  /// Maximum earnable stars or rating value for this level.
  final int maxStars;

  /// Whether this level begins unlocked on a fresh game.
  final bool unlockedByDefault;

  /// Optional list of level IDs that must be completed before unlocking.
  final List<String> prerequisiteIds;

  /// Arbitrary developer metadata associated with this level.
  final Map<String, Object?> metadata;

  /// Validates the level configuration.
  void validate() {
    if (id.trim().isEmpty) {
      throw const GameConfigurationException('LevelConfig id cannot be empty.');
    }
    if (number < 1) {
      throw GameConfigurationException(
        'LevelConfig "$id" number must be >= 1 (got $number).',
      );
    }
    if (maxStars < 0) {
      throw GameConfigurationException(
        'LevelConfig "$id" maxStars must be >= 0 (got $maxStars).',
      );
    }
  }
}

/// Strategy interface determining which levels unlock on completion and what
/// level comes next.
abstract interface class LevelProgressionStrategy {
  /// Returns level IDs that should newly unlock when [completedLevel] finishes
  /// under the current [state].
  List<String> resolveUnlocks({
    required LevelConfig completedLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  });

  /// Returns the next level to advance to from [currentLevel], or `null` if no
  /// further level is available.
  LevelConfig? resolveNextLevel({
    required LevelConfig currentLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  });
}

/// Standard linear progression: completing level `N` unlocks level `N + 1` in
/// configuration order.
class SequentialLevelProgression implements LevelProgressionStrategy {
  /// Creates a [SequentialLevelProgression].
  const SequentialLevelProgression();

  @override
  List<String> resolveUnlocks({
    required LevelConfig completedLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  }) {
    final index = allLevels.indexWhere((l) => l.id == completedLevel.id);
    if (index == -1 || index + 1 >= allLevels.length) {
      return const [];
    }
    final next = allLevels[index + 1];
    if (state.isUnlocked(next.id)) {
      return const [];
    }
    return [next.id];
  }

  @override
  LevelConfig? resolveNextLevel({
    required LevelConfig currentLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  }) {
    final index = allLevels.indexWhere((l) => l.id == currentLevel.id);
    if (index == -1 || index + 1 >= allLevels.length) {
      return null;
    }
    final next = allLevels[index + 1];
    return state.isUnlocked(next.id) ? next : null;
  }
}

/// Graph/branching progression: any level whose [LevelConfig.prerequisiteIds]
/// are all completed becomes unlocked.
class PrerequisiteLevelProgression implements LevelProgressionStrategy {
  /// Creates a [PrerequisiteLevelProgression].
  const PrerequisiteLevelProgression();

  @override
  List<String> resolveUnlocks({
    required LevelConfig completedLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  }) {
    final newlyUnlocked = <String>[];
    for (final candidate in allLevels) {
      if (state.isUnlocked(candidate.id)) {
        continue;
      }
      if (candidate.prerequisiteIds.isEmpty) {
        continue;
      }
      final allPrereqsMet = candidate.prerequisiteIds.every(
        (prereqId) =>
            prereqId == completedLevel.id || state.isCompleted(prereqId),
      );
      if (allPrereqsMet) {
        newlyUnlocked.add(candidate.id);
      }
    }
    return newlyUnlocked;
  }

  @override
  LevelConfig? resolveNextLevel({
    required LevelConfig currentLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  }) {
    final index = allLevels.indexWhere((l) => l.id == currentLevel.id);
    for (var i = index + 1; i < allLevels.length; i++) {
      final candidate = allLevels[i];
      if (state.isUnlocked(candidate.id) && !state.isCompleted(candidate.id)) {
        return candidate;
      }
    }
    for (var i = index + 1; i < allLevels.length; i++) {
      final candidate = allLevels[i];
      if (state.isUnlocked(candidate.id)) {
        return candidate;
      }
    }
    return null;
  }
}

/// Non-linear open progression where levels remain freely accessible.
class OpenLevelProgression implements LevelProgressionStrategy {
  /// Creates an [OpenLevelProgression].
  const OpenLevelProgression();

  @override
  List<String> resolveUnlocks({
    required LevelConfig completedLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  }) => const [];

  @override
  LevelConfig? resolveNextLevel({
    required LevelConfig currentLevel,
    required List<LevelConfig> allLevels,
    required LevelState state,
  }) {
    final index = allLevels.indexWhere((l) => l.id == currentLevel.id);
    if (index == -1 || index + 1 >= allLevels.length) {
      return null;
    }
    return allLevels[index + 1];
  }
}
