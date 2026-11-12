import 'dart:async';

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../inventory/game_item.dart';
import '../inventory/inventory_manager.dart';
import '../persistence/serialization.dart';
import '../score/score_manager.dart';
import '../utils/game_clock.dart';
import '../utils/id_generator.dart';
import '../utils/security.dart';
import '../utils/validators.dart';
import 'reward.dart';
import 'reward_event.dart';

/// Callback handling [GameRewardType.custom] rewards.
typedef CustomRewardHandler = FutureOr<void> Function(GameReward reward);

/// Manages granting, queuing, claiming, coin spending, and duplicate-claim
/// prevention for [GameReward]s.
class RewardManager extends GameModule {
  /// Creates a [RewardManager].
  RewardManager({
    ScoreManager? scoreManager,
    InventoryManager? inventoryManager,
    GameEventBus? eventBus,
    GameClock clock = const SystemGameClock(),
    IdGenerator? idGenerator,
    List<GameReward> initialPendingRewards = const [],
  }) : _scoreManager = scoreManager,
       _inventoryManager = inventoryManager,
       _eventBus = eventBus,
       _clock = clock,
       _idGenerator = idGenerator ?? SequentialIdGenerator(initialValue: 0) {
    _state = RewardState(
      coinBalance: 0,
      totalCoinsEarned: 0,
      totalExperience: 0,
      claimedRewardIds: const {},
      pendingRewards: const [],
    );
    for (final reward in initialPendingRewards) {
      offer(reward);
    }
  }

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'rewards';

  ScoreManager? _scoreManager;
  InventoryManager? _inventoryManager;
  GameEventBus? _eventBus;
  GameClock _clock;
  IdGenerator _idGenerator;

  final Map<String, CustomRewardHandler> _customHandlers = {};
  final StreamController<RewardState> _stateController =
      StreamController<RewardState>.broadcast();

  late RewardState _state;
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Current immutable [RewardState].
  RewardState get state => _state;

  /// Current spendable coin balance.
  int get coinBalance => _state.coinBalance;

  /// Cumulative coins earned.
  int get totalCoinsEarned => _state.totalCoinsEarned;

  /// Cumulative experience points earned.
  int get totalExperience => _state.totalExperience;

  /// Set of reward IDs already claimed.
  Set<String> get claimedRewardIds => _state.claimedRewardIds;

  /// List of offered rewards pending claim.
  List<GameReward> get pendingRewards => _state.pendingRewards;

  /// Broadcast stream emitting whenever reward state changes.
  Stream<RewardState> get stream => _stateController.stream;

  @override
  void onInitialize(GameModuleContext context) {
    _eventBus ??= context.events;
    _clock = context.clock;
    _idGenerator = context.idGenerator;
    _scoreManager ??= context.findModule<ScoreManager>();
    _inventoryManager ??= context.findModule<InventoryManager>();
  }

  @override
  void onReset() {
    reset();
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Registers a custom handler invoked whenever a [GameReward.custom] with
  /// [customType] is granted or claimed.
  void registerHandler(String customType, CustomRewardHandler handler) {
    _ensureNotDisposed();
    if (customType.trim().isEmpty) {
      throw const RewardException('customType cannot be empty.');
    }
    _customHandlers[customType] = handler;
  }

  /// Checks whether [rewardId] has already been claimed.
  bool isClaimed(String rewardId) => _state.claimedRewardIds.contains(rewardId);

  /// Queues [reward] as a pending reward to be claimed later via [claim].
  ///
  /// Assigns a generated ID if [reward.id] is `null`. Throws
  /// [RewardAlreadyClaimedException] if [reward.oneTime] is `true` and it was
  /// already claimed.
  GameReward offer(GameReward reward) {
    _ensureNotDisposed();
    _assertNotAlreadyClaimed(reward);

    final assigned = reward.id == null
        ? reward.withId(_idGenerator.nextId('reward'))
        : reward;

    if (_state.pendingRewards.any((r) => r.id == assigned.id)) {
      throw RewardException(
        'Pending reward with id "${assigned.id}" is already queued.',
      );
    }

    final pending = List<GameReward>.of(_state.pendingRewards)..add(assigned);
    _state = RewardState(
      coinBalance: _state.coinBalance,
      totalCoinsEarned: _state.totalCoinsEarned,
      totalExperience: _state.totalExperience,
      claimedRewardIds: _state.claimedRewardIds,
      pendingRewards: pending,
    );
    _emitState();
    _emitEvent(RewardOfferedEvent(reward: assigned, timestamp: _clock.now()));
    return assigned;
  }

  /// Claims a pending reward previously added with [offer].
  void claim(String rewardId) {
    _ensureNotDisposed();
    final index = _state.pendingRewards.indexWhere((r) => r.id == rewardId);
    if (index == -1) {
      if (_state.claimedRewardIds.contains(rewardId)) {
        throw RewardAlreadyClaimedException(rewardId);
      }
      throw RewardNotFoundException(rewardId);
    }

    final reward = _state.pendingRewards[index];
    grant(reward);

    final remaining = List<GameReward>.of(_state.pendingRewards)
      ..removeAt(index);
    _state = RewardState(
      coinBalance: _state.coinBalance,
      totalCoinsEarned: _state.totalCoinsEarned,
      totalExperience: _state.totalExperience,
      claimedRewardIds: _state.claimedRewardIds,
      pendingRewards: remaining,
    );
    _emitState();
  }

  /// Claims all currently pending rewards in queue order.
  List<GameReward> claimAll() {
    _ensureNotDisposed();
    final snapshot = List<GameReward>.of(_state.pendingRewards);
    for (final reward in snapshot) {
      claim(reward.id!);
    }
    return snapshot;
  }

  /// Immediately grants [reward], applying coins, points, items, XP, bundles,
  /// and custom handlers atomically.
  ///
  /// Throws [RewardAlreadyClaimedException] if [reward] (or any nested reward
  /// in a bundle) is marked `oneTime` and was previously claimed.
  void grant(GameReward reward) {
    _ensureNotDisposed();
    _assertNotAlreadyClaimed(reward);

    var coinDelta = 0;
    var xpDelta = 0;
    var pointsDelta = 0;
    final itemsToAdd = <GameItem>[];
    final customToRun = <GameReward>[];
    final claimedIdsToAdd = <String>{};

    void collect(GameReward current) {
      if (current.oneTime && current.id != null) {
        claimedIdsToAdd.add(current.id!);
      } else if (current.id != null) {
        claimedIdsToAdd.add(current.id!);
      }

      switch (current.type) {
        case GameRewardType.coins:
          coinDelta = Validators.safeAddInt(
            coinDelta,
            current.amount,
            'Reward coins',
            min: 0,
            max: GameSecurity.maxSafeInteger,
            exceptionBuilder: (message) => RewardException(message),
          );
        case GameRewardType.experience:
          xpDelta = Validators.safeAddInt(
            xpDelta,
            current.amount,
            'Reward experience',
            min: 0,
            max: GameSecurity.maxSafeInteger,
            exceptionBuilder: (message) => RewardException(message),
          );
        case GameRewardType.points:
          pointsDelta = Validators.safeAddInt(
            pointsDelta,
            current.amount,
            'Reward points',
            min: 0,
            max: GameSecurity.maxSafeInteger,
            exceptionBuilder: (message) => RewardException(message),
          );
        case GameRewardType.item:
          if (current.item != null) {
            itemsToAdd.add(current.item!);
          }
        case GameRewardType.custom:
          customToRun.add(current);
        case GameRewardType.bundle:
          for (final child in current.rewards) {
            collect(child);
          }
      }
    }

    collect(reward);

    final nextCoinBalance = Validators.safeAddInt(
      _state.coinBalance,
      coinDelta,
      'Coin balance',
      min: 0,
      max: GameSecurity.maxSafeInteger,
      exceptionBuilder: (message) => RewardException(message),
    );
    final nextTotalCoinsEarned = Validators.safeAddInt(
      _state.totalCoinsEarned,
      coinDelta,
      'Total coins earned',
      min: 0,
      max: GameSecurity.maxSafeInteger,
      exceptionBuilder: (message) => RewardException(message),
    );
    final nextTotalExperience = Validators.safeAddInt(
      _state.totalExperience,
      xpDelta,
      'Total experience',
      min: 0,
      max: GameSecurity.maxSafeInteger,
      exceptionBuilder: (message) => RewardException(message),
    );

    // Apply external side effects before committing reward balances so failures
    // (such as full inventory or score overflow) roll back cleanly.
    if (itemsToAdd.isNotEmpty && _inventoryManager != null) {
      _inventoryManager!.addAll(itemsToAdd);
    }
    if (pointsDelta > 0 && _scoreManager != null) {
      _scoreManager!.add(pointsDelta, applyMultiplier: false);
    }

    for (final custom in customToRun) {
      final handler = _customHandlers[custom.customType];
      if (handler != null) {
        handler(custom);
      }
    }

    final updatedClaimed = Set<String>.of(_state.claimedRewardIds)
      ..addAll(claimedIdsToAdd);

    _state = RewardState(
      coinBalance: nextCoinBalance,
      totalCoinsEarned: nextTotalCoinsEarned,
      totalExperience: nextTotalExperience,
      claimedRewardIds: updatedClaimed,
      pendingRewards: _state.pendingRewards,
    );
    _emitState();
    _emitEvent(
      RewardGrantedEvent(
        reward: reward,
        coinBalance: _state.coinBalance,
        totalExperience: _state.totalExperience,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Deducts [amount] coins from [coinBalance], returning the remaining balance.
  ///
  /// Throws [RewardException] if [amount] is non-positive or exceeds
  /// [coinBalance].
  int spendCoins(int amount, {String? reason}) {
    _ensureNotDisposed();
    if (amount <= 0) {
      throw RewardException(
        'Coins to spend must be greater than zero (got $amount).',
      );
    }
    if (_state.coinBalance < amount) {
      throw RewardException(
        'Insufficient coins: need $amount, have ${_state.coinBalance}.',
      );
    }
    final remaining = _state.coinBalance - amount;
    _state = RewardState(
      coinBalance: remaining,
      totalCoinsEarned: _state.totalCoinsEarned,
      totalExperience: _state.totalExperience,
      claimedRewardIds: _state.claimedRewardIds,
      pendingRewards: _state.pendingRewards,
    );
    _emitState();
    _emitEvent(
      CoinsSpentEvent(
        amount: amount,
        remainingBalance: remaining,
        reason: reason,
        timestamp: _clock.now(),
      ),
    );
    return remaining;
  }

  /// Resets balances, claimed IDs, and pending rewards.
  void reset() {
    _ensureNotDisposed();
    _state = RewardState(
      coinBalance: 0,
      totalCoinsEarned: 0,
      totalExperience: 0,
      claimedRewardIds: const {},
      pendingRewards: const [],
    );
    _emitState();
  }

  @override
  Map<String, Object?> toSaveData() => _state.toJson();

  @override
  void fromSaveData(Map<String, Object?> data) {
    _ensureNotDisposed();
    final coinBalance = GameSerialization.readInt(data, 'coinBalance');
    final totalCoinsEarned = GameSerialization.readInt(
      data,
      'totalCoinsEarned',
    );
    final totalExperience = GameSerialization.readInt(data, 'totalExperience');
    if (coinBalance < 0 || totalCoinsEarned < 0 || totalExperience < 0) {
      throw const SaveValidationException(
        'Saved reward balances cannot be negative.',
      );
    }
    if (coinBalance > GameSecurity.maxSafeInteger ||
        totalCoinsEarned > GameSecurity.maxSafeInteger ||
        totalExperience > GameSecurity.maxSafeInteger) {
      throw const SaveValidationException(
        'Saved reward balances exceed safe integer bounds.',
      );
    }
    if (coinBalance > totalCoinsEarned) {
      throw const SaveValidationException(
        'Saved coinBalance cannot exceed totalCoinsEarned.',
      );
    }

    final rawClaimed = GameSerialization.readList(
      data,
      'claimedRewardIds',
      defaultValue: const [],
    );
    final claimedIds = <String>{};
    for (final entry in rawClaimed) {
      if (entry is! String) {
        throw const CorruptSaveDataException(
          'Expected string ID inside claimedRewardIds.',
        );
      }
      claimedIds.add(entry);
    }

    final rawPending = GameSerialization.readList(
      data,
      'pendingRewards',
      defaultValue: const [],
    );
    final pending = <GameReward>[];
    for (final entry in rawPending) {
      if (entry is! Map<Object?, Object?>) {
        throw const CorruptSaveDataException(
          'Expected map entry inside pendingRewards.',
        );
      }
      pending.add(GameReward.fromJson(GameSerialization.normalizeMap(entry)));
    }

    _state = RewardState(
      coinBalance: coinBalance,
      totalCoinsEarned: totalCoinsEarned,
      totalExperience: totalExperience,
      claimedRewardIds: claimedIds,
      pendingRewards: pending,
    );
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

  void _assertNotAlreadyClaimed(GameReward reward) {
    if (reward.oneTime &&
        reward.id != null &&
        _state.claimedRewardIds.contains(reward.id)) {
      throw RewardAlreadyClaimedException(reward.id!);
    }
    if (reward.type == GameRewardType.bundle) {
      for (final child in reward.rewards) {
        _assertNotAlreadyClaimed(child);
      }
    }
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
        'Cannot use RewardManager after it has been disposed.',
      );
    }
  }
}
