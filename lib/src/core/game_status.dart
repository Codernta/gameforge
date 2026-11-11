/// Represents the lifecycle state of a [GameForge] controller instance.
///
/// Allowed transitions:
/// - [uninitialized] -> [initializing], [disposed]
/// - [initializing] -> [ready], [uninitialized] (on initialization failure),
///   [disposed]
/// - [ready] -> [running], [disposed]
/// - [running] -> [paused], [completed], [gameOver], [ready] (via restart),
///   [disposed]
/// - [paused] -> [running], [completed], [gameOver], [ready] (via restart),
///   [disposed]
/// - [completed] -> [ready] (via restart), [running] (via restart), [disposed]
/// - [gameOver] -> [ready] (via restart), [running] (via restart), [disposed]
/// - [disposed] -> terminal state (no outgoing transitions)
enum GameStatus {
  /// The game controller has been constructed but [GameForge.initialize]
  /// has not completed yet.
  uninitialized,

  /// Asynchronous initialization is currently in progress.
  initializing,

  /// Initialization succeeded and the game is ready to start.
  ready,

  /// Active gameplay is in progress.
  running,

  /// Active gameplay is temporarily paused.
  paused,

  /// The game or objective finished with a win/completion state.
  completed,

  /// The game ended in a failure or zero-lives game-over state.
  gameOver,

  /// The game controller and all modules have been permanently disposed.
  disposed;

  static const Map<GameStatus, Set<GameStatus>> _allowedTransitions = {
    GameStatus.uninitialized: {GameStatus.initializing, GameStatus.disposed},
    GameStatus.initializing: {
      GameStatus.ready,
      GameStatus.uninitialized,
      GameStatus.disposed,
    },
    GameStatus.ready: {GameStatus.running, GameStatus.disposed},
    GameStatus.running: {
      GameStatus.paused,
      GameStatus.completed,
      GameStatus.gameOver,
      GameStatus.ready,
      GameStatus.disposed,
    },
    GameStatus.paused: {
      GameStatus.running,
      GameStatus.completed,
      GameStatus.gameOver,
      GameStatus.ready,
      GameStatus.disposed,
    },
    GameStatus.completed: {
      GameStatus.ready,
      GameStatus.running,
      GameStatus.disposed,
    },
    GameStatus.gameOver: {
      GameStatus.ready,
      GameStatus.running,
      GameStatus.disposed,
    },
    GameStatus.disposed: <GameStatus>{},
  };

  /// Returns `true` if transitioning directly from `this` to [next] is valid.
  bool canTransitionTo(GameStatus next) {
    return _allowedTransitions[this]!.contains(next);
  }

  /// Set of valid target statuses directly reachable from `this`.
  Set<GameStatus> get allowedNextStatuses =>
      Set<GameStatus>.unmodifiable(_allowedTransitions[this]!);

  /// Whether gameplay is currently active or paused.
  bool get isActiveSession =>
      this == GameStatus.running || this == GameStatus.paused;

  /// Whether the game has been initialized and not yet disposed.
  bool get isInitialized =>
      this != GameStatus.uninitialized &&
      this != GameStatus.initializing &&
      this != GameStatus.disposed;
}
