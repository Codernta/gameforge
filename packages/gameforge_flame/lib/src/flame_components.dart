import 'dart:async';

import 'package:flame/components.dart';
import 'package:gameforge/gameforge.dart';

/// Reactive Flame [Component] that keeps synchronized [ScoreState] from
/// [ScoreManager] and cleans up stream subscriptions on removal.
class GameForgeScoreComponent extends Component {
  /// Creates a [GameForgeScoreComponent].
  GameForgeScoreComponent({required this.scoreManager, this.onScoreChanged})
    : _latest = scoreManager.state;

  /// Observed [ScoreManager].
  final ScoreManager scoreManager;

  /// Optional callback invoked whenever score state updates.
  final void Function(ScoreState state)? onScoreChanged;

  StreamSubscription<ScoreState>? _subscription;
  ScoreState _latest;

  /// Latest synchronized [ScoreState].
  ScoreState get state => _latest;

  /// Current score value.
  int get currentScore => _latest.currentScore;

  /// Current high score value.
  int get highScore => _latest.highScore;

  @override
  void onMount() {
    super.onMount();
    _latest = scoreManager.state;
    onScoreChanged?.call(_latest);
    _subscription = scoreManager.stream.listen((next) {
      _latest = next;
      onScoreChanged?.call(next);
    });
  }

  @override
  void onRemove() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.onRemove();
  }
}

/// Reactive Flame [Component] that keeps synchronized [HealthState] from
/// [HealthManager] and cleans up stream subscriptions on removal.
class GameForgeHealthComponent extends Component {
  /// Creates a [GameForgeHealthComponent].
  GameForgeHealthComponent({required this.healthManager, this.onHealthChanged})
    : _latest = healthManager.state;

  /// Observed [HealthManager].
  final HealthManager healthManager;

  /// Optional callback invoked whenever health state updates.
  final void Function(HealthState state)? onHealthChanged;

  StreamSubscription<HealthState>? _subscription;
  HealthState _latest;

  /// Latest synchronized [HealthState].
  HealthState get state => _latest;

  /// Current health value.
  double get currentHealth => _latest.currentHealth;

  /// Remaining lives count.
  int get lives => _latest.lives;

  /// Whether the player is permanently dead.
  bool get isDead => _latest.isDead;

  @override
  void onMount() {
    super.onMount();
    _latest = healthManager.state;
    onHealthChanged?.call(_latest);
    _subscription = healthManager.stream.listen((next) {
      _latest = next;
      onHealthChanged?.call(next);
    });
  }

  @override
  void onRemove() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.onRemove();
  }
}

/// Flame [Component] subscribing to strongly typed [GameEvent]s on [eventBus]
/// while mounted and automatically unsubscribing in [onRemove].
class GameForgeEventListenerComponent<T extends GameEvent> extends Component {
  /// Creates a [GameForgeEventListenerComponent].
  GameForgeEventListenerComponent({
    required this.eventBus,
    required this.onEvent,
    this.where,
  });

  /// Event bus to subscribe to.
  final GameEventBus eventBus;

  /// Callback invoked for each matching event.
  final void Function(T event) onEvent;

  /// Optional filter predicate.
  final bool Function(T event)? where;

  StreamSubscription<T>? _subscription;

  @override
  void onMount() {
    super.onMount();
    if (!eventBus.isDisposed) {
      _subscription = eventBus.on<T>(onEvent, where: where);
    }
  }

  @override
  void onRemove() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.onRemove();
  }
}
