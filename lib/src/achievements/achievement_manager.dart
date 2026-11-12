import 'dart:async';
import 'dart:math' as math;

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../persistence/serialization.dart';
import '../rewards/reward_manager.dart';
import '../utils/game_clock.dart';
import '../utils/security.dart';
import '../utils/validators.dart';
import 'achievement.dart';
import 'achievement_progress.dart';

/// Manages achievement registrations, incremental progress tracking, custom
/// unlock conditions, reward granting on unlock, and persistence.
class AchievementManager extends GameModule {
  /// Creates an [AchievementManager].
  AchievementManager({
    List<Achievement> achievements = const [],
    RewardManager? rewardManager,
    GameEventBus? eventBus,
    GameClock clock = const SystemGameClock(),
  }) : _rewardManager = rewardManager,
       _eventBus = eventBus,
       _clock = clock {
    registerAll(achievements);
    _commitState();
  }

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'achievements';

  final Map<String, Achievement> _definitions = {};
  final Map<String, AchievementProgress> _progress = {};
  RewardManager? _rewardManager;
  GameEventBus? _eventBus;
  GameClock _clock;

  final StreamController<AchievementProgress> _progressController =
      StreamController<AchievementProgress>.broadcast();
  final StreamController<AchievementState> _stateController =
      StreamController<AchievementState>.broadcast();

  late AchievementState _state;
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Current immutable [AchievementState].
  AchievementState get state => _state;

  /// Unmodifiable list of registered [Achievement] definitions.
  List<Achievement> get definitions =>
      List<Achievement>.unmodifiable(_definitions.values);

  /// Unmodifiable list of all achievement progress entries.
  List<AchievementProgress> get allProgress =>
      List<AchievementProgress>.unmodifiable(_progress.values);

  /// Broadcast stream emitting whenever any individual achievement updates.
  Stream<AchievementProgress> get progressStream => _progressController.stream;

  /// Broadcast stream emitting the full [AchievementState] on changes.
  Stream<AchievementState> get stream => _stateController.stream;

  @override
  void onInitialize(GameModuleContext context) {
    _eventBus ??= context.events;
    _clock = context.clock;
    _rewardManager ??= context.findModule<RewardManager>();
  }

  @override
  void onReset() {
    reset();
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Registers a single [achievement] definition.
  ///
  /// Throws [DuplicateAchievementException] if an achievement with the same ID
  /// is already registered.
  void register(Achievement achievement) {
    _ensureNotDisposed();
    achievement.validate();
    if (_definitions.containsKey(achievement.id)) {
      throw DuplicateAchievementException(achievement.id);
    }
    _definitions[achievement.id] = achievement;
    _progress[achievement.id] = AchievementProgress(
      achievementId: achievement.id,
      currentValue: 0,
      targetValue: achievement.targetValue,
    );
    _commitState();
  }

  /// Registers all [achievements].
  void registerAll(List<Achievement> achievements) {
    for (final achievement in achievements) {
      register(achievement);
    }
  }

  /// Returns the [Achievement] definition for [id], or `null`.
  Achievement? getDefinition(String id) => _definitions[id];

  /// Returns the [AchievementProgress] for [id], or `null`.
  AchievementProgress? getProgress(String id) => _progress[id];

  /// Returns `true` if [id] is registered and unlocked.
  bool isUnlocked(String id) => _progress[id]?.isUnlocked ?? false;

  /// Increments progress on [id] by [amount] (default `1`).
  ///
  /// Automatically unlocks the achievement once its condition is satisfied.
  AchievementProgress increment(String id, {int amount = 1}) {
    _ensureNotDisposed();
    if (amount <= 0) {
      throw AchievementException(
        'Increment amount for "$id" must be positive (got $amount).',
      );
    }
    final existing = _requireProgress(id);
    if (existing.isUnlocked) {
      return existing;
    }
    final nextValue = Validators.safeAddInt(
      existing.currentValue,
      amount,
      'Achievement progress for "$id"',
      min: 0,
      max: GameSecurity.maxSafeInteger,
      exceptionBuilder: (message) => AchievementException(message),
    );
    return setProgress(id, nextValue);
  }

  /// Sets absolute progress on [id] to [value] (clamped at `targetValue`).
  AchievementProgress setProgress(String id, int value) {
    _ensureNotDisposed();
    if (value < 0) {
      throw AchievementException(
        'Progress value for "$id" cannot be negative (got $value).',
      );
    }
    final definition = _requireDefinition(id);
    final existing = _requireProgress(id);
    if (existing.isUnlocked) {
      return existing;
    }

    final clamped = math.min(value, definition.targetValue);
    final previousValue = existing.currentValue;
    var updated = existing.copyWith(currentValue: clamped);
    _progress[id] = updated;

    if (clamped != previousValue) {
      _emitProgress(updated);
      _emitEvent(
        AchievementProgressEvent(
          achievement: definition,
          previousValue: previousValue,
          currentValue: clamped,
          targetValue: definition.targetValue,
          timestamp: _clock.now(),
        ),
      );
    }

    final context = AchievementEvaluationContext(
      currentProgress: clamped,
      targetValue: definition.targetValue,
    );
    if (definition.condition.isSatisfied(context)) {
      updated = _performUnlock(definition, updated);
    } else {
      _commitState();
    }
    return updated;
  }

  /// Immediately unlocks achievement [id] and grants any associated reward.
  ///
  /// Calling [unlock] on an already unlocked achievement is a safe no-op.
  AchievementProgress unlock(String id) {
    _ensureNotDisposed();
    final definition = _requireDefinition(id);
    final existing = _requireProgress(id);
    if (existing.isUnlocked) {
      return existing;
    }
    return _performUnlock(definition, existing);
  }

  /// Evaluates all locked achievements against custom game metrics/context.
  ///
  /// Returns the list of achievements newly unlocked during this pass.
  List<Achievement> evaluate({
    int? score,
    int? highScore,
    int? completedLevelsCount,
    int? totalCoinsEarned,
    Map<String, Object?> customData = const {},
  }) {
    _ensureNotDisposed();
    final newlyUnlocked = <Achievement>[];

    for (final definition in _definitions.values) {
      final current = _progress[definition.id]!;
      if (current.isUnlocked) {
        continue;
      }

      final evalContext = AchievementEvaluationContext(
        currentProgress: current.currentValue,
        targetValue: definition.targetValue,
        score: score,
        highScore: highScore,
        completedLevelsCount: completedLevelsCount,
        totalCoinsEarned: totalCoinsEarned,
        customData: customData,
      );

      final computed = definition.condition.computeProgress(evalContext);
      var latest = current;
      if (computed != null && computed > current.currentValue) {
        latest = setProgress(definition.id, computed);
      }

      if (!latest.isUnlocked && definition.condition.isSatisfied(evalContext)) {
        _performUnlock(definition, latest);
        newlyUnlocked.add(definition);
      } else if (latest.isUnlocked && !current.isUnlocked) {
        newlyUnlocked.add(definition);
      }
    }

    return newlyUnlocked;
  }

  /// Resets all achievement progress back to zero and locked state.
  void reset() {
    _ensureNotDisposed();
    for (final entry in _definitions.entries) {
      _progress[entry.key] = AchievementProgress(
        achievementId: entry.key,
        currentValue: 0,
        targetValue: entry.value.targetValue,
      );
    }
    _commitState();
  }

  @override
  Map<String, Object?> toSaveData() => _state.toJson();

  @override
  void fromSaveData(Map<String, Object?> data) {
    _ensureNotDisposed();
    final entriesMap = GameSerialization.readMap(data, 'entries');
    final restored = <String, AchievementProgress>{
      for (final entry in _definitions.entries)
        entry.key: AchievementProgress(
          achievementId: entry.key,
          currentValue: 0,
          targetValue: entry.value.targetValue,
        ),
    };

    for (final entry in entriesMap.entries) {
      final achievementId = entry.key;
      final definition = _definitions[achievementId];
      if (definition == null) {
        // Safely ignore retired achievement IDs not registered in current build.
        continue;
      }
      final raw = entry.value;
      if (raw is! Map<Object?, Object?>) {
        throw CorruptSaveDataException(
          'Expected map for achievement "$achievementId".',
        );
      }
      final normalized = GameSerialization.normalizeMap(raw);
      final currentValue = GameSerialization.readInt(
        normalized,
        'currentValue',
      );
      final isUnlocked = GameSerialization.readBool(normalized, 'isUnlocked');
      final unlockedAtStr = GameSerialization.readOptionalString(
        normalized,
        'unlockedAt',
      );
      final unlockedAt = unlockedAtStr == null
          ? null
          : DateTime.tryParse(unlockedAtStr);
      if (unlockedAtStr != null && unlockedAt == null) {
        throw CorruptSaveDataException(
          'Invalid unlockedAt timestamp for achievement "$achievementId".',
        );
      }
      if (currentValue < 0 || currentValue > definition.targetValue) {
        throw SaveValidationException(
          'Saved progress ($currentValue) for achievement "$achievementId" '
          'must be within [0, ${definition.targetValue}].',
        );
      }

      restored[achievementId] = AchievementProgress(
        achievementId: achievementId,
        currentValue: isUnlocked ? definition.targetValue : currentValue,
        targetValue: definition.targetValue,
        isUnlocked: isUnlocked,
        unlockedAt: unlockedAt,
      );
    }

    _progress
      ..clear()
      ..addAll(restored);
    _commitState();
  }

  /// Releases resources owned by this manager.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _progressController.close();
    await _stateController.close();
  }

  AchievementProgress _performUnlock(
    Achievement definition,
    AchievementProgress current,
  ) {
    final now = _clock.now();
    final unlocked = current.copyWith(
      currentValue: definition.targetValue,
      isUnlocked: true,
      unlockedAt: now,
    );
    _progress[definition.id] = unlocked;
    _commitState();
    _emitProgress(unlocked);

    if (definition.reward != null && _rewardManager != null) {
      final reward = definition.reward!;
      if (!reward.oneTime ||
          reward.id == null ||
          !_rewardManager!.isClaimed(reward.id!)) {
        _rewardManager!.grant(reward);
      }
    }

    _emitEvent(
      AchievementUnlockedEvent(
        achievement: definition,
        unlockedAt: now,
        timestamp: now,
      ),
    );
    return unlocked;
  }

  Achievement _requireDefinition(String id) {
    final def = _definitions[id];
    if (def == null) {
      throw AchievementNotFoundException(id);
    }
    return def;
  }

  AchievementProgress _requireProgress(String id) {
    final progress = _progress[id];
    if (progress == null) {
      throw AchievementNotFoundException(id);
    }
    return progress;
  }

  void _commitState() {
    _state = AchievementState(entries: _progress);
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _emitProgress(AchievementProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
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
        'Cannot use AchievementManager after it has been disposed.',
      );
    }
  }
}
