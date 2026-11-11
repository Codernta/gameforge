import 'package:meta/meta.dart';

import '../core/game_event.dart';
import '../core/game_exception.dart';
import '../persistence/serialization.dart';

/// Lifecycle states for a gameplay session.
enum SessionStatus {
  /// No active session has been started yet.
  idle,

  /// Session is currently running and accumulating active duration.
  active,

  /// Session is temporarily paused.
  paused,

  /// Session finished normally (win or level/run completion).
  completed,

  /// Session was exited or terminated early (e.g., quit or game over).
  abandoned,
}

/// Immutable snapshot of a single gameplay session and its statistics.
@immutable
class SessionState {
  /// Creates a [SessionState].
  SessionState({
    required this.sessionId,
    required this.status,
    this.startTime,
    this.endTime,
    this.duration = Duration.zero,
    this.sessionScore = 0,
    Map<String, num> statistics = const {},
  }) : statistics = Map<String, num>.unmodifiable(statistics);

  /// Empty idle placeholder before any session starts.
  factory SessionState.idle() =>
      SessionState(sessionId: '', status: SessionStatus.idle);

  /// Restores a [SessionState] from serialized JSON data.
  factory SessionState.fromJson(Map<String, Object?> json) {
    final sessionId = GameSerialization.readString(json, 'sessionId');
    final statusName = GameSerialization.readString(json, 'status');
    final status = SessionStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => throw CorruptSaveDataException(
        'Unknown SessionStatus "$statusName".',
      ),
    );
    final startStr = GameSerialization.readOptionalString(json, 'startTime');
    final endStr = GameSerialization.readOptionalString(json, 'endTime');
    final startTime = startStr == null ? null : DateTime.tryParse(startStr);
    final endTime = endStr == null ? null : DateTime.tryParse(endStr);
    if ((startStr != null && startTime == null) ||
        (endStr != null && endTime == null)) {
      throw const CorruptSaveDataException(
        'Invalid timestamp inside saved SessionState.',
      );
    }

    final durationUs = GameSerialization.readInt(
      json,
      'durationMicros',
      defaultValue: 0,
    );
    if (durationUs < 0) {
      throw const SaveValidationException(
        'Saved session duration cannot be negative.',
      );
    }
    final score = GameSerialization.readInt(
      json,
      'sessionScore',
      defaultValue: 0,
    );
    final rawStats = GameSerialization.readMap(
      json,
      'statistics',
      defaultValue: const {},
    );
    final stats = <String, num>{};
    for (final entry in rawStats.entries) {
      final value = entry.value;
      if (value is! num) {
        throw CorruptSaveDataException(
          'Expected numeric stat for "${entry.key}", got ${value.runtimeType}.',
        );
      }
      stats[entry.key] = value;
    }

    return SessionState(
      sessionId: sessionId,
      status: status,
      startTime: startTime,
      endTime: endTime,
      duration: Duration(microseconds: durationUs),
      sessionScore: score,
      statistics: stats,
    );
  }

  /// Unique identifier for this session.
  final String sessionId;

  /// Current session lifecycle state.
  final SessionStatus status;

  /// Timestamp when the session started.
  final DateTime? startTime;

  /// Timestamp when the session completed or was abandoned.
  final DateTime? endTime;

  /// Active gameplay duration accumulated (excluding paused intervals).
  final Duration duration;

  /// Score accumulated during this session.
  final int sessionScore;

  /// Numeric gameplay statistics collected during this session.
  final Map<String, num> statistics;

  /// Whether this session is currently active or paused.
  bool get isOpen =>
      status == SessionStatus.active || status == SessionStatus.paused;

  /// Returns a modified copy of this [SessionState].
  SessionState copyWith({
    String? sessionId,
    SessionStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    int? sessionScore,
    Map<String, num>? statistics,
  }) {
    return SessionState(
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      sessionScore: sessionScore ?? this.sessionScore,
      statistics: statistics ?? this.statistics,
    );
  }

  /// Serializes this session snapshot into JSON-compatible data.
  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'status': status.name,
    'startTime': startTime?.toUtc().toIso8601String(),
    'endTime': endTime?.toUtc().toIso8601String(),
    'durationMicros': duration.inMicroseconds,
    'sessionScore': sessionScore,
    'statistics': Map<String, num>.of(statistics),
  };
}

/// Emitted when a new gameplay session begins.
final class SessionStartedEvent extends GameEvent {
  /// Creates a [SessionStartedEvent].
  SessionStartedEvent({required this.session, super.timestamp});

  /// Snapshot of the newly started session.
  final SessionState session;
}

/// Emitted when an active session is paused.
final class SessionPausedEvent extends GameEvent {
  /// Creates a [SessionPausedEvent].
  SessionPausedEvent({required this.session, super.timestamp});

  /// Snapshot of the paused session.
  final SessionState session;
}

/// Emitted when a paused session resumes.
final class SessionResumedEvent extends GameEvent {
  /// Creates a [SessionResumedEvent].
  SessionResumedEvent({required this.session, super.timestamp});

  /// Snapshot of the resumed session.
  final SessionState session;
}

/// Emitted when a session completes normally.
final class SessionCompletedEvent extends GameEvent {
  /// Creates a [SessionCompletedEvent].
  SessionCompletedEvent({required this.session, super.timestamp});

  /// Snapshot of the completed session.
  final SessionState session;
}

/// Emitted when a session is abandoned before completion.
final class SessionAbandonedEvent extends GameEvent {
  /// Creates a [SessionAbandonedEvent].
  SessionAbandonedEvent({required this.session, super.timestamp});

  /// Snapshot of the abandoned session.
  final SessionState session;
}
