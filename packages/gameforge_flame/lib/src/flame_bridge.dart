import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:gameforge/gameforge.dart';

/// Flame [Component] bridging a [FlameGame] with a [GameForge] controller
/// using composition.
///
/// Handles initialization, start, pause/resume synchronization, and safe
/// subscription cleanup when removed from the component tree.
class GameForgeFlameBridge extends Component with HasGameReference<FlameGame> {
  /// Creates a [GameForgeFlameBridge] wrapping [gameForge].
  GameForgeFlameBridge({
    required this.gameForge,
    this.autoInitialize = true,
    this.autoStart = true,
    this.pauseEngineOnGamePause = true,
    this.pauseEngineOnEnd = false,
    this.disposeControllerOnRemove = false,
  });

  /// Target [GameForge] gameplay controller.
  final GameForge gameForge;

  /// Whether [onLoad] calls `gameForge.initialize()` if uninitialized.
  final bool autoInitialize;

  /// Whether [onMount] calls `gameForge.start()` if status is `ready`.
  final bool autoStart;

  /// Whether `GameStatus.paused` / `running` automatically drives Flame's
  /// `pauseEngine()` / `resumeEngine()`.
  final bool pauseEngineOnGamePause;

  /// Whether reaching `completed` or `gameOver` pauses the Flame engine.
  final bool pauseEngineOnEnd;

  /// Whether [onRemove] disposes [gameForge].
  final bool disposeControllerOnRemove;

  StreamSubscription<GameStatus>? _statusSub;
  bool _syncing = false;

  /// Runs bidirectional-safe pause synchronization when Flame pauses externally.
  void notifyFlamePaused() {
    if (_syncing) return;
    if (gameForge.status == GameStatus.running) {
      _syncing = true;
      try {
        gameForge.pause();
      } finally {
        _syncing = false;
      }
    }
  }

  /// Runs bidirectional-safe resume synchronization when Flame resumes
  /// externally.
  void notifyFlameResumed() {
    if (_syncing) return;
    if (gameForge.status == GameStatus.paused) {
      _syncing = true;
      try {
        gameForge.resume();
      } finally {
        _syncing = false;
      }
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (autoInitialize && gameForge.status == GameStatus.uninitialized) {
      await gameForge.initialize();
    }
  }

  @override
  void onMount() {
    super.onMount();
    _statusSub = gameForge.statusStream.listen(_handleStatusChanged);
    if (autoStart && gameForge.status == GameStatus.ready) {
      gameForge.start();
    } else {
      _handleStatusChanged(gameForge.status);
    }
  }

  void _handleStatusChanged(GameStatus status) {
    if (_syncing || !isMounted) return;
    _syncing = true;
    try {
      switch (status) {
        case GameStatus.paused:
          if (pauseEngineOnGamePause && !game.paused) {
            game.pauseEngine();
          }
        case GameStatus.running:
          if (pauseEngineOnGamePause && game.paused) {
            game.resumeEngine();
          }
        case GameStatus.completed:
        case GameStatus.gameOver:
          if (pauseEngineOnEnd && !game.paused) {
            game.pauseEngine();
          }
        case GameStatus.uninitialized:
        case GameStatus.initializing:
        case GameStatus.ready:
        case GameStatus.disposed:
          break;
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  void onRemove() {
    unawaited(_statusSub?.cancel());
    _statusSub = null;
    if (disposeControllerOnRemove && gameForge.status != GameStatus.disposed) {
      unawaited(gameForge.dispose());
    }
    super.onRemove();
  }
}

/// Optional mixin on [FlameGame] providing full bidirectional lifecycle,
/// pause/resume, and disposal synchronization with a [GameForge] controller.
mixin GameForgeFlameMixin on FlameGame {
  GameForgeFlameBridge? _bridge;

  /// The [GameForge] controller bound to this Flame game.
  GameForge get gameForge;

  /// Whether [onLoad] automatically attaches and initializes [gameForge].
  bool get autoAttachGameForge => true;

  /// Whether Flame's `dispose()` also disposes [gameForge].
  bool get disposeGameForgeOnDispose => true;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (autoAttachGameForge && _bridge == null) {
      final bridge = GameForgeFlameBridge(
        gameForge: gameForge,
        disposeControllerOnRemove: false,
      );
      _bridge = bridge;
      await add(bridge);
    }
  }

  @override
  void pauseEngine() {
    super.pauseEngine();
    _bridge?.notifyFlamePaused();
  }

  @override
  void resumeEngine() {
    super.resumeEngine();
    _bridge?.notifyFlameResumed();
  }

  @override
  void dispose() {
    super.dispose();
    if (disposeGameForgeOnDispose && gameForge.status != GameStatus.disposed) {
      unawaited(gameForge.dispose());
    }
  }
}
