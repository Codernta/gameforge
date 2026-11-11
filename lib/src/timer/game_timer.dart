import 'dart:async';

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../utils/game_clock.dart';
import '../utils/id_generator.dart';
import 'countdown_timer.dart';
import 'timer_state.dart';

/// Base class for lifecycle-aware gameplay timers ([CountdownTimer],
/// [StopwatchTimer], and [PeriodicTimer]).
abstract class GameTimer {
  /// Creates a [GameTimer].
  GameTimer({
    required this.id,
    required this.tickInterval,
    GameTicker ticker = const SystemGameTicker(),
    GameClock clock = const SystemGameClock(),
    GameEventBus? eventBus,
    this.emitTickEvents = false,
    void Function(TimerState state)? onTick,
    void Function()? onComplete,
  }) : _ticker = ticker,
       _clock = clock,
       _eventBus = eventBus,
       _onTickCallback = onTick,
       _onCompleteCallback = onComplete {
    if (id.trim().isEmpty) {
      throw const TimerException('Timer id cannot be empty.');
    }
    if (tickInterval <= Duration.zero) {
      throw TimerException(
        'Timer "$id" tickInterval must be greater than Duration.zero.',
      );
    }
  }

  /// Unique identifier for this timer.
  final String id;

  /// Sampling interval used to drive ticks.
  final Duration tickInterval;

  /// Whether every tick should also broadcast a [TimerTickEvent] on [GameEventBus].
  final bool emitTickEvents;

  final GameTicker _ticker;
  final GameClock _clock;
  final GameEventBus? _eventBus;
  final void Function(TimerState state)? _onTickCallback;
  final void Function()? _onCompleteCallback;

  final StreamController<TimerState> _stateController =
      StreamController<TimerState>.broadcast();
  final StreamController<TimerState> _tickController =
      StreamController<TimerState>.broadcast();

  GameTickerHandle? _handle;
  late TimerState _state;

  /// Current immutable [TimerState].
  TimerState get state => _state;

  /// Current timer lifecycle status.
  TimerStatus get status => _state.status;

  /// Active elapsed duration accumulated while running.
  Duration get elapsed => _state.elapsed;

  /// Remaining duration when applicable, or `null`.
  Duration? get remaining => _state.remaining;

  /// Stream emitting whenever timer state changes (status, reset, tick).
  Stream<TimerState> get stateStream => _stateController.stream;

  /// Stream emitting specifically on timer ticks.
  Stream<TimerState> get tickStream => _tickController.stream;

  /// Initializes the initial [TimerState] for subclasses.
  void initState(TimerState initialState) {
    _state = initialState;
  }

  /// Starts the timer.
  ///
  /// If already [TimerStatus.running], this is a no-op. If previously
  /// [TimerStatus.stopped] or [TimerStatus.completed], resets elapsed progress
  /// before starting.
  void start() {
    _ensureNotDisposed();
    if (_state.status == TimerStatus.running) {
      return;
    }
    if (_state.status == TimerStatus.paused) {
      resume();
      return;
    }
    if (_state.status == TimerStatus.stopped ||
        _state.status == TimerStatus.completed) {
      onResetState();
    }
    _state = _state.copyWith(status: TimerStatus.running);
    _startTicker();
    _emitState();
    _emitEvent(TimerStartedEvent(timerId: id, timestamp: _clock.now()));
  }

  /// Pauses the timer if currently [TimerStatus.running].
  void pause() {
    _ensureNotDisposed();
    if (_state.status != TimerStatus.running) {
      return;
    }
    _stopTicker();
    _state = _state.copyWith(status: TimerStatus.paused);
    _emitState();
    _emitEvent(
      TimerPausedEvent(
        timerId: id,
        elapsed: _state.elapsed,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Resumes the timer if currently [TimerStatus.paused].
  void resume() {
    _ensureNotDisposed();
    if (_state.status != TimerStatus.paused) {
      return;
    }
    _state = _state.copyWith(status: TimerStatus.running);
    _startTicker();
    _emitState();
    _emitEvent(
      TimerResumedEvent(
        timerId: id,
        elapsed: _state.elapsed,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Stops the timer without clearing current elapsed progress.
  void stop() {
    _ensureNotDisposed();
    if (_state.status == TimerStatus.stopped ||
        _state.status == TimerStatus.idle) {
      return;
    }
    _stopTicker();
    _state = _state.copyWith(status: TimerStatus.stopped);
    _emitState();
    _emitEvent(
      TimerStoppedEvent(
        timerId: id,
        elapsed: _state.elapsed,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Resets the timer back to [TimerStatus.idle].
  void reset() {
    _ensureNotDisposed();
    _stopTicker();
    onResetState();
    _emitState();
    _emitEvent(TimerResetEvent(timerId: id, timestamp: _clock.now()));
  }

  /// Releases ticker handles and closes streams permanently.
  Future<void> dispose() async {
    if (_state.status == TimerStatus.disposed) {
      return;
    }
    _stopTicker();
    _state = _state.copyWith(status: TimerStatus.disposed);
    await _tickController.close();
    await _stateController.close();
  }

  /// Subclass hook invoked on each [delta] tick while running.
  void onHandleTick(Duration delta);

  /// Subclass hook invoked during [reset] or restart to reset state fields.
  void onResetState();

  /// Updates state from subclass and emits notifications.
  void updateState(TimerState nextState, {bool isTick = false}) {
    _state = nextState;
    _emitState();
    if (isTick) {
      if (!_tickController.isClosed) {
        _tickController.add(_state);
      }
      _onTickCallback?.call(_state);
      if (emitTickEvents) {
        _emitEvent(TimerTickEvent(state: _state, timestamp: _clock.now()));
      }
    }
  }

  /// Completes the timer from a subclass once its target is reached.
  void markCompleted(TimerState completedState) {
    _stopTicker();
    _state = completedState.copyWith(status: TimerStatus.completed);
    _emitState();
    if (!_tickController.isClosed) {
      _tickController.add(_state);
    }
    _onTickCallback?.call(_state);
    _onCompleteCallback?.call();
    _emitEvent(
      TimerCompletedEvent(
        timerId: id,
        elapsed: _state.elapsed,
        timestamp: _clock.now(),
      ),
    );
  }

  void _startTicker() {
    _stopTicker();
    _handle = _ticker.startPeriodic(tickInterval, (delta) {
      if (_state.status != TimerStatus.running) {
        return;
      }
      onHandleTick(delta);
    });
  }

  void _stopTicker() {
    _handle?.cancel();
    _handle = null;
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _emitEvent(GameEvent event) {
    final bus = _eventBus;
    if (bus != null && !bus.isDisposed) {
      bus.emit(event);
    }
  }

  void _ensureNotDisposed() {
    if (_state.status == TimerStatus.disposed) {
      throw TimerException('Timer "$id" has already been disposed.');
    }
  }
}

/// Count-up timer tracking elapsed active duration, with optional [maxDuration].
class StopwatchTimer extends GameTimer {
  /// Creates a [StopwatchTimer].
  StopwatchTimer({
    required super.id,
    this.maxDuration,
    super.tickInterval = const Duration(milliseconds: 100),
    super.ticker,
    super.clock,
    super.eventBus,
    super.emitTickEvents,
    super.onTick,
    super.onComplete,
  }) {
    if (maxDuration != null && maxDuration! <= Duration.zero) {
      throw TimerException(
        'StopwatchTimer "$id" maxDuration must be greater than Duration.zero.',
      );
    }
    initState(
      TimerState(
        id: id,
        status: TimerStatus.idle,
        elapsed: Duration.zero,
        totalDuration: maxDuration,
        remaining: maxDuration,
      ),
    );
  }

  /// Optional ceiling duration at which the stopwatch auto-completes.
  final Duration? maxDuration;

  @override
  void onHandleTick(Duration delta) {
    var nextElapsed = state.elapsed + delta;
    final nextTicks = state.tickCount + 1;
    final limit = maxDuration;

    if (limit != null && nextElapsed >= limit) {
      nextElapsed = limit;
      markCompleted(
        state.copyWith(
          elapsed: nextElapsed,
          remaining: Duration.zero,
          tickCount: nextTicks,
        ),
      );
      return;
    }

    updateState(
      state.copyWith(
        elapsed: nextElapsed,
        remaining: limit == null ? null : limit - nextElapsed,
        tickCount: nextTicks,
      ),
      isTick: true,
    );
  }

  @override
  void onResetState() {
    initState(
      TimerState(
        id: id,
        status: TimerStatus.idle,
        elapsed: Duration.zero,
        totalDuration: maxDuration,
        remaining: maxDuration,
      ),
    );
  }
}

/// Repeating interval timer firing on each [period] up to optional [maxTicks].
class PeriodicTimer extends GameTimer {
  /// Creates a [PeriodicTimer].
  PeriodicTimer({
    required super.id,
    required this.period,
    this.maxTicks,
    Duration? tickInterval,
    super.ticker,
    super.clock,
    super.eventBus,
    super.emitTickEvents,
    super.onTick,
    super.onComplete,
  }) : super(tickInterval: tickInterval ?? period) {
    if (period <= Duration.zero) {
      throw TimerException(
        'PeriodicTimer "$id" period must be greater than Duration.zero.',
      );
    }
    if (maxTicks != null && maxTicks! <= 0) {
      throw TimerException(
        'PeriodicTimer "$id" maxTicks must be greater than zero.',
      );
    }
    initState(
      TimerState(
        id: id,
        status: TimerStatus.idle,
        elapsed: Duration.zero,
        totalDuration: maxTicks == null ? null : period * maxTicks!,
      ),
    );
  }

  /// Interval between logical periodic triggers.
  final Duration period;

  /// Optional maximum number of periodic ticks before completing.
  final int? maxTicks;

  Duration _accumulated = Duration.zero;

  @override
  void onHandleTick(Duration delta) {
    _accumulated += delta;
    var nextElapsed = state.elapsed + delta;
    var ticks = state.tickCount;
    var emittedPeriodTick = false;

    while (_accumulated >= period) {
      _accumulated -= period;
      ticks += 1;
      emittedPeriodTick = true;

      if (maxTicks != null && ticks >= maxTicks!) {
        nextElapsed = period * maxTicks!;
        markCompleted(state.copyWith(elapsed: nextElapsed, tickCount: ticks));
        return;
      }

      updateState(
        state.copyWith(elapsed: nextElapsed, tickCount: ticks),
        isTick: true,
      );
    }

    if (!emittedPeriodTick) {
      updateState(state.copyWith(elapsed: nextElapsed));
    }
  }

  @override
  void onResetState() {
    _accumulated = Duration.zero;
    initState(
      TimerState(
        id: id,
        status: TimerStatus.idle,
        elapsed: Duration.zero,
        totalDuration: maxTicks == null ? null : period * maxTicks!,
      ),
    );
  }
}

/// Manages lifecycle-bound timers for a [GameForge] instance.
///
/// Automatically pauses running timers when the game pauses (when
/// `pauseTimersOnGamePause` is enabled) and resumes only timers that were
/// paused by the game pause rather than manually paused beforehand.
class GameTimerManager extends GameModule {
  /// Creates a [GameTimerManager].
  GameTimerManager({
    this.pauseOnGamePause = true,
    GameTicker ticker = const SystemGameTicker(),
    GameClock clock = const SystemGameClock(),
    GameEventBus? eventBus,
    IdGenerator? idGenerator,
  }) : _ticker = ticker,
       _clock = clock,
       _eventBus = eventBus,
       _idGenerator = idGenerator ?? SequentialIdGenerator();

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'timers';

  /// Whether game pause/resume automatically pauses/resumes active timers.
  final bool pauseOnGamePause;

  final GameTicker _ticker;
  GameClock _clock;
  GameEventBus? _eventBus;
  IdGenerator _idGenerator;

  final Map<String, GameTimer> _timers = {};
  final Set<String> _pausedByGame = {};
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Unmodifiable view of all registered timers keyed by ID.
  Map<String, GameTimer> get timers =>
      Map<String, GameTimer>.unmodifiable(_timers);

  @override
  void onInitialize(GameModuleContext context) {
    _eventBus ??= context.events;
    _clock = context.clock;
    _idGenerator = context.idGenerator;
  }

  @override
  void onPause() {
    if (!pauseOnGamePause) {
      return;
    }
    _pausedByGame.clear();
    for (final timer in _timers.values) {
      if (timer.status == TimerStatus.running) {
        timer.pause();
        _pausedByGame.add(timer.id);
      }
    }
  }

  @override
  void onResume() {
    if (!pauseOnGamePause) {
      return;
    }
    final toResume = List<String>.of(_pausedByGame);
    _pausedByGame.clear();
    for (final timerId in toResume) {
      final timer = _timers[timerId];
      if (timer != null && timer.status == TimerStatus.paused) {
        timer.resume();
      }
    }
  }

  @override
  void onReset() {
    _pausedByGame.clear();
    for (final timer in _timers.values) {
      if (timer.status != TimerStatus.disposed) {
        timer.reset();
      }
    }
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Creates, registers, and returns a new [CountdownTimer].
  CountdownTimer countdown({
    required Duration duration,
    String? id,
    Duration tickInterval = const Duration(milliseconds: 100),
    bool autoStart = false,
    bool emitTickEvents = false,
    void Function(TimerState state)? onTick,
    void Function()? onComplete,
  }) {
    final timer = CountdownTimer(
      id: id ?? _idGenerator.nextId('countdown'),
      duration: duration,
      tickInterval: tickInterval,
      ticker: _ticker,
      clock: _clock,
      eventBus: _eventBus,
      emitTickEvents: emitTickEvents,
      onTick: onTick,
      onComplete: onComplete,
    );
    register(timer);
    if (autoStart) {
      timer.start();
    }
    return timer;
  }

  /// Creates, registers, and returns a new [StopwatchTimer].
  StopwatchTimer stopwatch({
    String? id,
    Duration? maxDuration,
    Duration tickInterval = const Duration(milliseconds: 100),
    bool autoStart = false,
    bool emitTickEvents = false,
    void Function(TimerState state)? onTick,
    void Function()? onComplete,
  }) {
    final timer = StopwatchTimer(
      id: id ?? _idGenerator.nextId('stopwatch'),
      maxDuration: maxDuration,
      tickInterval: tickInterval,
      ticker: _ticker,
      clock: _clock,
      eventBus: _eventBus,
      emitTickEvents: emitTickEvents,
      onTick: onTick,
      onComplete: onComplete,
    );
    register(timer);
    if (autoStart) {
      timer.start();
    }
    return timer;
  }

  /// Creates, registers, and returns a new [PeriodicTimer].
  PeriodicTimer periodic({
    required Duration period,
    String? id,
    int? maxTicks,
    Duration? tickInterval,
    bool autoStart = false,
    bool emitTickEvents = false,
    void Function(TimerState state)? onTick,
    void Function()? onComplete,
  }) {
    final timer = PeriodicTimer(
      id: id ?? _idGenerator.nextId('periodic'),
      period: period,
      maxTicks: maxTicks,
      tickInterval: tickInterval,
      ticker: _ticker,
      clock: _clock,
      eventBus: _eventBus,
      emitTickEvents: emitTickEvents,
      onTick: onTick,
      onComplete: onComplete,
    );
    register(timer);
    if (autoStart) {
      timer.start();
    }
    return timer;
  }

  /// Registers an externally constructed [GameTimer] for lifecycle management.
  void register(GameTimer timer) {
    _ensureNotDisposed();
    if (_timers.containsKey(timer.id)) {
      throw TimerException(
        'A timer with id "${timer.id}" is already registered.',
      );
    }
    _timers[timer.id] = timer;
  }

  /// Returns a registered timer by [id], or `null`.
  GameTimer? get(String id) => _timers[id];

  /// Removes and disposes the timer identified by [id], if present.
  Future<void> remove(String id) async {
    _pausedByGame.remove(id);
    final timer = _timers.remove(id);
    if (timer != null) {
      await timer.dispose();
    }
  }

  /// Disposes all managed timers and prevents further registrations.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _pausedByGame.clear();
    final timers = List<GameTimer>.of(_timers.values);
    _timers.clear();
    for (final timer in timers) {
      await timer.dispose();
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot use GameTimerManager after it has been disposed.',
      );
    }
  }
}
