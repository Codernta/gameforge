import 'package:meta/meta.dart';

import '../core/game_exception.dart';

/// Configuration options for [HealthManager].
@immutable
class HealthConfig {
  /// Creates a [HealthConfig].
  const HealthConfig({
    this.maxHealth = 100.0,
    this.initialHealth,
    this.initialLives = 3,
    this.maxLives,
    this.supportsLives = true,
    this.autoRespawnOnDeath = true,
    this.respawnHealth,
    this.invincibilityDuration,
    this.invincibilityOnDamage = false,
    this.invincibilityOnRespawn = true,
  });

  /// Maximum health capacity (`> 0`).
  final double maxHealth;

  /// Starting health value; defaults to [maxHealth].
  final double? initialHealth;

  /// Starting life count when [supportsLives] is `true`.
  final int initialLives;

  /// Optional maximum life cap.
  final int? maxLives;

  /// Whether player deaths consume lives rather than ending immediately.
  final bool supportsLives;

  /// Whether losing health to zero automatically consumes a life and restores
  /// health to [effectiveRespawnHealth] when lives remain.
  final bool autoRespawnOnDeath;

  /// Health restored upon respawn; defaults to [maxHealth].
  final double? respawnHealth;

  /// Optional invincibility duration triggered on damage and/or respawn.
  final Duration? invincibilityDuration;

  /// Whether taking non-lethal damage activates [invincibilityDuration].
  final bool invincibilityOnDamage;

  /// Whether respawning after losing a life activates [invincibilityDuration].
  final bool invincibilityOnRespawn;

  /// Resolved initial health value.
  double get effectiveInitialHealth => initialHealth ?? maxHealth;

  /// Resolved respawn health value.
  double get effectiveRespawnHealth => respawnHealth ?? maxHealth;

  /// Validates this configuration, throwing [GameConfigurationException] if
  /// any limit is inconsistent.
  void validate() {
    if (!maxHealth.isFinite || maxHealth <= 0) {
      throw GameConfigurationException(
        'HealthConfig maxHealth ($maxHealth) must be finite and > 0.',
      );
    }
    final start = effectiveInitialHealth;
    if (!start.isFinite || start < 0 || start > maxHealth) {
      throw GameConfigurationException(
        'HealthConfig initialHealth ($start) must be within [0, $maxHealth].',
      );
    }
    final respawn = effectiveRespawnHealth;
    if (!respawn.isFinite || respawn <= 0 || respawn > maxHealth) {
      throw GameConfigurationException(
        'HealthConfig respawnHealth ($respawn) must be within (0, $maxHealth].',
      );
    }
    if (initialLives < 0) {
      throw GameConfigurationException(
        'HealthConfig initialLives ($initialLives) must be >= 0.',
      );
    }
    if (maxLives != null) {
      if (maxLives! < 0) {
        throw GameConfigurationException(
          'HealthConfig maxLives ($maxLives) must be >= 0.',
        );
      }
      if (initialLives > maxLives!) {
        throw GameConfigurationException(
          'HealthConfig initialLives ($initialLives) cannot exceed maxLives '
          '($maxLives).',
        );
      }
    }
    if (invincibilityDuration != null &&
        invincibilityDuration! < Duration.zero) {
      throw const GameConfigurationException(
        'HealthConfig invincibilityDuration cannot be negative.',
      );
    }
  }

  /// Creates a copy of this configuration with the provided overrides.
  HealthConfig copyWith({
    double? maxHealth,
    double? initialHealth,
    int? initialLives,
    int? maxLives,
    bool? supportsLives,
    bool? autoRespawnOnDeath,
    double? respawnHealth,
    Duration? invincibilityDuration,
    bool? invincibilityOnDamage,
    bool? invincibilityOnRespawn,
  }) {
    return HealthConfig(
      maxHealth: maxHealth ?? this.maxHealth,
      initialHealth: initialHealth ?? this.initialHealth,
      initialLives: initialLives ?? this.initialLives,
      maxLives: maxLives ?? this.maxLives,
      supportsLives: supportsLives ?? this.supportsLives,
      autoRespawnOnDeath: autoRespawnOnDeath ?? this.autoRespawnOnDeath,
      respawnHealth: respawnHealth ?? this.respawnHealth,
      invincibilityDuration:
          invincibilityDuration ?? this.invincibilityDuration,
      invincibilityOnDamage:
          invincibilityOnDamage ?? this.invincibilityOnDamage,
      invincibilityOnRespawn:
          invincibilityOnRespawn ?? this.invincibilityOnRespawn,
    );
  }
}

/// Immutable snapshot of player health, lives, and invincibility status.
@immutable
class HealthState {
  /// Creates a [HealthState].
  const HealthState({
    required this.currentHealth,
    required this.maxHealth,
    required this.lives,
    this.maxLives,
    this.supportsLives = true,
    this.invincibleUntil,
    this.isInvincible = false,
  });

  /// Current health value (`0.0 <= currentHealth <= maxHealth`).
  final double currentHealth;

  /// Maximum health capacity.
  final double maxHealth;

  /// Remaining player lives.
  final int lives;

  /// Optional maximum life cap.
  final int? maxLives;

  /// Whether lives are tracked by this health model.
  final bool supportsLives;

  /// Timestamp until which invincibility remains active, if any.
  final DateTime? invincibleUntil;

  /// Whether invincibility was active when this snapshot was produced.
  final bool isInvincible;

  /// Normalized health ratio in `[0.0, 1.0]`.
  double get healthPercentage =>
      maxHealth <= 0 ? 0.0 : (currentHealth / maxHealth).clamp(0.0, 1.0);

  /// Whether the player is permanently dead (no health and no remaining lives).
  bool get isDead => supportsLives ? lives <= 0 : currentHealth <= 0;

  /// Whether the player is still alive.
  bool get isAlive => !isDead;

  /// Returns a modified copy of this state.
  HealthState copyWith({
    double? currentHealth,
    double? maxHealth,
    int? lives,
    int? maxLives,
    bool? supportsLives,
    DateTime? invincibleUntil,
    bool clearInvincibleUntil = false,
    bool? isInvincible,
  }) {
    return HealthState(
      currentHealth: currentHealth ?? this.currentHealth,
      maxHealth: maxHealth ?? this.maxHealth,
      lives: lives ?? this.lives,
      maxLives: maxLives ?? this.maxLives,
      supportsLives: supportsLives ?? this.supportsLives,
      invincibleUntil: clearInvincibleUntil
          ? null
          : (invincibleUntil ?? this.invincibleUntil),
      isInvincible: isInvincible ?? this.isInvincible,
    );
  }

  /// Serializes this state into a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'currentHealth': currentHealth,
    'maxHealth': maxHealth,
    'lives': lives,
    'maxLives': maxLives,
    'supportsLives': supportsLives,
    'invincibleUntil': invincibleUntil?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HealthState &&
        other.currentHealth == currentHealth &&
        other.maxHealth == maxHealth &&
        other.lives == lives &&
        other.maxLives == maxLives &&
        other.supportsLives == supportsLives &&
        other.invincibleUntil == invincibleUntil &&
        other.isInvincible == isInvincible;
  }

  @override
  int get hashCode => Object.hash(
    currentHealth,
    maxHealth,
    lives,
    maxLives,
    supportsLives,
    invincibleUntil,
    isInvincible,
  );

  @override
  String toString() =>
      'HealthState(health: $currentHealth/$maxHealth, lives: $lives, '
      'isInvincible: $isInvincible)';
}
