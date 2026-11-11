import 'package:meta/meta.dart';

import '../core/game_event.dart';

/// Lifecycle states of a [GameTimer].
enum TimerStatus {
  /// Timer has been created or reset and has not started yet.
  idle,

  /// Timer is actively ticking.
  running,

  /// Timer is paused and retains elapsed progress.
  paused,

  /// Timer finished reaching its target duration or tick limit.
  completed,

  /// Timer was manually stopped before completion.
  stopped,

  /// Timer has been permanently disposed.
  disposed,
}

/// Immutable snapshot of a [GameTimer]'s current progress and status.
@immutable
class TimerState {
  /// Creates a [TimerState].
  const TimerState({
    required this.id,
    required this.status,
    required this.elapsed,
    this.totalDuration,
    this.remaining,
    this.tickCount = 0,
  });

  /// Identifier of the owning timer.
  final String id;

  /// Current lifecycle status.
  final TimerStatus status;

  /// Total active elapsed duration accumulated while running.
  final Duration elapsed;

  /// Configured target duration (for countdown or bounded timers), if any.
  final Duration? totalDuration;

  /// Remaining duration until completion (for countdown timers), if any.
  final Duration? remaining;

  /// Number of ticks observed since start/reset.
  final int tickCount;

  /// Progress fraction in `[0.0, 1.0]` when [totalDuration] is configured.
  double get progress {
    final total = totalDuration;
    if (total == null || total <= Duration.zero) {
      return 0.0;
    }
    return (elapsed.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0);
  }

  /// Whether this timer is currently running.
  bool get isRunning => status == TimerStatus.running;

  /// Whether this timer is currently paused.
  bool get isPaused => status == TimerStatus.paused;

  /// Whether this timer has completed.
  bool get isCompleted => status == TimerStatus.completed;

  /// Returns a modified copy of this state.
  TimerState copyWith({
    TimerStatus? status,
    Duration? elapsed,
    Duration? totalDuration,
    Duration? remaining,
    bool clearRemaining = false,
    int? tickCount,
  }) {
    return TimerState(
      id: id,
      status: status ?? this.status,
      elapsed: elapsed ?? this.elapsed,
      totalDuration: totalDuration ?? this.totalDuration,
      remaining: clearRemaining ? null : (remaining ?? this.remaining),
      tickCount: tickCount ?? this.tickCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimerState &&
        other.id == id &&
        other.status == status &&
        other.elapsed == elapsed &&
        other.totalDuration == totalDuration &&
        other.remaining == remaining &&
        other.tickCount == tickCount;
  }

  @override
  int get hashCode =>
      Object.hash(id, status, elapsed, totalDuration, remaining, tickCount);

  @override
  String toString() =>
      'TimerState(id: $id, status: $status, elapsed: $elapsed, '
      'remaining: $remaining, ticks: $tickCount)';
}

/// Emitted when a [GameTimer] starts.
final class TimerStartedEvent extends GameEvent {
  /// Creates a [TimerStartedEvent].
  TimerStartedEvent({required this.timerId, super.timestamp});

  /// Identifier of the started timer.
  final String timerId;
}

/// Emitted when a [GameTimer] pauses.
final class TimerPausedEvent extends GameEvent {
  /// Creates a [TimerPausedEvent].
  TimerPausedEvent({
    required this.timerId,
    required this.elapsed,
    super.timestamp,
  });

  /// Identifier of the paused timer.
  final String timerId;

  /// Elapsed duration at pause time.
  final Duration elapsed;
}

/// Emitted when a [GameTimer] resumes from pause.
final class TimerResumedEvent extends GameEvent {
  /// Creates a [TimerResumedEvent].
  TimerResumedEvent({
    required this.timerId,
    required this.elapsed,
    super.timestamp,
  });

  /// Identifier of the resumed timer.
  final String timerId;

  /// Elapsed duration when resumed.
  final Duration elapsed;
}

/// Emitted on each tick of a [GameTimer].
final class TimerTickEvent extends GameEvent {
  /// Creates a [TimerTickEvent].
  TimerTickEvent({required this.state, super.timestamp});

  /// Timer state at this tick.
  final TimerState state;
}

/// Emitted when a bounded [GameTimer] completes.
final class TimerCompletedEvent extends GameEvent {
  /// Creates a [TimerCompletedEvent].
  TimerCompletedEvent({
    required this.timerId,
    required this.elapsed,
    super.timestamp,
  });

  /// Identifier of the completed timer.
  final String timerId;

  /// Total elapsed duration upon completion.
  final Duration elapsed;
}

/// Emitted when a [GameTimer] is stopped.
final class TimerStoppedEvent extends GameEvent {
  /// Creates a [TimerStoppedEvent].
  TimerStoppedEvent({
    required this.timerId,
    required this.elapsed,
    super.timestamp,
  });

  /// Identifier of the stopped timer.
  final String timerId;

  /// Elapsed duration when stopped.
  final Duration elapsed;
}

/// Emitted when a [GameTimer] is reset.
final class TimerResetEvent extends GameEvent {
  /// Creates a [TimerResetEvent].
  TimerResetEvent({required this.timerId, super.timestamp});

  /// Identifier of the reset timer.
  final String timerId;
}
