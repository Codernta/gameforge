import 'dart:async';

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../persistence/game_storage.dart';
import '../persistence/serialization.dart';
import '../utils/game_clock.dart';
import '../utils/id_generator.dart';
import 'session_state.dart';

/// Manages gameplay sessions, active duration tracking (excluding pauses),
/// session scores, statistics, and optional persisted session history.
class GameSessionManager extends GameModule {
  /// Creates a [GameSessionManager].
  GameSessionManager({
    this.autoManageLifecycle = true,
    GameStorage? historyStorage,
    this.historyStorageKey = 'gameforge_session_history',
    this.maxHistoryEntries = 100,
    GameClock clock = const SystemGameClock(),
    IdGenerator? idGenerator,
    GameEventBus? eventBus,
  }) : _historyStorage = historyStorage,
       _clock = clock,
       _idGenerator = idGenerator ?? RandomIdGenerator(),
       _eventBus = eventBus;

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'session';

  /// Whether [GameForge] lifecycle transitions automatically start, pause,
  /// resume, complete, or abandon the active session.
  final bool autoManageLifecycle;

  final GameStorage? _historyStorage;

  /// Storage key used when persisting session history to [historyStorage].
  final String historyStorageKey;

  /// Maximum number of archived sessions retained in history.
  final int maxHistoryEntries;

  GameClock _clock;
  IdGenerator _idGenerator;
  GameEventBus? _eventBus;

  final StreamController<SessionState> _stateController =
      StreamController<SessionState>.broadcast();

  final List<SessionState> _history = [];
  SessionState _current = SessionState.idle();
  DateTime? _activeSegmentStart;
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Snapshot of the current (or most recently closed) session, computing
  /// real-time active duration if currently running.
  SessionState get current {
    if (_current.status == SessionStatus.active &&
        _activeSegmentStart != null) {
      final segment = _clock.now().difference(_activeSegmentStart!);
      final total = segment.isNegative
          ? _current.duration
          : _current.duration + segment;
      return _current.copyWith(duration: total);
    }
    return _current;
  }

  /// Current session lifecycle status.
  SessionStatus get status => _current.status;

  /// Unmodifiable list of completed or abandoned past sessions.
  List<SessionState> get history => List<SessionState>.unmodifiable(_history);

  /// Broadcast stream emitting whenever session state updates.
  Stream<SessionState> get stream => _stateController.stream;

  @override
  Future<void> onInitialize(GameModuleContext context) async {
    _eventBus ??= context.events;
    _clock = context.clock;
    _idGenerator = context.idGenerator;
    await loadHistory();
  }

  @override
  void onStart() {
    if (!autoManageLifecycle) return;
    if (!_current.isOpen) {
      startSession();
    }
  }

  @override
  void onPause() {
    if (!autoManageLifecycle) return;
    if (_current.status == SessionStatus.active) {
      pauseSession();
    }
  }

  @override
  void onResume() {
    if (!autoManageLifecycle) return;
    if (_current.status == SessionStatus.paused) {
      resumeSession();
    }
  }

  @override
  void onComplete() {
    if (!autoManageLifecycle) return;
    if (_current.isOpen) {
      completeSession();
    }
  }

  @override
  void onGameOver() {
    if (!autoManageLifecycle) return;
    if (_current.isOpen) {
      abandonSession();
    }
  }

  @override
  void onReset() {
    if (_current.isOpen) {
      abandonSession();
    }
    _current = SessionState.idle();
    _activeSegmentStart = null;
    _emitState();
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Starts a new gameplay session with optional [sessionId] and initial
  /// [statistics].
  ///
  /// Throws [SessionException] if a session is already active or paused.
  SessionState startSession({
    String? sessionId,
    Map<String, num> statistics = const {},
  }) {
    _ensureNotDisposed();
    if (_current.isOpen) {
      throw SessionException(
        'Cannot start a new session while session "${_current.sessionId}" is '
        'still ${_current.status.name}.',
      );
    }

    final now = _clock.now();
    final id = sessionId ?? _idGenerator.nextId('session');
    _activeSegmentStart = now;
    _current = SessionState(
      sessionId: id,
      status: SessionStatus.active,
      startTime: now,
      duration: Duration.zero,
      sessionScore: 0,
      statistics: statistics,
    );
    _emitState();
    _emitEvent(SessionStartedEvent(session: _current, timestamp: now));
    return _current;
  }

  /// Pauses the active session, preserving accumulated duration.
  SessionState pauseSession() {
    _ensureNotDisposed();
    if (_current.status != SessionStatus.active) {
      throw SessionException(
        'Cannot pause session in status ${_current.status.name}.',
      );
    }

    final now = _clock.now();
    _current = current.copyWith(status: SessionStatus.paused);
    _activeSegmentStart = null;
    _emitState();
    _emitEvent(SessionPausedEvent(session: _current, timestamp: now));
    return _current;
  }

  /// Resumes a paused session.
  SessionState resumeSession() {
    _ensureNotDisposed();
    if (_current.status != SessionStatus.paused) {
      throw SessionException(
        'Cannot resume session in status ${_current.status.name}.',
      );
    }

    final now = _clock.now();
    _activeSegmentStart = now;
    _current = _current.copyWith(status: SessionStatus.active);
    _emitState();
    _emitEvent(SessionResumedEvent(session: _current, timestamp: now));
    return _current;
  }

  /// Completes the current active or paused session and records it in history.
  SessionState completeSession({int? finalScore}) {
    return _finishSession(SessionStatus.completed, finalScore: finalScore);
  }

  /// Abandons the current active or paused session and records it in history.
  SessionState abandonSession({int? finalScore}) {
    return _finishSession(SessionStatus.abandoned, finalScore: finalScore);
  }

  /// Sets the current session's score to [score].
  void setScore(int score) {
    _ensureNotDisposed();
    if (!_current.isOpen) {
      return;
    }
    _current = _current.copyWith(sessionScore: score);
    _emitState();
  }

  /// Increments a numeric statistic [key] on the current open session by [delta].
  void recordStat(String key, num delta) {
    _ensureNotDisposed();
    if (!_current.isOpen) {
      throw const SessionException(
        'Cannot record statistics without an open session.',
      );
    }
    final stats = Map<String, num>.of(_current.statistics);
    stats[key] = (stats[key] ?? 0) + delta;
    _current = _current.copyWith(statistics: stats);
    _emitState();
  }

  /// Sets a numeric statistic [key] on the current open session to [value].
  void setStat(String key, num value) {
    _ensureNotDisposed();
    if (!_current.isOpen) {
      throw const SessionException(
        'Cannot set statistics without an open session.',
      );
    }
    final stats = Map<String, num>.of(_current.statistics);
    stats[key] = value;
    _current = _current.copyWith(statistics: stats);
    _emitState();
  }

  /// Loads persisted session history from [historyStorage], if configured.
  Future<List<SessionState>> loadHistory() async {
    final storage = _historyStorage;
    if (storage == null) {
      return history;
    }
    final raw = await storage.read(historyStorageKey);
    if (raw == null) {
      return history;
    }
    final items = GameSerialization.readList(
      raw,
      'sessions',
      defaultValue: const [],
    );
    final restored = <SessionState>[];
    for (final entry in items) {
      if (entry is! Map<Object?, Object?>) {
        throw const CorruptSaveDataException(
          'Expected map inside saved session history.',
        );
      }
      restored.add(
        SessionState.fromJson(GameSerialization.normalizeMap(entry)),
      );
    }
    _history
      ..clear()
      ..addAll(restored);
    return history;
  }

  /// Persists the current session history to [historyStorage], if configured.
  Future<void> saveHistory() async {
    final storage = _historyStorage;
    if (storage == null) {
      return;
    }
    await storage.save(historyStorageKey, {
      'sessions': _history.map((s) => s.toJson()).toList(growable: false),
    });
  }

  /// Clears in-memory and optionally persisted session history.
  Future<void> clearHistory() async {
    _history.clear();
    final storage = _historyStorage;
    if (storage != null) {
      await storage.delete(historyStorageKey);
    }
  }

  @override
  Map<String, Object?> toSaveData() => {
    'current': current.toJson(),
    'history': _history.map((s) => s.toJson()).toList(growable: false),
  };

  @override
  void fromSaveData(Map<String, Object?> data) {
    _ensureNotDisposed();
    final rawCurrent = GameSerialization.readMap(data, 'current');
    final restoredCurrent = SessionState.fromJson(rawCurrent);
    final rawHistory = GameSerialization.readList(
      data,
      'history',
      defaultValue: const [],
    );
    final restoredHistory = <SessionState>[];
    for (final entry in rawHistory) {
      if (entry is! Map<Object?, Object?>) {
        throw const CorruptSaveDataException(
          'Expected map inside saved session history.',
        );
      }
      restoredHistory.add(
        SessionState.fromJson(GameSerialization.normalizeMap(entry)),
      );
    }

    _current = restoredCurrent;
    _activeSegmentStart = restoredCurrent.status == SessionStatus.active
        ? _clock.now()
        : null;
    _history
      ..clear()
      ..addAll(restoredHistory);
    _emitState();
  }

  /// Releases resources owned by this manager.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _stateController.close();
  }

  SessionState _finishSession(SessionStatus endStatus, {int? finalScore}) {
    _ensureNotDisposed();
    if (!_current.isOpen) {
      throw SessionException(
        'Cannot finish session when status is ${_current.status.name}.',
      );
    }

    final now = _clock.now();
    final finished = current.copyWith(
      status: endStatus,
      endTime: now,
      sessionScore: finalScore ?? _current.sessionScore,
    );
    _activeSegmentStart = null;
    _current = finished;

    _history.add(finished);
    while (_history.length > maxHistoryEntries) {
      _history.removeAt(0);
    }
    _emitState();

    if (endStatus == SessionStatus.completed) {
      _emitEvent(SessionCompletedEvent(session: finished, timestamp: now));
    } else {
      _emitEvent(SessionAbandonedEvent(session: finished, timestamp: now));
    }

    if (_historyStorage != null) {
      unawaited(saveHistory());
    }
    return finished;
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(current);
    }
  }

  void _emitEvent(GameEvent event) {
    final bus = _eventBus;
    if (bus != null && !bus.isDisposed) {
      bus.emit(event);
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot use GameSessionManager after it has been disposed.',
      );
    }
  }
}
