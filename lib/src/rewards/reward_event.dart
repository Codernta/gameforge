import '../core/game_event.dart';
import 'reward.dart';

/// Emitted when a claimable reward is added to the pending queue.
final class RewardOfferedEvent extends GameEvent {
  /// Creates a [RewardOfferedEvent].
  RewardOfferedEvent({required this.reward, super.timestamp});

  /// The offered reward awaiting claim.
  final GameReward reward;
}

/// Emitted when a reward is granted or claimed.
final class RewardGrantedEvent extends GameEvent {
  /// Creates a [RewardGrantedEvent].
  RewardGrantedEvent({
    required this.reward,
    required this.coinBalance,
    required this.totalExperience,
    super.timestamp,
  });

  /// The granted reward.
  final GameReward reward;

  /// Resulting coin balance after granting.
  final int coinBalance;

  /// Resulting total experience points after granting.
  final int totalExperience;
}

/// Emitted when coins are spent from [RewardManager].
final class CoinsSpentEvent extends GameEvent {
  /// Creates a [CoinsSpentEvent].
  CoinsSpentEvent({
    required this.amount,
    required this.remainingBalance,
    this.reason,
    super.timestamp,
  });

  /// Coins spent.
  final int amount;

  /// Remaining coin balance.
  final int remainingBalance;

  /// Optional reason or purchase identifier.
  final String? reason;
}
