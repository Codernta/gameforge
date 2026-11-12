/// Base exception type for all errors thrown by GameForge.
class GameException implements Exception {
  /// Creates a [GameException] with a descriptive [message] and optional [code].
  const GameException(
    this.message, {
    this.code = 'game_error',
    this.cause,
    this.stackTrace,
  });

  /// Human-readable description of the failure.
  final String message;

  /// Machine-readable error code identifying the failure category.
  final String code;

  /// Optional underlying error that caused this exception.
  final Object? cause;

  /// Optional stack trace associated with [cause].
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType($code): $message');
    if (cause != null) {
      buffer.write(' [cause: $cause]');
    }
    return buffer.toString();
  }
}

/// Thrown when an invalid game lifecycle transition is attempted.
class InvalidLifecycleTransitionException extends GameException {
  /// Creates an [InvalidLifecycleTransitionException].
  const InvalidLifecycleTransitionException({
    required this.from,
    required this.to,
    required this.operation,
    String? message,
  }) : super(
         message ??
             'Cannot execute "$operation" when game status is "$from"'
                 '${to != null ? ' (target: "$to")' : ''}.',
         code: 'invalid_lifecycle_transition',
       );

  /// The current lifecycle status name when the operation was attempted.
  final String from;

  /// The attempted target lifecycle status name, if applicable.
  final String? to;

  /// The lifecycle method or operation that failed.
  final String operation;
}

/// Thrown when a [GameConfig] or module configuration is invalid.
class GameConfigurationException extends GameException {
  /// Creates a [GameConfigurationException].
  const GameConfigurationException(
    super.message, {
    super.code = 'invalid_configuration',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when an operation is invalid for the current state.
class GameStateException extends GameException {
  /// Creates a [GameStateException].
  const GameStateException(
    super.message, {
    super.code = 'invalid_state',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when registering, initializing, or resolving a custom module fails.
class GameModuleException extends GameException {
  /// Creates a [GameModuleException].
  const GameModuleException(
    super.message, {
    super.code = 'module_error',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when the event bus detects an uncontrolled recursive event loop.
class GameEventLoopException extends GameException {
  /// Creates a [GameEventLoopException].
  const GameEventLoopException(
    super.message, {
    super.code = 'event_loop_detected',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a score operation violates validation or boundary rules.
class ScoreValidationException extends GameException {
  /// Creates a [ScoreValidationException].
  const ScoreValidationException(
    super.message, {
    super.code = 'score_validation_error',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a health or lives operation violates validation rules.
class HealthValidationException extends GameException {
  /// Creates a [HealthValidationException].
  const HealthValidationException(
    super.message, {
    super.code = 'health_validation_error',
    super.cause,
    super.stackTrace,
  });
}

/// Base exception for level management errors.
class LevelException extends GameException {
  /// Creates a [LevelException].
  const LevelException(
    super.message, {
    super.code = 'level_error',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when referencing a level that does not exist.
class LevelNotFoundException extends LevelException {
  /// Creates a [LevelNotFoundException].
  const LevelNotFoundException(this.levelReference)
    : super(
        'Level "$levelReference" could not be found.',
        code: 'level_not_found',
      );

  /// The identifier or number of the missing level.
  final Object levelReference;
}

/// Thrown when attempting to select or complete a locked level.
class LevelLockedException extends LevelException {
  /// Creates a [LevelLockedException].
  const LevelLockedException(this.levelId)
    : super('Level "$levelId" is currently locked.', code: 'level_locked');

  /// The identifier of the locked level.
  final String levelId;
}

/// Base exception for inventory operations.
class InventoryException extends GameException {
  /// Creates an [InventoryException].
  const InventoryException(
    super.message, {
    super.code = 'inventory_error',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when an inventory item does not exist.
class ItemNotFoundException extends InventoryException {
  /// Creates an [ItemNotFoundException].
  const ItemNotFoundException(this.itemId)
    : super(
        'Item "$itemId" was not found in the inventory.',
        code: 'item_not_found',
      );

  /// The identifier of the missing item.
  final String itemId;
}

/// Thrown when removing or consuming more items than currently available.
class InsufficientItemException extends InventoryException {
  /// Creates an [InsufficientItemException].
  const InsufficientItemException({
    required this.itemId,
    required this.requested,
    required this.available,
  }) : super(
         'Insufficient quantity for item "$itemId": requested $requested, '
         'available $available.',
         code: 'insufficient_item_quantity',
       );

  /// The identifier of the item.
  final String itemId;

  /// Requested quantity.
  final int requested;

  /// Available quantity.
  final int available;
}

/// Thrown when inventory slot capacity or stack limits would be exceeded.
class InventoryFullException extends InventoryException {
  /// Creates an [InventoryFullException].
  const InventoryFullException(super.message, {super.code = 'inventory_full'});
}

/// Thrown when adding a duplicate non-stackable or conflicting item.
class DuplicateItemException extends InventoryException {
  /// Creates a [DuplicateItemException].
  const DuplicateItemException(this.itemId, [String? details])
    : super(
        details ?? 'Item "$itemId" already exists in the inventory.',
        code: 'duplicate_item',
      );

  /// The identifier of the duplicate item.
  final String itemId;
}

/// Thrown when an item has invalid properties or quantities.
class InvalidItemException extends InventoryException {
  /// Creates an [InvalidItemException].
  const InvalidItemException(super.message) : super(code: 'invalid_item');
}

/// Base exception for reward system errors.
class RewardException extends GameException {
  /// Creates a [RewardException].
  const RewardException(
    super.message, {
    super.code = 'reward_error',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when attempting to claim a one-time reward more than once.
class RewardAlreadyClaimedException extends RewardException {
  /// Creates a [RewardAlreadyClaimedException].
  const RewardAlreadyClaimedException(this.rewardId)
    : super(
        'One-time reward "$rewardId" has already been claimed.',
        code: 'reward_already_claimed',
      );

  /// The identifier of the already claimed reward.
  final String rewardId;
}

/// Thrown when attempting to claim a pending reward that does not exist.
class RewardNotFoundException extends RewardException {
  /// Creates a [RewardNotFoundException].
  const RewardNotFoundException(this.rewardId)
    : super(
        'Pending reward "$rewardId" was not found.',
        code: 'reward_not_found',
      );

  /// The identifier of the missing reward.
  final String rewardId;
}

/// Base exception for achievement system errors.
class AchievementException extends GameException {
  /// Creates an [AchievementException].
  const AchievementException(
    super.message, {
    super.code = 'achievement_error',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when referencing an unregistered achievement.
class AchievementNotFoundException extends AchievementException {
  /// Creates an [AchievementNotFoundException].
  const AchievementNotFoundException(this.achievementId)
    : super(
        'Achievement "$achievementId" is not registered.',
        code: 'achievement_not_found',
      );

  /// The identifier of the missing achievement.
  final String achievementId;
}

/// Thrown when registering an achievement with an already registered ID.
class DuplicateAchievementException extends AchievementException {
  /// Creates a [DuplicateAchievementException].
  const DuplicateAchievementException(this.achievementId)
    : super(
        'Achievement "$achievementId" is already registered.',
        code: 'duplicate_achievement',
      );

  /// The duplicate achievement identifier.
  final String achievementId;
}

/// Thrown for timer configuration or lifecycle errors.
class TimerException extends GameException {
  /// Creates a [TimerException].
  const TimerException(
    super.message, {
    super.code = 'timer_error',
    super.cause,
    super.stackTrace,
  });
}

/// Base exception for save/load persistence errors.
class PersistenceException extends GameException {
  /// Creates a [PersistenceException].
  const PersistenceException(
    super.message, {
    super.code = 'persistence_error',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when stored save data cannot be parsed or fails integrity checks.
class CorruptSaveDataException extends PersistenceException {
  /// Creates a [CorruptSaveDataException].
  const CorruptSaveDataException(
    super.message, {
    super.code = 'corrupt_save_data',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when save payload integrity or HMAC authentication fails.
class SaveIntegrityException extends CorruptSaveDataException {
  /// Creates a [SaveIntegrityException].
  const SaveIntegrityException(super.message, {super.cause, super.stackTrace})
    : super(code: 'save_integrity_error');
}

/// Thrown when migrating save data across versions fails.
class SaveMigrationException extends PersistenceException {
  /// Creates a [SaveMigrationException].
  const SaveMigrationException(super.message, {super.cause, super.stackTrace})
    : super(code: 'save_migration_error');
}

/// Thrown when restored save data fails semantic validation rules.
class SaveValidationException extends PersistenceException {
  /// Creates a [SaveValidationException].
  const SaveValidationException(super.message, {super.cause, super.stackTrace})
    : super(code: 'save_validation_error');
}

/// Thrown for invalid game session lifecycle operations.
class SessionException extends GameException {
  /// Creates a [SessionException].
  const SessionException(
    super.message, {
    super.code = 'session_error',
    super.cause,
    super.stackTrace,
  });
}
