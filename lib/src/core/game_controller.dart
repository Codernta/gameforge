import 'dart:async';

import '../achievements/achievement.dart';
import '../achievements/achievement_manager.dart';
import '../audio/game_audio.dart';
import '../health/health_manager.dart';
import '../health/health_state.dart';
import '../input/game_input_handler.dart';
import '../inventory/inventory_manager.dart';
import '../levels/level_config.dart';
import '../levels/level_manager.dart';
import '../persistence/game_save_data.dart';
import '../persistence/game_storage.dart';
import '../persistence/memory_game_storage.dart';
import '../rewards/reward.dart';
import '../rewards/reward_manager.dart';
import '../score/score_manager.dart';
import '../score/score_state.dart';
import '../session/game_session.dart';
import '../timer/game_timer.dart';
import '../timer/timer_state.dart';
import '../utils/game_clock.dart';
import '../utils/id_generator.dart';
import 'game_config.dart';
import 'game_event.dart';
import 'game_event_bus.dart';
import 'game_exception.dart';
import 'game_module.dart';
import 'game_state.dart';
import 'game_status.dart';

/// Central GameForge gameplay controller coordinating lifecycle, built-in
/// gameplay modules, custom modules, events, audio, input, and persistence.
class GameForge {
  /// Creates an isolated, configurable [GameForge] instance.
  GameForge({
    this.config = const GameConfig(),
    GameStorage? storage,
    GameAudioService? audio,
    GameClock clock = const SystemGameClock(),
    GameTicker ticker = const SystemGameTicker(),
    GameEventBus? eventBus,
    IdGenerator? idGenerator,
    ScoreRules? scoreRules,
    HealthConfig? healthConfig,
    LevelProgressionStrategy levelProgressionStrategy =
        const SequentialLevelProgression(),
    List<Achievement> achievements = const [],
    List<GameReward> initialPendingRewards = const [],
    List<GameModule> modules = const [],
    List<SaveMigration> saveMigrations = const [],
    bool disposeEventBusOnDispose = true,
  }) : _clock = clock,
       _ticker = ticker,
       _idGenerator = idGenerator ?? RandomIdGenerator(),
       _storage = storage ?? MemoryGameStorage(),
       _audio = audio ?? NoopGameAudioService(),
       _events = eventBus ?? GameEventBus(),
       _migrationRunner = SaveMigrationRunner(saveMigrations),
       _disposeEventBusOnDispose = disposeEventBusOnDispose {
    config.validate();

    _score = ScoreManager(
      rules: scoreRules ?? config.toScoreRules(),
      eventBus: _events,
      clock: _clock,
      onStateChanged: _handleScoreChanged,
    );
    _health = HealthManager(
      config: healthConfig ?? config.toHealthConfig(),
      eventBus: _events,
      clock: _clock,
      onStateChanged: _handleHealthChanged,
    );
    _levels = LevelManager(
      levels: config.levelConfigs,
      maxLevels: config.maxLevels,
      progressionStrategy: levelProgressionStrategy,
      eventBus: _events,
      clock: _clock,
    );
    _inventory = InventoryManager(
      capacity: config.inventoryCapacity,
      eventBus: _events,
      clock: _clock,
    );
    _rewards = RewardManager(
      scoreManager: _score,
      inventoryManager: _inventory,
      eventBus: _events,
      clock: _clock,
      idGenerator: _idGenerator,
      initialPendingRewards: initialPendingRewards,
    );
    _achievements = AchievementManager(
      achievements: achievements,
      rewardManager: _rewards,
      eventBus: _events,
      clock: _clock,
    );
    _timers = GameTimerManager(
      pauseOnGamePause: config.pauseTimersOnGamePause,
      ticker: _ticker,
      clock: _clock,
      eventBus: _events,
      idGenerator: _idGenerator,
    );
    _session = GameSessionManager(
      autoManageLifecycle: config.autoStartSession,
      clock: _clock,
      idGenerator: _idGenerator,
      eventBus: _events,
    );
    _input = GameInputHandler(eventBus: _events);

    _builtInModules = <GameModule>[
      _score,
      _health,
      _levels,
      _inventory,
      _rewards,
      _achievements,
      _timers,
      _session,
      _input,
    ];

    for (final builtIn in _builtInModules) {
      _modulesById[builtIn.id] = builtIn;
    }
    for (final custom in modules) {
      _registerCustomModule(custom);
    }
  }

  /// Static configuration used to initialize this controller.
  final GameConfig config;

  final GameClock _clock;
  final GameTicker _ticker;
  final IdGenerator _idGenerator;
  final GameStorage _storage;
  final GameAudioService _audio;
  final GameEventBus _events;
  final SaveMigrationRunner _migrationRunner;
  final bool _disposeEventBusOnDispose;

  late final ScoreManager _score;
  late final HealthManager _health;
  late final LevelManager _levels;
  late final InventoryManager _inventory;
  late final RewardManager _rewards;
  late final AchievementManager _achievements;
  late final GameTimerManager _timers;
  late final GameSessionManager _session;
  late final GameInputHandler _input;

  late final List<GameModule> _builtInModules;
  final List<GameModule> _customModules = [];
  final Map<String, GameModule> _modulesById = {};
  final List<StreamSubscription<Object?>> _internalSubscriptions = [];

  final StreamController<GameStatus> _statusController =
      StreamController<GameStatus>.broadcast();
  final StreamController<GameState> _stateController =
      StreamController<GameState>.broadcast();

  GameStatus _status = GameStatus.uninitialized;

  /// Current lifecycle status.
  GameStatus get status => _status;

  /// Broadcast stream emitting whenever [status] transitions.
  Stream<GameStatus> get statusStream => _statusController.stream;

  /// Current unified [GameState] snapshot.
  GameState get state => GameState(
    status: _status,
    score: _score.state,
    health: _health.state,
    levels: _levels.state,
    inventory: _inventory.state,
    rewards: _rewards.state,
    achievements: _achievements.state,
    session: _session.current,
    updatedAt: _clock.now(),
  );

  /// Broadcast stream emitting whenever any core gameplay module or status
  /// changes.
  Stream<GameState> get stateStream => _stateController.stream;

  /// Clock used for timestamps and deterministic timing.
  GameClock get clock => _clock;

  /// Event bus for strongly typed gameplay events.
  GameEventBus get events => _events;

  /// Storage backend used by [save] and [load].
  GameStorage get storage => _storage;

  /// Audio service interface used by this game.
  GameAudioService get audio => _audio;

  /// Score and combo manager.
  ScoreManager get score => _score;

  /// Health and lives manager.
  HealthManager get health => _health;

  /// Level progression manager.
  LevelManager get levels => _levels;

  /// Inventory and item manager.
  InventoryManager get inventory => _inventory;

  /// Reward manager.
  RewardManager get rewards => _rewards;

  /// Achievement manager.
  AchievementManager get achievements => _achievements;

  /// Lifecycle-bound timer manager.
  GameTimerManager get timers => _timers;

  /// Gameplay session and statistics manager.
  GameSessionManager get session => _session;

  /// Engine-independent input dispatcher.
  GameInputHandler get input => _input;

  /// Unmodifiable list of registered custom [GameModule]s.
  List<GameModule> get customModules =>
      List<GameModule>.unmodifiable(_customModules);

  /// Registers a custom [module] prior to [initialize].
  ///
  /// To attach a module dynamically after initialization, use [attachModule].
  void registerModule(GameModule module) {
    if (_status != GameStatus.uninitialized) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: null,
        operation: 'registerModule(${module.id})',
        message:
            'registerModule can only be called while uninitialized. Use '
            'attachModule() after initialize().',
      );
    }
    _registerCustomModule(module);
  }

  /// Registers and, if already initialized, asynchronously initializes a custom
  /// [module].
  Future<void> attachModule(GameModule module) async {
    _ensureNotDisposed('attachModule');
    _registerCustomModule(module);
    if (_status.isInitialized) {
      await module.onInitialize(_createModuleContext());
    }
  }

  /// Looks up a registered built-in or custom module by type [T].
  T? getModule<T extends GameModule>() {
    for (final module in _allModules) {
      if (module is T) {
        return module;
      }
    }
    return null;
  }

  /// Looks up a registered built-in or custom module by its [GameModule.id].
  GameModule? getModuleById(String id) => _modulesById[id];

  /// Initializes the game, audio service, and all registered modules.
  ///
  /// Transitions status from [GameStatus.uninitialized] ->
  /// [GameStatus.initializing] -> [GameStatus.ready].
  Future<void> initialize() async {
    _assertCanTransition(GameStatus.initializing, 'initialize');
    _transitionTo(GameStatus.initializing);

    final context = _createModuleContext();
    try {
      await _audio.initialize();
      for (final module in _allModules) {
        await module.onInitialize(context);
      }
      _wireInternalListeners();
      _transitionTo(GameStatus.ready);
      _emitState();
      _emitEvent(GameInitializedEvent(timestamp: _clock.now()));
    } catch (error, stackTrace) {
      await _cancelInternalSubscriptions();
      if (_status == GameStatus.initializing) {
        _transitionTo(GameStatus.uninitialized);
      }
      if (!_events.isDisposed) {
        _events.tryEmit(
          GameErrorEvent(
            error: error,
            errorStackTrace: stackTrace,
            timestamp: _clock.now(),
          ),
        );
      }
      rethrow;
    }
  }

  /// Starts gameplay, transitioning from [GameStatus.ready] to
  /// [GameStatus.running].
  void start() {
    _assertCanTransition(GameStatus.running, 'start');
    if (_status != GameStatus.ready) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: GameStatus.running.name,
        operation: 'start',
      );
    }
    _transitionTo(GameStatus.running);
    for (final module in _allModules) {
      module.onStart();
    }
    _emitState();
    _emitEvent(GameStartedEvent(timestamp: _clock.now()));
  }

  /// Pauses active gameplay, transitioning from [GameStatus.running] to
  /// [GameStatus.paused].
  void pause() {
    if (_status != GameStatus.running) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: GameStatus.paused.name,
        operation: 'pause',
      );
    }
    _transitionTo(GameStatus.paused);
    for (final module in _allModules) {
      module.onPause();
    }
    if (config.pauseAudioOnGamePause) {
      unawaited(_audio.pauseMusic());
    }
    _emitState();
    _emitEvent(GamePausedEvent(timestamp: _clock.now()));
  }

  /// Resumes paused gameplay, transitioning from [GameStatus.paused] to
  /// [GameStatus.running].
  void resume() {
    if (_status != GameStatus.paused) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: GameStatus.running.name,
        operation: 'resume',
      );
    }
    _transitionTo(GameStatus.running);
    for (final module in _allModules) {
      module.onResume();
    }
    if (config.pauseAudioOnGamePause) {
      unawaited(_audio.resumeMusic());
    }
    _emitState();
    _emitEvent(GameResumedEvent(timestamp: _clock.now()));
  }

  /// Marks gameplay as completed, transitioning from [GameStatus.running] or
  /// [GameStatus.paused] to [GameStatus.completed].
  void complete() {
    if (_status != GameStatus.running && _status != GameStatus.paused) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: GameStatus.completed.name,
        operation: 'complete',
      );
    }
    _transitionTo(GameStatus.completed);
    for (final module in _allModules) {
      module.onComplete();
    }
    _emitState();
    _emitEvent(GameCompletedEvent(timestamp: _clock.now()));
  }

  /// Transitions gameplay into [GameStatus.gameOver].
  void triggerGameOver({String? reason}) {
    if (_status != GameStatus.running && _status != GameStatus.paused) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: GameStatus.gameOver.name,
        operation: 'triggerGameOver',
      );
    }
    _transitionTo(GameStatus.gameOver);
    for (final module in _allModules) {
      module.onGameOver();
    }
    _emitState();
    _emitEvent(GameOverEvent(reason: reason, timestamp: _clock.now()));
  }

  /// Resets all modules and restarts the game.
  ///
  /// Allowed from [GameStatus.ready], [GameStatus.running],
  /// [GameStatus.paused], [GameStatus.completed], or [GameStatus.gameOver].
  /// When [autoStart] is `true` (default), immediately starts gameplay after
  /// resetting.
  void restart({bool autoStart = true}) {
    if (!_status.isInitialized) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: GameStatus.ready.name,
        operation: 'restart',
      );
    }

    _transitionTo(GameStatus.ready);
    for (final module in _allModules) {
      module.onReset();
    }
    _emitEvent(
      GameRestartedEvent(autoStarted: autoStart, timestamp: _clock.now()),
    );

    if (autoStart) {
      _transitionTo(GameStatus.running);
      for (final module in _allModules) {
        module.onStart();
      }
      _emitEvent(GameStartedEvent(timestamp: _clock.now()));
    }
    _emitState();
  }

  /// Captures an atomic snapshot of all built-in and custom module state and
  /// saves it to [storage] under [key] (defaulting to [GameConfig.saveKey]).
  Future<void> save({
    String? key,
    Map<String, Object?> metadata = const {},
  }) async {
    _ensureInitialized('save');
    final targetKey = key ?? config.saveKey;
    final saveData = createSaveData(metadata: metadata);
    await _storage.save(targetKey, saveData.toJson());
    _emitEvent(
      GameSavedEvent(
        key: targetKey,
        version: saveData.version,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Creates an in-memory [GameSaveData] snapshot of the current game state.
  GameSaveData createSaveData({Map<String, Object?> metadata = const {}}) {
    _ensureInitialized('createSaveData');
    final customData = <String, Map<String, Object?>>{};
    for (final module in _customModules) {
      final data = module.toSaveData();
      if (data != null) {
        customData[module.id] = data;
      }
    }
    return GameSaveData(
      version: config.saveVersion,
      savedAt: _clock.now(),
      score: _score.toSaveData(),
      health: _health.toSaveData(),
      levels: _levels.toSaveData(),
      inventory: _inventory.toSaveData(),
      rewards: _rewards.toSaveData(),
      achievements: _achievements.toSaveData(),
      session: _session.toSaveData(),
      modules: customData,
      metadata: metadata,
    );
  }

  /// Loads saved progress from [storage] under [key] (defaulting to
  /// [GameConfig.saveKey]), migrating older versions if needed.
  ///
  /// Returns `false` if no save entry exists at [key], or `true` once restored.
  /// If any module validation fails, all module states roll back atomically to
  /// their pre-load snapshots.
  Future<bool> load({String? key}) async {
    _ensureInitialized('load');
    final targetKey = key ?? config.saveKey;
    final raw = await _storage.read(targetKey);
    if (raw == null) {
      return false;
    }

    final migrated = _migrationRunner.migrateTo(
      rawData: raw,
      targetVersion: config.saveVersion,
    );
    final saveData = GameSaveData.fromJson(migrated);

    // Capture rollback snapshots prior to mutating any module.
    final rollback = createSaveData();
    _isLoadingSave = true;
    try {
      await _applySaveData(saveData);
    } catch (_) {
      await _applySaveData(rollback);
      rethrow;
    } finally {
      _isLoadingSave = false;
    }

    _emitState();
    _emitEvent(
      GameLoadedEvent(
        key: targetKey,
        version: saveData.version,
        timestamp: _clock.now(),
      ),
    );
    return true;
  }

  /// Deletes the save snapshot stored under [key] (or [GameConfig.saveKey]).
  Future<void> deleteSave({String? key}) {
    _ensureNotDisposed('deleteSave');
    return _storage.delete(key ?? config.saveKey);
  }

  /// Permanently disposes this [GameForge] instance, releasing all module
  /// subscriptions, timers, audio backend, and event bus streams.
  Future<void> dispose() async {
    if (_status == GameStatus.disposed) {
      return;
    }
    if (!_events.isDisposed) {
      _events.tryEmit(GameDisposedEvent(timestamp: _clock.now()));
    }
    _transitionTo(GameStatus.disposed);
    // Cancel active timers synchronously so Flutter widget disposal does not
    // observe pending periodic timers across async microtasks.
    for (final timer in _timers.timers.values) {
      if (timer.status == TimerStatus.running) {
        timer.stop();
      }
    }
    await _cancelInternalSubscriptions();

    for (final module in _customModules.reversed) {
      await module.onDispose();
    }
    for (final module in _builtInModules.reversed) {
      await module.onDispose();
    }

    await _audio.dispose();
    if (_disposeEventBusOnDispose) {
      await _events.dispose();
    }
    await _statusController.close();
    await _stateController.close();
  }

  List<GameModule> get _allModules => [..._builtInModules, ..._customModules];

  GameModuleContext _createModuleContext() {
    return GameModuleContext(
      events: _events,
      clock: _clock,
      idGenerator: _idGenerator,
      statusProvider: () => _status,
      moduleResolver: getModule,
    );
  }

  void _registerCustomModule(GameModule module) {
    if (module.id.trim().isEmpty) {
      throw const GameModuleException('Custom GameModule id cannot be empty.');
    }
    if (_modulesById.containsKey(module.id)) {
      throw GameModuleException(
        'A module with id "${module.id}" is already registered.',
      );
    }
    _modulesById[module.id] = module;
    _customModules.add(module);
  }

  void _wireInternalListeners() {
    _internalSubscriptions.addAll([
      _levels.stream.listen((_) => _emitState()),
      _inventory.stream.listen((_) => _emitState()),
      _rewards.stream.listen((_) => _emitState()),
      _achievements.stream.listen((_) => _emitState()),
      _session.stream.listen((_) => _emitState()),
    ]);
  }

  void _handleScoreChanged(ScoreState scoreState) {
    if (!_status.isInitialized || _status == GameStatus.disposed) {
      return;
    }
    if (_session.current.isOpen) {
      _session.setScore(scoreState.currentScore);
    }
    _emitState();
  }

  void _handleHealthChanged(HealthState healthState) {
    if (!_status.isInitialized || _status == GameStatus.disposed) {
      return;
    }
    _emitState();
    if (!_isLoadingSave &&
        config.autoGameOverOnZeroLives &&
        healthState.isDead &&
        (_status == GameStatus.running || _status == GameStatus.paused)) {
      triggerGameOver(reason: 'zero_lives');
    }
  }

  bool _isLoadingSave = false;

  Future<void> _cancelInternalSubscriptions() async {
    final subs = List<StreamSubscription<Object?>>.of(_internalSubscriptions);
    _internalSubscriptions.clear();
    for (final sub in subs) {
      await sub.cancel();
    }
  }

  Future<void> _applySaveData(GameSaveData saveData) async {
    if (saveData.score != null) {
      _score.fromSaveData(saveData.score!);
    }
    if (saveData.health != null) {
      _health.fromSaveData(saveData.health!);
    }
    if (saveData.levels != null) {
      _levels.fromSaveData(saveData.levels!);
    }
    if (saveData.inventory != null) {
      _inventory.fromSaveData(saveData.inventory!);
    }
    if (saveData.rewards != null) {
      _rewards.fromSaveData(saveData.rewards!);
    }
    if (saveData.achievements != null) {
      _achievements.fromSaveData(saveData.achievements!);
    }
    if (saveData.session != null) {
      _session.fromSaveData(saveData.session!);
    }
    for (final module in _customModules) {
      final data = saveData.modules[module.id];
      if (data != null) {
        await module.fromSaveData(data);
      }
    }
  }

  void _assertCanTransition(GameStatus next, String operation) {
    if (!_status.canTransitionTo(next)) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: next.name,
        operation: operation,
      );
    }
  }

  void _ensureInitialized(String operation) {
    if (!_status.isInitialized) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: null,
        operation: operation,
        message: 'GameForge must be initialized before calling $operation().',
      );
    }
  }

  void _ensureNotDisposed(String operation) {
    if (_status == GameStatus.disposed) {
      throw InvalidLifecycleTransitionException(
        from: _status.name,
        to: null,
        operation: operation,
        message: 'Cannot call $operation() after GameForge has been disposed.',
      );
    }
  }

  void _transitionTo(GameStatus next) {
    final previous = _status;
    if (previous == next) {
      return;
    }
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
    _emitEvent(
      GameStatusChangedEvent(
        previousStatus: previous,
        newStatus: next,
        timestamp: _clock.now(),
      ),
    );
  }

  void _emitState() {
    if (!_stateController.isClosed && _status != GameStatus.disposed) {
      _stateController.add(state);
    }
  }

  void _emitEvent(GameEvent event) {
    if (!_events.isDisposed) {
      _events.emit(event);
    }
  }
}
