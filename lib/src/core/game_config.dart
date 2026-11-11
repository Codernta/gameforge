import 'package:meta/meta.dart';

import '../health/health_state.dart';
import '../levels/level_config.dart';
import '../score/score_state.dart';
import 'game_exception.dart';

/// Immutable configuration object for creating a [GameForge] controller.
@immutable
class GameConfig {
  /// Creates a [GameConfig].
  const GameConfig({
    this.initialScore = 0,
    this.maxScore,
    this.allowNegativeScore = false,
    this.initialHealth,
    this.maxHealth = 100.0,
    this.initialLives = 3,
    this.maxLives,
    this.supportsLives = true,
    this.invincibilityDuration,
    this.maxLevels = 10,
    this.levelConfigs,
    this.inventoryCapacity,
    this.autoStartSession = true,
    this.pauseTimersOnGamePause = true,
    this.pauseAudioOnGamePause = true,
    this.autoGameOverOnZeroLives = true,
    this.saveKey = 'gameforge_save',
    this.saveVersion = 1,
    this.custom = const {},
  });

  /// Starting score value.
  final int initialScore;

  /// Optional maximum score cap.
  final int? maxScore;

  /// Whether scores may drop below zero.
  final bool allowNegativeScore;

  /// Starting health value; defaults to [maxHealth].
  final double? initialHealth;

  /// Maximum player health (`> 0`).
  final double maxHealth;

  /// Starting number of player lives.
  final int initialLives;

  /// Optional maximum life cap.
  final int? maxLives;

  /// Whether death consumes lives rather than triggering immediate death.
  final bool supportsLives;

  /// Optional temporary invincibility duration applied after damage/respawn.
  final Duration? invincibilityDuration;

  /// Number of sequential levels generated when [levelConfigs] is omitted.
  final int maxLevels;

  /// Optional explicit level definitions overriding [maxLevels].
  final List<LevelConfig>? levelConfigs;

  /// Optional inventory slot capacity (`null` means unlimited).
  final int? inventoryCapacity;

  /// Whether [GameForge.start] automatically starts a [GameSessionManager]
  /// session.
  final bool autoStartSession;

  /// Whether [GameForge.pause] / [GameForge.resume] automatically pauses and
  /// resumes timers managed by [GameTimerManager].
  final bool pauseTimersOnGamePause;

  /// Whether [GameForge.pause] / [GameForge.resume] pauses and resumes
  /// background music on [GameAudioService].
  final bool pauseAudioOnGamePause;

  /// Whether exhausting all lives/health while running automatically triggers
  /// [GameStatus.gameOver].
  final bool autoGameOverOnZeroLives;

  /// Default storage key used by [GameForge.save] and [GameForge.load].
  final String saveKey;

  /// Current schema version written into [GameSaveData].
  final int saveVersion;

  /// Arbitrary developer-defined custom configuration values.
  final Map<String, Object?> custom;

  /// Builds default [ScoreRules] derived from this config.
  ScoreRules toScoreRules() => ScoreRules(
    initialScore: initialScore,
    maxScore: maxScore,
    allowNegativeScore: allowNegativeScore,
  );

  /// Builds default [HealthConfig] derived from this config.
  HealthConfig toHealthConfig() => HealthConfig(
    maxHealth: maxHealth,
    initialHealth: initialHealth,
    initialLives: initialLives,
    maxLives: maxLives,
    supportsLives: supportsLives,
    invincibilityDuration: invincibilityDuration,
  );

  /// Validates all configuration parameters, throwing
  /// [GameConfigurationException] on invalid values.
  void validate() {
    toScoreRules().validate();
    toHealthConfig().validate();
    if (levelConfigs != null) {
      if (levelConfigs!.isEmpty) {
        throw const GameConfigurationException(
          'GameConfig.levelConfigs cannot be empty when provided.',
        );
      }
      for (final level in levelConfigs!) {
        level.validate();
      }
    } else if (maxLevels < 1) {
      throw GameConfigurationException(
        'GameConfig.maxLevels must be >= 1 (got $maxLevels).',
      );
    }
    if (inventoryCapacity != null && inventoryCapacity! < 0) {
      throw GameConfigurationException(
        'GameConfig.inventoryCapacity cannot be negative '
        '(got $inventoryCapacity).',
      );
    }
    if (saveKey.trim().isEmpty) {
      throw const GameConfigurationException(
        'GameConfig.saveKey cannot be empty.',
      );
    }
    if (saveVersion < 1) {
      throw GameConfigurationException(
        'GameConfig.saveVersion must be >= 1 (got $saveVersion).',
      );
    }
  }

  /// Creates a copy of this config with the specified overrides.
  GameConfig copyWith({
    int? initialScore,
    int? maxScore,
    bool? allowNegativeScore,
    double? initialHealth,
    double? maxHealth,
    int? initialLives,
    int? maxLives,
    bool? supportsLives,
    Duration? invincibilityDuration,
    int? maxLevels,
    List<LevelConfig>? levelConfigs,
    int? inventoryCapacity,
    bool? autoStartSession,
    bool? pauseTimersOnGamePause,
    bool? pauseAudioOnGamePause,
    bool? autoGameOverOnZeroLives,
    String? saveKey,
    int? saveVersion,
    Map<String, Object?>? custom,
  }) {
    return GameConfig(
      initialScore: initialScore ?? this.initialScore,
      maxScore: maxScore ?? this.maxScore,
      allowNegativeScore: allowNegativeScore ?? this.allowNegativeScore,
      initialHealth: initialHealth ?? this.initialHealth,
      maxHealth: maxHealth ?? this.maxHealth,
      initialLives: initialLives ?? this.initialLives,
      maxLives: maxLives ?? this.maxLives,
      supportsLives: supportsLives ?? this.supportsLives,
      invincibilityDuration:
          invincibilityDuration ?? this.invincibilityDuration,
      maxLevels: maxLevels ?? this.maxLevels,
      levelConfigs: levelConfigs ?? this.levelConfigs,
      inventoryCapacity: inventoryCapacity ?? this.inventoryCapacity,
      autoStartSession: autoStartSession ?? this.autoStartSession,
      pauseTimersOnGamePause:
          pauseTimersOnGamePause ?? this.pauseTimersOnGamePause,
      pauseAudioOnGamePause:
          pauseAudioOnGamePause ?? this.pauseAudioOnGamePause,
      autoGameOverOnZeroLives:
          autoGameOverOnZeroLives ?? this.autoGameOverOnZeroLives,
      saveKey: saveKey ?? this.saveKey,
      saveVersion: saveVersion ?? this.saveVersion,
      custom: custom ?? this.custom,
    );
  }
}
