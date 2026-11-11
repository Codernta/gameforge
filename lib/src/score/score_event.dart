import '../core/game_event.dart';

/// Emitted whenever the current score changes.
final class ScoreChangedEvent extends GameEvent {
  /// Creates a [ScoreChangedEvent].
  ScoreChangedEvent({
    required this.previousScore,
    required this.newScore,
    required this.delta,
    required this.highScore,
    super.timestamp,
  });

  /// Score value before the change.
  final int previousScore;

  /// Score value after the change.
  final int newScore;

  /// Net change (`newScore - previousScore`).
  final int delta;

  /// Current high score after the change.
  final int highScore;
}

/// Emitted when [newHighScore] strictly surpasses [previousHighScore].
final class HighScoreAchievedEvent extends GameEvent {
  /// Creates a [HighScoreAchievedEvent].
  HighScoreAchievedEvent({
    required this.previousHighScore,
    required this.newHighScore,
    super.timestamp,
  });

  /// Previous high score value.
  final int previousHighScore;

  /// Newly achieved high score value.
  final int newHighScore;
}

/// Emitted when the active score multiplier changes.
final class ScoreMultiplierChangedEvent extends GameEvent {
  /// Creates a [ScoreMultiplierChangedEvent].
  ScoreMultiplierChangedEvent({
    required this.previousMultiplier,
    required this.newMultiplier,
    super.timestamp,
  });

  /// Multiplier before the update.
  final double previousMultiplier;

  /// Multiplier after the update.
  final double newMultiplier;
}

/// Emitted when the combo streak count or combo multiplier changes.
final class ComboChangedEvent extends GameEvent {
  /// Creates a [ComboChangedEvent].
  ComboChangedEvent({
    required this.previousCombo,
    required this.newCombo,
    required this.comboMultiplier,
    super.timestamp,
  });

  /// Combo count prior to the change.
  final int previousCombo;

  /// Combo count after the change.
  final int newCombo;

  /// Resulting combo multiplier.
  final double comboMultiplier;
}

/// Emitted when the score is reset.
final class ScoreResetEvent extends GameEvent {
  /// Creates a [ScoreResetEvent].
  ScoreResetEvent({
    required this.previousScore,
    required this.resetScore,
    required this.highScoreReset,
    super.timestamp,
  });

  /// Score prior to resetting.
  final int previousScore;

  /// Score after resetting.
  final int resetScore;

  /// Whether the high score was also cleared.
  final bool highScoreReset;
}
