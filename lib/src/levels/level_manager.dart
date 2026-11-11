import 'dart:async';
import 'dart:math' as math;

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../persistence/serialization.dart';
import '../utils/game_clock.dart';
import 'level_config.dart';
import 'level_event.dart';
import 'level_state.dart';

/// Manages level configuration, unlocking, completion, star ratings, level
/// scores, and customizable progression strategies.
class LevelManager extends GameModule {
  /// Creates a [LevelManager] from [levels] (or [maxLevels] sequential levels).
  LevelManager({
    List<LevelConfig>? levels,
    int maxLevels = 10,
    LevelProgressionStrategy progressionStrategy =
        const SequentialLevelProgression(),
    GameEventBus? eventBus,
    GameClock clock = const SystemGameClock(),
  }) : _progressionStrategy = progressionStrategy,
       _eventBus = eventBus,
       _clock = clock,
       _levels = List<LevelConfig>.unmodifiable(
         levels ?? LevelConfig.generateSequential(maxLevels),
       ) {
    if (_levels.isEmpty) {
      throw const GameConfigurationException(
        'LevelManager requires at least one LevelConfig.',
      );
    }

    final seenIds = <String>{};
    final seenNumbers = <int>{};
    for (var i = 0; i < _levels.length; i++) {
      final level = _levels[i];
      level.validate();
      if (!seenIds.add(level.id)) {
        throw GameConfigurationException(
          'Duplicate level ID "${level.id}" in LevelManager.',
        );
      }
      if (!seenNumbers.add(level.number)) {
        throw GameConfigurationException(
          'Duplicate level number ${level.number} in LevelManager.',
        );
      }
      _byId[level.id] = level;
      _byNumber[level.number] = level;
    }

    _state = _createInitialState();
  }

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'levels';

  final List<LevelConfig> _levels;
  final Map<String, LevelConfig> _byId = {};
  final Map<int, LevelConfig> _byNumber = {};
  final LevelProgressionStrategy _progressionStrategy;
  GameEventBus? _eventBus;
  GameClock _clock;

  final StreamController<LevelState> _stateController =
      StreamController<LevelState>.broadcast();

  late LevelState _state;
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Unmodifiable list of all configured levels.
  List<LevelConfig> get levels => _levels;

  /// Total number of configured levels.
  int get totalLevels => _levels.length;

  /// Current immutable [LevelState].
  LevelState get state => _state;

  /// Identifier of the currently selected level.
  String get currentLevelId => _state.currentLevelId;

  /// Configuration of the currently selected level.
  LevelConfig get currentLevel => _byId[_state.currentLevelId]!;

  /// Broadcast stream emitting whenever [state] updates.
  Stream<LevelState> get stream => _stateController.stream;

  @override
  void onInitialize(GameModuleContext context) {
    _eventBus ??= context.events;
    _clock = context.clock;
  }

  @override
  void onReset() {
    reset();
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Returns the [LevelConfig] for [levelId], or `null` if not found.
  LevelConfig? getConfig(String levelId) => _byId[levelId];

  /// Returns the [LevelConfig] for numeric [levelNumber], or `null`.
  LevelConfig? getConfigByNumber(int levelNumber) => _byNumber[levelNumber];

  /// Returns the [LevelProgress] for [levelId], or `null`.
  LevelProgress? progressFor(String levelId) => _state.progressById[levelId];

  /// Returns `true` if [levelId] is currently unlocked.
  bool isUnlocked(String levelId) => _state.isUnlocked(levelId);

  /// Returns `true` if numeric [levelNumber] is currently unlocked.
  bool isNumberUnlocked(int levelNumber) {
    final config = _byNumber[levelNumber];
    if (config == null) return false;
    return _state.isUnlocked(config.id);
  }

  /// Returns `true` if [levelId] has been completed.
  bool isCompleted(String levelId) => _state.isCompleted(levelId);

  /// Unlocks the level identified by numeric [levelNumber].
  void unlock(int levelNumber) {
    _ensureNotDisposed();
    final config = _requireByNumber(levelNumber);
    _unlockConfig(config);
  }

  /// Unlocks the level identified by [levelId].
  void unlockById(String levelId) {
    _ensureNotDisposed();
    final config = _requireById(levelId);
    _unlockConfig(config);
  }

  /// Locks the level identified by numeric [levelNumber].
  void lock(int levelNumber) {
    _ensureNotDisposed();
    final config = _requireByNumber(levelNumber);
    _lockConfig(config);
  }

  /// Locks the level identified by [levelId].
  void lockById(String levelId) {
    _ensureNotDisposed();
    final config = _requireById(levelId);
    _lockConfig(config);
  }

  /// Selects [levelNumber] as the current level.
  ///
  /// Throws [LevelLockedException] if the target level is locked unless
  /// [unlockIfLocked] is `true`.
  void select(int levelNumber, {bool unlockIfLocked = false}) {
    _ensureNotDisposed();
    final config = _requireByNumber(levelNumber);
    _selectConfig(config, unlockIfLocked: unlockIfLocked);
  }

  /// Selects [levelId] as the current level.
  ///
  /// Throws [LevelLockedException] if the target level is locked unless
  /// [unlockIfLocked] is `true`.
  void selectById(String levelId, {bool unlockIfLocked = false}) {
    _ensureNotDisposed();
    final config = _requireById(levelId);
    _selectConfig(config, unlockIfLocked: unlockIfLocked);
  }

  /// Marks a level as completed, recording [stars] and [score] and running
  /// the configured [LevelProgressionStrategy] to unlock follow-up levels.
  ///
  /// Defaults to [currentLevelId] if neither [levelId] nor [levelNumber] is
  /// specified.
  void complete({
    String? levelId,
    int? levelNumber,
    int stars = 0,
    int score = 0,
  }) {
    _ensureNotDisposed();
    final LevelConfig config;
    if (levelId != null) {
      config = _requireById(levelId);
    } else if (levelNumber != null) {
      config = _requireByNumber(levelNumber);
    } else {
      config = currentLevel;
    }

    if (!_state.isUnlocked(config.id)) {
      throw LevelLockedException(config.id);
    }
    if (stars < 0 || stars > config.maxStars) {
      throw LevelException(
        'Stars ($stars) for level "${config.id}" must be between 0 and '
        '${config.maxStars}.',
      );
    }
    if (score < 0) {
      throw LevelException(
        'Level score ($score) for "${config.id}" must be non-negative.',
      );
    }

    final now = _clock.now();
    final map = Map<String, LevelProgress>.of(_state.progressById);
    final existing = map[config.id]!;
    map[config.id] = existing.copyWith(
      isCompleted: true,
      stars: math.max(existing.stars, stars),
      bestScore: math.max(existing.bestScore, score),
      attempts: existing.attempts + 1,
      completedAt: now,
    );

    final updatedState = LevelState(
      currentLevelId: _state.currentLevelId,
      progressById: map,
    );

    final toUnlock = _progressionStrategy.resolveUnlocks(
      completedLevel: config,
      allLevels: _levels,
      state: updatedState,
    );

    final unlockedConfigs = <LevelConfig>[];
    for (final unlockId in toUnlock) {
      final target = _byId[unlockId];
      if (target == null) continue;
      final prev = map[unlockId]!;
      if (!prev.isUnlocked) {
        map[unlockId] = prev.copyWith(isUnlocked: true);
        unlockedConfigs.add(target);
      }
    }

    _state = LevelState(
      currentLevelId: _state.currentLevelId,
      progressById: map,
    );
    _emitState();

    for (final unlocked in unlockedConfigs) {
      _emitEvent(
        LevelUnlockedEvent(
          levelId: unlocked.id,
          levelNumber: unlocked.number,
          timestamp: now,
        ),
      );
    }

    _emitEvent(
      LevelCompletedEvent(
        levelId: config.id,
        levelNumber: config.number,
        stars: stars,
        score: score,
        newlyUnlockedLevelIds: unlockedConfigs.map((l) => l.id).toList(),
        timestamp: now,
      ),
    );
  }

  /// Advances [currentLevel] to the next eligible level using the configured
  /// [LevelProgressionStrategy], returning the newly selected [LevelConfig] or
  /// `null` if no next level is unlocked/available.
  LevelConfig? next({bool unlockNext = false}) {
    _ensureNotDisposed();
    final nextConfig = _progressionStrategy.resolveNextLevel(
      currentLevel: currentLevel,
      allLevels: _levels,
      state: _state,
    );
    if (nextConfig != null) {
      _selectConfig(nextConfig, unlockIfLocked: unlockNext);
      return nextConfig;
    }

    if (unlockNext) {
      final idx = _levels.indexWhere((l) => l.id == currentLevel.id);
      if (idx != -1 && idx + 1 < _levels.length) {
        final fallback = _levels[idx + 1];
        _selectConfig(fallback, unlockIfLocked: true);
        return fallback;
      }
    }
    return null;
  }

  /// Resets all level progress back to initial defaults.
  void reset() {
    _ensureNotDisposed();
    _state = _createInitialState();
    _emitState();
  }

  @override
  Map<String, Object?> toSaveData() => _state.toJson();

  @override
  void fromSaveData(Map<String, Object?> data) {
    _ensureNotDisposed();
    final savedCurrentId = GameSerialization.readString(data, 'currentLevelId');
    if (!_byId.containsKey(savedCurrentId)) {
      throw SaveValidationException(
        'Saved currentLevelId "$savedCurrentId" does not exist in LevelManager.',
      );
    }

    final levelsMap = GameSerialization.readMap(data, 'levels');
    final restored = Map<String, LevelProgress>.of(
      _createInitialState().progressById,
    );

    for (final entry in levelsMap.entries) {
      final levelId = entry.key;
      final config = _byId[levelId];
      if (config == null) {
        // Ignore unknown deprecated level IDs safely when restoring.
        continue;
      }
      final raw = entry.value;
      if (raw is! Map<Object?, Object?>) {
        throw CorruptSaveDataException(
          'Expected map for level progress "$levelId".',
        );
      }
      final normalized = GameSerialization.normalizeMap(raw);
      final isUnlocked = GameSerialization.readBool(normalized, 'isUnlocked');
      final isCompleted = GameSerialization.readBool(normalized, 'isCompleted');
      final stars = GameSerialization.readInt(normalized, 'stars');
      final bestScore = GameSerialization.readInt(normalized, 'bestScore');
      final attempts = GameSerialization.readInt(
        normalized,
        'attempts',
        defaultValue: 0,
      );
      final completedAtStr = GameSerialization.readOptionalString(
        normalized,
        'completedAt',
      );
      final completedAt = completedAtStr == null
          ? null
          : DateTime.tryParse(completedAtStr);
      if (completedAtStr != null && completedAt == null) {
        throw CorruptSaveDataException(
          'Invalid completedAt timestamp for level "$levelId".',
        );
      }
      if (stars < 0 ||
          stars > config.maxStars ||
          bestScore < 0 ||
          attempts < 0) {
        throw SaveValidationException(
          'Saved metrics for level "$levelId" are out of bounds.',
        );
      }

      restored[levelId] = LevelProgress(
        levelId: levelId,
        isUnlocked: isUnlocked,
        isCompleted: isCompleted,
        stars: stars,
        bestScore: bestScore,
        attempts: attempts,
        completedAt: completedAt,
      );
    }

    _state = LevelState(currentLevelId: savedCurrentId, progressById: restored);
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

  LevelState _createInitialState() {
    final map = <String, LevelProgress>{};
    String? firstUnlockedId;
    final openAll = _progressionStrategy is OpenLevelProgression;
    for (var i = 0; i < _levels.length; i++) {
      final level = _levels[i];
      final unlocked = openAll || level.unlockedByDefault || i == 0;
      firstUnlockedId ??= unlocked ? level.id : null;
      map[level.id] = LevelProgress(levelId: level.id, isUnlocked: unlocked);
    }
    return LevelState(
      currentLevelId: firstUnlockedId ?? _levels.first.id,
      progressById: map,
    );
  }

  LevelConfig _requireById(String levelId) {
    final config = _byId[levelId];
    if (config == null) {
      throw LevelNotFoundException(levelId);
    }
    return config;
  }

  LevelConfig _requireByNumber(int number) {
    final config = _byNumber[number];
    if (config == null) {
      throw LevelNotFoundException(number);
    }
    return config;
  }

  void _unlockConfig(LevelConfig config) {
    final current = _state.progressById[config.id]!;
    if (current.isUnlocked) {
      return;
    }
    final map = Map<String, LevelProgress>.of(_state.progressById);
    map[config.id] = current.copyWith(isUnlocked: true);
    _state = LevelState(
      currentLevelId: _state.currentLevelId,
      progressById: map,
    );
    _emitState();
    _emitEvent(
      LevelUnlockedEvent(
        levelId: config.id,
        levelNumber: config.number,
        timestamp: _clock.now(),
      ),
    );
  }

  void _lockConfig(LevelConfig config) {
    final current = _state.progressById[config.id]!;
    if (!current.isUnlocked) {
      return;
    }
    final map = Map<String, LevelProgress>.of(_state.progressById);
    map[config.id] = current.copyWith(isUnlocked: false);
    _state = LevelState(
      currentLevelId: _state.currentLevelId,
      progressById: map,
    );
    _emitState();
    _emitEvent(
      LevelLockedEvent(
        levelId: config.id,
        levelNumber: config.number,
        timestamp: _clock.now(),
      ),
    );
  }

  void _selectConfig(LevelConfig config, {required bool unlockIfLocked}) {
    if (!_state.isUnlocked(config.id)) {
      if (unlockIfLocked) {
        _unlockConfig(config);
      } else {
        throw LevelLockedException(config.id);
      }
    }
    final previousId = _state.currentLevelId;
    if (previousId == config.id) {
      return;
    }
    _state = LevelState(
      currentLevelId: config.id,
      progressById: _state.progressById,
    );
    _emitState();
    _emitEvent(
      CurrentLevelChangedEvent(
        previousLevelId: previousId,
        newLevelId: config.id,
        newLevelNumber: config.number,
        timestamp: _clock.now(),
      ),
    );
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
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot use LevelManager after it has been disposed.',
      );
    }
  }
}
