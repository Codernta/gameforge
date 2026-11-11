import 'package:meta/meta.dart';

import '../achievements/achievement_progress.dart';
import '../health/health_state.dart';
import '../inventory/inventory_state.dart';
import '../levels/level_state.dart';
import '../rewards/reward.dart';
import '../score/score_state.dart';
import '../session/session_state.dart';
import 'game_status.dart';

/// Unified immutable snapshot of a [GameForge] instance's runtime state across
/// all built-in gameplay systems.
@immutable
class GameState {
  /// Creates a [GameState].
  const GameState({
    required this.status,
    required this.score,
    required this.health,
    required this.levels,
    required this.inventory,
    required this.rewards,
    required this.achievements,
    required this.session,
    required this.updatedAt,
  });

  /// Current game lifecycle status.
  final GameStatus status;

  /// Current score state snapshot.
  final ScoreState score;

  /// Current health and lives snapshot.
  final HealthState health;

  /// Current level progression snapshot.
  final LevelState levels;

  /// Current inventory snapshot.
  final InventoryState inventory;

  /// Current rewards and coin balance snapshot.
  final RewardState rewards;

  /// Current achievements snapshot.
  final AchievementState achievements;

  /// Current gameplay session snapshot.
  final SessionState session;

  /// Timestamp when this snapshot was captured.
  final DateTime updatedAt;
}
