import 'package:meta/meta.dart';

import 'game_status.dart';

/// Base class for all strongly typed events dispatched on [GameEventBus].
@immutable
abstract class GameEvent {
  /// Creates a [GameEvent] stamped with [timestamp] (defaults to now).
  GameEvent({DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  /// Wall-clock or injected clock timestamp when the event was created.
  final DateTime timestamp;
}

/// Emitted whenever [GameForge.status] transitions from one state to another.
final class GameStatusChangedEvent extends GameEvent {
  /// Creates a [GameStatusChangedEvent].
  GameStatusChangedEvent({
    required this.previousStatus,
    required this.newStatus,
    super.timestamp,
  });

  /// Lifecycle status prior to the transition.
  final GameStatus previousStatus;

  /// Lifecycle status after the transition.
  final GameStatus newStatus;
}

/// Emitted when [GameForge.initialize] completes successfully.
final class GameInitializedEvent extends GameEvent {
  /// Creates a [GameInitializedEvent].
  GameInitializedEvent({super.timestamp});
}

/// Emitted when gameplay starts from [GameStatus.ready].
final class GameStartedEvent extends GameEvent {
  /// Creates a [GameStartedEvent].
  GameStartedEvent({super.timestamp});
}

/// Emitted when gameplay transitions to [GameStatus.paused].
final class GamePausedEvent extends GameEvent {
  /// Creates a [GamePausedEvent].
  GamePausedEvent({super.timestamp});
}

/// Emitted when gameplay resumes from [GameStatus.paused].
final class GameResumedEvent extends GameEvent {
  /// Creates a [GameResumedEvent].
  GameResumedEvent({super.timestamp});
}

/// Emitted when the game is restarted and modules are reset.
final class GameRestartedEvent extends GameEvent {
  /// Creates a [GameRestartedEvent].
  GameRestartedEvent({required this.autoStarted, super.timestamp});

  /// Whether the game immediately transitioned into [GameStatus.running].
  final bool autoStarted;
}

/// Emitted when the game reaches [GameStatus.completed].
final class GameCompletedEvent extends GameEvent {
  /// Creates a [GameCompletedEvent].
  GameCompletedEvent({super.timestamp});
}

/// Emitted when the game reaches [GameStatus.gameOver].
final class GameOverEvent extends GameEvent {
  /// Creates a [GameOverEvent].
  GameOverEvent({this.reason, super.timestamp});

  /// Optional reason describing why game-over occurred.
  final String? reason;
}

/// Emitted right before the event bus closes during [GameForge.dispose].
final class GameDisposedEvent extends GameEvent {
  /// Creates a [GameDisposedEvent].
  GameDisposedEvent({super.timestamp});
}

/// Emitted after [GameForge.save] successfully persists state.
final class GameSavedEvent extends GameEvent {
  /// Creates a [GameSavedEvent].
  GameSavedEvent({required this.key, required this.version, super.timestamp});

  /// Storage key under which the snapshot was saved.
  final String key;

  /// Save schema version written.
  final int version;
}

/// Emitted after [GameForge.load] successfully restores state.
final class GameLoadedEvent extends GameEvent {
  /// Creates a [GameLoadedEvent].
  GameLoadedEvent({required this.key, required this.version, super.timestamp});

  /// Storage key from which the snapshot was loaded.
  final String key;

  /// Original or migrated save schema version loaded.
  final int version;
}

/// Emitted when a non-fatal runtime or listener error is captured.
final class GameErrorEvent extends GameEvent {
  /// Creates a [GameErrorEvent].
  GameErrorEvent({required this.error, this.errorStackTrace, super.timestamp});

  /// The captured error object.
  final Object error;

  /// Optional stack trace associated with [error].
  final StackTrace? errorStackTrace;
}
