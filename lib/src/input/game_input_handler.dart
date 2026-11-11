import 'dart:async';

import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import 'game_input.dart';

/// Predicate matching a [GameInputEvent] to a logical action name.
typedef GameInputMatcher = bool Function(GameInputEvent event);

/// Engine-independent input dispatcher, typed stream provider, and logical
/// action mapper.
class GameInputHandler extends GameModule {
  /// Creates a [GameInputHandler].
  GameInputHandler({GameEventBus? eventBus, this.forwardToEventBus = false})
    : _eventBus = eventBus;

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'input';

  /// Whether dispatched input events should also be mirrored onto [GameEventBus].
  final bool forwardToEventBus;

  GameEventBus? _eventBus;
  final StreamController<GameInputEvent> _inputController =
      StreamController<GameInputEvent>.broadcast();
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  final Map<String, List<GameInputMatcher>> _bindings = {};
  final Set<String> _pressedKeys = {};
  InputVector2D _joystickOffset = InputVector2D.zero;
  InputDirection _currentDirection = InputDirection.none;
  bool _isDisposed = false;
  bool _isEnabled = true;

  @override
  String get id => moduleId;

  /// Whether incoming input dispatch is currently enabled.
  bool get isEnabled => _isEnabled;

  /// Unmodifiable set of currently held logical key names.
  Set<String> get pressedKeys => Set<String>.unmodifiable(_pressedKeys);

  /// Most recent joystick offset vector.
  InputVector2D get joystickOffset => _joystickOffset;

  /// Most recent directional input.
  InputDirection get currentDirection => _currentDirection;

  /// Broadcast stream of all dispatched [GameInputEvent]s.
  Stream<GameInputEvent> get stream => _inputController.stream;

  /// Broadcast stream of triggered logical action names from [bindAction].
  Stream<String> get actionStream => _actionController.stream;

  /// Filtered broadcast stream for a specific [GameInputEvent] subtype [T].
  Stream<T> on<T extends GameInputEvent>() =>
      _inputController.stream.where((event) => event is T).cast<T>();

  @override
  void onInitialize(GameModuleContext context) {
    _eventBus ??= context.events;
  }

  @override
  void onPause() {
    _pressedKeys.clear();
    _joystickOffset = InputVector2D.zero;
    _currentDirection = InputDirection.none;
  }

  @override
  void onReset() {
    _pressedKeys.clear();
    _joystickOffset = InputVector2D.zero;
    _currentDirection = InputDirection.none;
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Enables or disables input dispatching (useful during menus/cutscenes).
  void setEnabled(bool enabled) {
    _ensureNotDisposed();
    _isEnabled = enabled;
    if (!enabled) {
      _pressedKeys.clear();
      _joystickOffset = InputVector2D.zero;
      _currentDirection = InputDirection.none;
    }
  }

  /// Registers a [matcher] triggering logical [action] when matched.
  void bindAction(String action, GameInputMatcher matcher) {
    _ensureNotDisposed();
    if (action.trim().isEmpty) {
      throw const GameConfigurationException('Action name cannot be empty.');
    }
    _bindings.putIfAbsent(action, () => []).add(matcher);
  }

  /// Convenience helper binding a keyboard key press (`KeyPhase.down`) to
  /// [action].
  void bindKey(String key, String action) {
    bindAction(
      action,
      (event) =>
          event is KeyInputEvent &&
          event.phase == KeyPhase.down &&
          event.key == key,
    );
  }

  /// Removes all bindings registered for [action].
  void unbindAction(String action) {
    _bindings.remove(action);
  }

  /// Returns `true` if [key] is currently pressed.
  bool isKeyPressed(String key) => _pressedKeys.contains(key);

  /// Dispatches an engine-independent [event] to subscribers and action maps.
  void dispatch(GameInputEvent event) {
    _ensureNotDisposed();
    if (!_isEnabled) {
      return;
    }

    switch (event) {
      case KeyInputEvent(:final key, :final phase):
        if (phase == KeyPhase.down || phase == KeyPhase.repeat) {
          _pressedKeys.add(key);
        } else if (phase == KeyPhase.up) {
          _pressedKeys.remove(key);
        }
      case JoystickInputEvent(:final offset, :final isActive):
        _joystickOffset = isActive ? offset : InputVector2D.zero;
      case DirectionalInputEvent(:final direction):
        _currentDirection = direction;
      case TapInputEvent():
      case DoubleTapInputEvent():
      case LongPressInputEvent():
      case DragInputEvent():
      case SwipeInputEvent():
        break;
    }

    if (!_inputController.isClosed) {
      _inputController.add(event);
    }

    if (forwardToEventBus && _eventBus != null && !_eventBus!.isDisposed) {
      _eventBus!.emit(event);
    }

    for (final entry in _bindings.entries) {
      for (final matcher in entry.value) {
        if (matcher(event)) {
          if (!_actionController.isClosed) {
            _actionController.add(entry.key);
          }
          break;
        }
      }
    }
  }

  /// Releases stream controllers and clears bindings.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _bindings.clear();
    _pressedKeys.clear();
    await _actionController.close();
    await _inputController.close();
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot use GameInputHandler after it has been disposed.',
      );
    }
  }
}
