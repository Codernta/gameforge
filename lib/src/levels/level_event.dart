import '../core/game_event.dart';

/// Emitted when a level transitions from locked to unlocked.
final class LevelUnlockedEvent extends GameEvent {
  /// Creates a [LevelUnlockedEvent].
  LevelUnlockedEvent({
    required this.levelId,
    required this.levelNumber,
    super.timestamp,
  });

  /// Identifier of the unlocked level.
  final String levelId;

  /// Numeric index of the unlocked level.
  final int levelNumber;
}

/// Emitted when a level is locked.
final class LevelLockedEvent extends GameEvent {
  /// Creates a [LevelLockedEvent].
  LevelLockedEvent({
    required this.levelId,
    required this.levelNumber,
    super.timestamp,
  });

  /// Identifier of the locked level.
  final String levelId;

  /// Numeric index of the locked level.
  final int levelNumber;
}

/// Emitted when the active level selection changes.
final class CurrentLevelChangedEvent extends GameEvent {
  /// Creates a [CurrentLevelChangedEvent].
  CurrentLevelChangedEvent({
    required this.previousLevelId,
    required this.newLevelId,
    required this.newLevelNumber,
    super.timestamp,
  });

  /// Previously selected level ID.
  final String previousLevelId;

  /// Newly selected level ID.
  final String newLevelId;

  /// Numeric index of the newly selected level.
  final int newLevelNumber;
}

/// Emitted when a level is completed.
final class LevelCompletedEvent extends GameEvent {
  /// Creates a [LevelCompletedEvent].
  LevelCompletedEvent({
    required this.levelId,
    required this.levelNumber,
    required this.stars,
    required this.score,
    required this.newlyUnlockedLevelIds,
    super.timestamp,
  });

  /// Identifier of the completed level.
  final String levelId;

  /// Numeric index of the completed level.
  final int levelNumber;

  /// Stars earned in this completion.
  final int stars;

  /// Score recorded for this completion.
  final int score;

  /// Any levels that automatically unlocked as a result.
  final List<String> newlyUnlockedLevelIds;
}
