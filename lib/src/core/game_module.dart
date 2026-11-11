import 'dart:async';

import '../utils/game_clock.dart';
import '../utils/id_generator.dart';
import 'game_event_bus.dart';
import 'game_status.dart';

/// Read-only runtime context supplied to [GameModule.onInitialize].
class GameModuleContext {
  /// Creates a [GameModuleContext].
  const GameModuleContext({
    required this.events,
    required this.clock,
    required this.idGenerator,
    required GameStatus Function() statusProvider,
    required T? Function<T extends GameModule>() moduleResolver,
  }) : _statusProvider = statusProvider,
       _moduleResolver = moduleResolver;

  /// Shared event bus for the owning [GameForge] instance.
  final GameEventBus events;

  /// Clock used for timestamps and deterministic time calculations.
  final GameClock clock;

  /// Identifier generator for the owning [GameForge] instance.
  final IdGenerator idGenerator;

  final GameStatus Function() _statusProvider;
  final T? Function<T extends GameModule>() _moduleResolver;

  /// Returns the current lifecycle status of the owning [GameForge] instance.
  GameStatus get currentStatus => _statusProvider();

  /// Resolves another registered module of type [T], if present.
  T? findModule<T extends GameModule>() => _moduleResolver<T>();
}

/// Extensible lifecycle contract for custom gameplay modules plugged into
/// [GameForge].
///
/// Subclasses can extend [GameModule] and override only the hooks they need.
abstract class GameModule {
  /// Unique module identifier used for lookups and save-data namespacing.
  String get id;

  /// Called asynchronously when [GameForge.initialize] runs.
  FutureOr<void> onInitialize(GameModuleContext context) {}

  /// Called when the game starts via [GameForge.start] or auto-start restart.
  void onStart() {}

  /// Called when the game pauses via [GameForge.pause].
  void onPause() {}

  /// Called when the game resumes via [GameForge.resume].
  void onResume() {}

  /// Called when the game completes via [GameForge.complete].
  void onComplete() {}

  /// Called when the game enters [GameStatus.gameOver].
  void onGameOver() {}

  /// Called when the game resets via [GameForge.restart].
  void onReset() {}

  /// Called during [GameForge.dispose] to release subscriptions and resources.
  FutureOr<void> onDispose() {}

  /// Serializes module state for persistence, or returns `null` if stateless.
  Map<String, Object?>? toSaveData() => null;

  /// Restores module state previously returned by [toSaveData].
  FutureOr<void> fromSaveData(Map<String, Object?> data) {}
}
