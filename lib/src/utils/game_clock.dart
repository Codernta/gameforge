import 'dart:async';

/// Abstraction over wall-clock time for deterministic testing and timestamps.
abstract interface class GameClock {
  /// Returns the current timestamp.
  DateTime now();
}

/// Handle representing a scheduled periodic tick callback.
abstract interface class GameTickerHandle {
  /// Whether this ticker registration is still active.
  bool get isActive;

  /// Cancels future tick notifications.
  void cancel();
}

/// Abstraction over periodic tick scheduling for timers.
abstract interface class GameTicker {
  /// Schedules [onTick] to run every [interval] with the elapsed step delta.
  GameTickerHandle startPeriodic(
    Duration interval,
    void Function(Duration delta) onTick,
  );
}

/// Default production [GameClock] backed by [DateTime.now].
class SystemGameClock implements GameClock {
  /// Creates a [SystemGameClock].
  const SystemGameClock({this.useUtc = false});

  /// Whether [now] returns UTC timestamps instead of local time.
  final bool useUtc;

  @override
  DateTime now() => useUtc ? DateTime.now().toUtc() : DateTime.now();
}

/// Default production [GameTicker] backed by `dart:async` [Timer.periodic].
class SystemGameTicker implements GameTicker {
  /// Creates a [SystemGameTicker].
  const SystemGameTicker();

  @override
  GameTickerHandle startPeriodic(
    Duration interval,
    void Function(Duration delta) onTick,
  ) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Tick interval must be greater than Duration.zero.',
      );
    }
    return _SystemTickerHandle(interval, onTick);
  }
}

class _SystemTickerHandle implements GameTickerHandle {
  _SystemTickerHandle(Duration interval, void Function(Duration delta) onTick) {
    final stopwatch = Stopwatch()..start();
    var lastElapsed = Duration.zero;
    _timer = Timer.periodic(interval, (_) {
      if (!_active) {
        return;
      }
      final current = stopwatch.elapsed;
      var delta = current - lastElapsed;
      lastElapsed = current;
      if (delta <= Duration.zero) {
        delta = interval;
      }
      onTick(delta);
    });
  }

  late final Timer _timer;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (!_active) {
      return;
    }
    _active = false;
    _timer.cancel();
  }
}

/// Deterministic [GameClock] and [GameTicker] for unit and integration tests.
///
/// Time only moves when [advance] or [setTime] is called explicitly.
class FakeGameClock implements GameClock, GameTicker {
  /// Creates a [FakeGameClock] initialized at [initialTime].
  FakeGameClock({DateTime? initialTime})
    : _now = initialTime ?? DateTime.utc(2026, 1, 1);

  DateTime _now;
  final List<_FakeTickerHandle> _handles = [];

  @override
  DateTime now() => _now;

  /// Number of currently active ticker registrations.
  int get activeTickerCount =>
      _handles.where((handle) => handle.isActive).length;

  /// Jumps directly to [timestamp] without firing intermediate ticks.
  void setTime(DateTime timestamp) {
    _now = timestamp;
  }

  /// Advances the clock by [duration], triggering active tickers in exact
  /// chronological order.
  void advance(Duration duration) {
    if (duration < Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Cannot advance FakeGameClock backwards.',
      );
    }
    final target = _now.add(duration);
    if (duration == Duration.zero) {
      return;
    }

    while (true) {
      _FakeTickerHandle? earliest;
      for (final handle in _handles) {
        if (!handle.isActive) {
          continue;
        }
        if (handle.nextFire.isAfter(target)) {
          continue;
        }
        if (earliest == null || handle.nextFire.isBefore(earliest.nextFire)) {
          earliest = handle;
        }
      }

      if (earliest == null) {
        break;
      }

      _now = earliest.nextFire;
      earliest.nextFire = earliest.nextFire.add(earliest.interval);
      earliest.onTick(earliest.interval);
    }

    _now = target;
    _handles.removeWhere((handle) => !handle.isActive);
  }

  @override
  GameTickerHandle startPeriodic(
    Duration interval,
    void Function(Duration delta) onTick,
  ) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Tick interval must be greater than Duration.zero.',
      );
    }
    final handle = _FakeTickerHandle(
      interval: interval,
      nextFire: _now.add(interval),
      onTick: onTick,
    );
    _handles.add(handle);
    return handle;
  }
}

class _FakeTickerHandle implements GameTickerHandle {
  _FakeTickerHandle({
    required this.interval,
    required this.nextFire,
    required this.onTick,
  });

  final Duration interval;
  DateTime nextFire;
  final void Function(Duration delta) onTick;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    _active = false;
  }
}
