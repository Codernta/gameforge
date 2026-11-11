import 'package:flutter/widgets.dart';

import '../../core/game_controller.dart';
import '../../core/game_state.dart';
import '../../core/game_status.dart';

/// Provides a [GameForge] controller instance down the widget tree without
/// relying on global singletons.
class GameForgeScope extends InheritedWidget {
  /// Creates a [GameForgeScope] providing [game] to [child].
  const GameForgeScope({required this.game, required super.child, super.key});

  /// The [GameForge] instance exposed to descendants.
  final GameForge game;

  /// Returns the nearest ancestor [GameForge] instance, or `null` if none is
  /// found.
  static GameForge? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GameForgeScope>()?.game;
  }

  /// Returns the nearest ancestor [GameForge] instance, throwing a
  /// [FlutterError] if no [GameForgeScope] wraps [context].
  static GameForge of(BuildContext context) {
    final game = maybeOf(context);
    if (game == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No GameForgeScope found in widget tree.'),
        ErrorDescription(
          'GameForgeScope.of(context) requires a GameForgeScope ancestor '
          'above the calling widget.',
        ),
      ]);
    }
    return game;
  }

  @override
  bool updateShouldNotify(GameForgeScope oldWidget) =>
      !identical(oldWidget.game, game);
}

/// Rebuilds whenever [game]'s unified [GameState] emits an update.
class GameForgeBuilder extends StatelessWidget {
  /// Creates a [GameForgeBuilder].
  const GameForgeBuilder({
    required this.builder,
    this.game,
    this.child,
    super.key,
  });

  /// Optional explicit controller; falls back to [GameForgeScope.of].
  final GameForge? game;

  /// Builder invoked with the latest [GameState].
  final Widget Function(BuildContext context, GameState state, Widget? child)
  builder;

  /// Optional static child widget preserved across rebuilds.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final target = game ?? GameForgeScope.of(context);
    return StreamBuilder<GameState>(
      initialData: target.state,
      stream: target.stateStream,
      builder: (context, snapshot) {
        return builder(context, snapshot.data ?? target.state, child);
      },
    );
  }
}

/// Rebuilds whenever [game]'s [GameStatus] changes.
class GameForgeStatusBuilder extends StatelessWidget {
  /// Creates a [GameForgeStatusBuilder].
  const GameForgeStatusBuilder({
    required this.builder,
    this.game,
    this.child,
    super.key,
  });

  /// Optional explicit controller; falls back to [GameForgeScope.of].
  final GameForge? game;

  /// Builder invoked with the current [GameStatus].
  final Widget Function(BuildContext context, GameStatus status, Widget? child)
  builder;

  /// Optional static child widget preserved across rebuilds.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final target = game ?? GameForgeScope.of(context);
    return StreamBuilder<GameStatus>(
      initialData: target.status,
      stream: target.statusStream,
      builder: (context, snapshot) {
        return builder(context, snapshot.data ?? target.status, child);
      },
    );
  }
}
