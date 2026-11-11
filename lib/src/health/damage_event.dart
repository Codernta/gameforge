import '../core/game_event.dart';

/// Emitted when damage is applied (or blocked by invincibility).
final class DamageTakenEvent extends GameEvent {
  /// Creates a [DamageTakenEvent].
  DamageTakenEvent({
    required this.requestedAmount,
    required this.appliedAmount,
    required this.previousHealth,
    required this.newHealth,
    this.source,
    this.wasBlockedByInvincibility = false,
    super.timestamp,
  });

  /// Requested damage amount.
  final double requestedAmount;

  /// Actual health deducted after clamping or invincibility checks.
  final double appliedAmount;

  /// Health prior to damage.
  final double previousHealth;

  /// Health after damage.
  final double newHealth;

  /// Optional damage source identifier (e.g., `'spike'`, `'enemy'`).
  final String? source;

  /// Whether invincibility prevented the damage.
  final bool wasBlockedByInvincibility;
}

/// Emitted when health is restored via [HealthManager.heal].
final class HealedEvent extends GameEvent {
  /// Creates a [HealedEvent].
  HealedEvent({
    required this.requestedAmount,
    required this.appliedAmount,
    required this.previousHealth,
    required this.newHealth,
    super.timestamp,
  });

  /// Requested heal amount.
  final double requestedAmount;

  /// Actual health restored after clamping at max health.
  final double appliedAmount;

  /// Health prior to healing.
  final double previousHealth;

  /// Health after healing.
  final double newHealth;
}

/// Emitted when a player loses a life.
final class LifeLostEvent extends GameEvent {
  /// Creates a [LifeLostEvent].
  LifeLostEvent({
    required this.previousLives,
    required this.remainingLives,
    super.timestamp,
  });

  /// Life count prior to the loss.
  final int previousLives;

  /// Remaining life count after the loss.
  final int remainingLives;
}

/// Emitted when one or more lives are gained.
final class LifeAddedEvent extends GameEvent {
  /// Creates a [LifeAddedEvent].
  LifeAddedEvent({
    required this.previousLives,
    required this.newLives,
    super.timestamp,
  });

  /// Life count prior to addition.
  final int previousLives;

  /// Life count after addition.
  final int newLives;
}

/// Emitted when all health and remaining lives are exhausted.
final class PlayerDiedEvent extends GameEvent {
  /// Creates a [PlayerDiedEvent].
  PlayerDiedEvent({required this.remainingLives, super.timestamp});

  /// Remaining life count at death (`0` for life-based configurations).
  final int remainingLives;
}

/// Emitted when the player respawns after losing a life.
final class PlayerRespawnedEvent extends GameEvent {
  /// Creates a [PlayerRespawnedEvent].
  PlayerRespawnedEvent({
    required this.restoredHealth,
    required this.remainingLives,
    super.timestamp,
  });

  /// Health value restored on respawn.
  final double restoredHealth;

  /// Remaining lives after respawn.
  final int remainingLives;
}

/// Emitted when a temporary invincibility window starts.
final class InvincibilityStartedEvent extends GameEvent {
  /// Creates an [InvincibilityStartedEvent].
  InvincibilityStartedEvent({
    required this.duration,
    required this.until,
    super.timestamp,
  });

  /// Duration of the invincibility window.
  final Duration duration;

  /// Timestamp when invincibility expires.
  final DateTime until;
}

/// Emitted when an active invincibility window expires or is cleared.
final class InvincibilityEndedEvent extends GameEvent {
  /// Creates an [InvincibilityEndedEvent].
  InvincibilityEndedEvent({super.timestamp});
}
