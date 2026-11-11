import 'package:meta/meta.dart';

import '../core/game_exception.dart';
import '../inventory/game_item.dart';
import '../persistence/serialization.dart';

/// Categories of rewards supported by [GameReward] and [RewardManager].
enum GameRewardType {
  /// Virtual coin currency reward.
  coins,

  /// Score points reward.
  points,

  /// Inventory [GameItem] reward.
  item,

  /// Player experience points (XP) reward.
  experience,

  /// Developer-defined custom reward payload.
  custom,

  /// Composite group of multiple rewards claimed atomically together.
  bundle,
}

/// Immutable reward definition supporting coins, points, items, XP, custom
/// payloads, and grouped bundles.
@immutable
class GameReward {
  const GameReward._({
    required this.type,
    this.id,
    this.title,
    this.amount = 0,
    this.item,
    this.customType,
    this.customData = const {},
    this.rewards = const [],
    this.oneTime = false,
    this.metadata = const {},
  });

  /// Creates a coin currency reward of [amount].
  factory GameReward.coins(
    int amount, {
    String? id,
    String? title,
    bool oneTime = false,
    Map<String, Object?> metadata = const {},
  }) {
    _validateAmount(amount, 'coins');
    _validateOneTimeId(oneTime, id);
    return GameReward._(
      type: GameRewardType.coins,
      id: id,
      title: title ?? '$amount Coins',
      amount: amount,
      oneTime: oneTime,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  /// Creates a score points reward of [amount].
  factory GameReward.points(
    int amount, {
    String? id,
    String? title,
    bool oneTime = false,
    Map<String, Object?> metadata = const {},
  }) {
    _validateAmount(amount, 'points');
    _validateOneTimeId(oneTime, id);
    return GameReward._(
      type: GameRewardType.points,
      id: id,
      title: title ?? '$amount Points',
      amount: amount,
      oneTime: oneTime,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  /// Creates an inventory [GameItem] reward.
  factory GameReward.item(
    GameItem item, {
    String? id,
    String? title,
    bool oneTime = false,
    Map<String, Object?> metadata = const {},
  }) {
    item.validate();
    _validateOneTimeId(oneTime, id);
    return GameReward._(
      type: GameRewardType.item,
      id: id,
      title: title ?? '${item.quantity}x ${item.name}',
      item: item,
      oneTime: oneTime,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  /// Creates an experience points (XP) reward of [amount].
  factory GameReward.experience(
    int amount, {
    String? id,
    String? title,
    bool oneTime = false,
    Map<String, Object?> metadata = const {},
  }) {
    _validateAmount(amount, 'experience');
    _validateOneTimeId(oneTime, id);
    return GameReward._(
      type: GameRewardType.experience,
      id: id,
      title: title ?? '$amount XP',
      amount: amount,
      oneTime: oneTime,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  /// Creates a developer-defined custom reward payload.
  factory GameReward.custom({
    required String id,
    required String customType,
    Map<String, Object?> data = const {},
    String? title,
    bool oneTime = false,
    Map<String, Object?> metadata = const {},
  }) {
    if (id.trim().isEmpty) {
      throw const RewardException('Custom reward id cannot be empty.');
    }
    if (customType.trim().isEmpty) {
      throw const RewardException('Custom reward customType cannot be empty.');
    }
    return GameReward._(
      type: GameRewardType.custom,
      id: id,
      title: title ?? customType,
      customType: customType,
      customData: Map<String, Object?>.unmodifiable(data),
      oneTime: oneTime,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  /// Creates a grouped reward bundle claiming all [rewards] atomically.
  factory GameReward.bundle({
    required String id,
    required List<GameReward> rewards,
    String? title,
    bool oneTime = false,
    Map<String, Object?> metadata = const {},
  }) {
    if (id.trim().isEmpty) {
      throw const RewardException('Bundle reward id cannot be empty.');
    }
    if (rewards.isEmpty) {
      throw const RewardException(
        'Bundle reward must contain at least 1 item.',
      );
    }
    return GameReward._(
      type: GameRewardType.bundle,
      id: id,
      title: title ?? 'Reward Bundle',
      rewards: List<GameReward>.unmodifiable(rewards),
      oneTime: oneTime,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  /// Restores a [GameReward] from JSON data.
  factory GameReward.fromJson(Map<String, Object?> json) {
    final typeName = GameSerialization.readString(json, 'type');
    final type = GameRewardType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () =>
          throw CorruptSaveDataException('Unknown GameRewardType "$typeName".'),
    );
    final id = GameSerialization.readOptionalString(json, 'id');
    final title = GameSerialization.readOptionalString(json, 'title');
    final oneTime = GameSerialization.readBool(
      json,
      'oneTime',
      defaultValue: false,
    );
    final metadata = GameSerialization.readMap(
      json,
      'metadata',
      defaultValue: const {},
    );

    switch (type) {
      case GameRewardType.coins:
        return GameReward.coins(
          GameSerialization.readInt(json, 'amount'),
          id: id,
          title: title,
          oneTime: oneTime,
          metadata: metadata,
        );
      case GameRewardType.points:
        return GameReward.points(
          GameSerialization.readInt(json, 'amount'),
          id: id,
          title: title,
          oneTime: oneTime,
          metadata: metadata,
        );
      case GameRewardType.experience:
        return GameReward.experience(
          GameSerialization.readInt(json, 'amount'),
          id: id,
          title: title,
          oneTime: oneTime,
          metadata: metadata,
        );
      case GameRewardType.item:
        final itemMap = GameSerialization.readMap(json, 'item');
        return GameReward.item(
          GameItem.fromJson(itemMap),
          id: id,
          title: title,
          oneTime: oneTime,
          metadata: metadata,
        );
      case GameRewardType.custom:
        return GameReward.custom(
          id: GameSerialization.readString(json, 'id'),
          customType: GameSerialization.readString(json, 'customType'),
          data: GameSerialization.readMap(
            json,
            'customData',
            defaultValue: const {},
          ),
          title: title,
          oneTime: oneTime,
          metadata: metadata,
        );
      case GameRewardType.bundle:
        final rawList = GameSerialization.readList(json, 'rewards');
        final nested = <GameReward>[];
        for (final entry in rawList) {
          if (entry is! Map<Object?, Object?>) {
            throw const CorruptSaveDataException(
              'Expected map inside reward bundle list.',
            );
          }
          nested.add(
            GameReward.fromJson(GameSerialization.normalizeMap(entry)),
          );
        }
        return GameReward.bundle(
          id: GameSerialization.readString(json, 'id'),
          rewards: nested,
          title: title,
          oneTime: oneTime,
          metadata: metadata,
        );
    }
  }

  /// Kind of reward.
  final GameRewardType type;

  /// Optional unique reward identifier (required when [oneTime] is `true`).
  final String? id;

  /// Human-readable reward title.
  final String? title;

  /// Numeric amount for coins, points, or experience rewards.
  final int amount;

  /// Item granted when [type] is [GameRewardType.item].
  final GameItem? item;

  /// Custom reward discriminator when [type] is [GameRewardType.custom].
  final String? customType;

  /// Arbitrary payload for [GameRewardType.custom].
  final Map<String, Object?> customData;

  /// Child rewards when [type] is [GameRewardType.bundle].
  final List<GameReward> rewards;

  /// Whether this reward may only be claimed once per game profile.
  final bool oneTime;

  /// Additional metadata associated with this reward.
  final Map<String, Object?> metadata;

  /// Returns a copy with an explicit [id].
  GameReward withId(String id) {
    return GameReward._(
      type: type,
      id: id,
      title: title,
      amount: amount,
      item: item,
      customType: customType,
      customData: customData,
      rewards: rewards,
      oneTime: oneTime,
      metadata: metadata,
    );
  }

  /// Serializes this reward into a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'type': type.name,
    'id': id,
    'title': title,
    'amount': amount,
    'item': item?.toJson(),
    'customType': customType,
    'customData': GameSerialization.normalizeMap(customData),
    'rewards': rewards.map((r) => r.toJson()).toList(growable: false),
    'oneTime': oneTime,
    'metadata': GameSerialization.normalizeMap(metadata),
  };

  static void _validateAmount(int amount, String kind) {
    if (amount <= 0) {
      throw RewardException(
        'Reward amount for $kind must be greater than zero (got $amount).',
      );
    }
  }

  static void _validateOneTimeId(bool oneTime, String? id) {
    if (oneTime && (id == null || id.trim().isEmpty)) {
      throw const RewardException(
        'A non-empty id is required when creating a one-time reward.',
      );
    }
  }
}

/// Immutable snapshot of [RewardManager] balances and claim state.
@immutable
class RewardState {
  /// Creates a [RewardState].
  RewardState({
    required this.coinBalance,
    required this.totalCoinsEarned,
    required this.totalExperience,
    required Set<String> claimedRewardIds,
    required List<GameReward> pendingRewards,
  }) : claimedRewardIds = Set<String>.unmodifiable(claimedRewardIds),
       pendingRewards = List<GameReward>.unmodifiable(pendingRewards);

  /// Current spendable coin balance.
  final int coinBalance;

  /// Cumulative coins earned across grants.
  final int totalCoinsEarned;

  /// Cumulative experience points earned.
  final int totalExperience;

  /// Identifiers of claimed rewards (including one-time rewards).
  final Set<String> claimedRewardIds;

  /// Rewards offered and awaiting explicit claim via [RewardManager.claim].
  final List<GameReward> pendingRewards;

  /// Serializes this state into a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'coinBalance': coinBalance,
    'totalCoinsEarned': totalCoinsEarned,
    'totalExperience': totalExperience,
    'claimedRewardIds': claimedRewardIds.toList(growable: false),
    'pendingRewards': pendingRewards
        .map((r) => r.toJson())
        .toList(growable: false),
  };
}
