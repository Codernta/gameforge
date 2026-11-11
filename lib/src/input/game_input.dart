import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/game_event.dart';

/// Pure Dart 2D vector / point used by engine-independent input abstractions.
@immutable
class InputVector2D {
  /// Creates an [InputVector2D].
  const InputVector2D(this.x, this.y);

  /// Zero vector `(0, 0)`.
  static const InputVector2D zero = InputVector2D(0, 0);

  /// Horizontal component.
  final double x;

  /// Vertical component.
  final double y;

  /// Euclidean magnitude of this vector.
  double get magnitude => math.sqrt(x * x + y * y);

  /// Returns a unit-length vector pointing in the same direction, or [zero].
  InputVector2D get normalized {
    final len = magnitude;
    if (len == 0) return zero;
    return InputVector2D(x / len, y / len);
  }

  /// Adds two vectors component-wise.
  InputVector2D operator +(InputVector2D other) =>
      InputVector2D(x + other.x, y + other.y);

  /// Subtracts [other] component-wise.
  InputVector2D operator -(InputVector2D other) =>
      InputVector2D(x - other.x, y - other.y);

  /// Scales this vector by [scalar].
  InputVector2D operator *(double scalar) =>
      InputVector2D(x * scalar, y * scalar);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InputVector2D && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'InputVector2D($x, $y)';
}

/// Cardinal and diagonal directions for swipes and directional controls.
enum InputDirection {
  /// Neutral / no active direction.
  none,

  /// Upwards.
  up,

  /// Downwards.
  down,

  /// Leftwards.
  left,

  /// Rightwards.
  right,

  /// Up-left diagonal.
  upLeft,

  /// Up-right diagonal.
  upRight,

  /// Down-left diagonal.
  downLeft,

  /// Down-right diagonal.
  downRight;

  /// Converts this direction into a normalized [InputVector2D] in screen space
  /// where `+x` is right and `+y` is down.
  InputVector2D toVector() {
    switch (this) {
      case InputDirection.none:
        return InputVector2D.zero;
      case InputDirection.up:
        return const InputVector2D(0, -1);
      case InputDirection.down:
        return const InputVector2D(0, 1);
      case InputDirection.left:
        return const InputVector2D(-1, 0);
      case InputDirection.right:
        return const InputVector2D(1, 0);
      case InputDirection.upLeft:
        return const InputVector2D(-1, -1).normalized;
      case InputDirection.upRight:
        return const InputVector2D(1, -1).normalized;
      case InputDirection.downLeft:
        return const InputVector2D(-1, 1).normalized;
      case InputDirection.downRight:
        return const InputVector2D(1, 1).normalized;
    }
  }
}

/// Lifecycle phase of a pointer drag gesture.
enum DragPhase {
  /// Drag gesture started.
  start,

  /// Drag gesture moved.
  update,

  /// Drag gesture ended.
  end,

  /// Drag gesture was cancelled.
  cancel,
}

/// Lifecycle phase of a keyboard key event.
enum KeyPhase {
  /// Key pressed down.
  down,

  /// Key released.
  up,

  /// Key held and auto-repeating.
  repeat,
}

/// Base class for all engine-independent player input events.
@immutable
sealed class GameInputEvent extends GameEvent {
  GameInputEvent({super.timestamp});
}

/// Single tap input at [position].
final class TapInputEvent extends GameInputEvent {
  /// Creates a [TapInputEvent].
  TapInputEvent({required this.position, this.pointerId = 0, super.timestamp});

  /// Tap location in local viewport coordinates.
  final InputVector2D position;

  /// Optional pointer identifier.
  final int pointerId;
}

/// Double tap input at [position].
final class DoubleTapInputEvent extends GameInputEvent {
  /// Creates a [DoubleTapInputEvent].
  DoubleTapInputEvent({
    required this.position,
    this.pointerId = 0,
    super.timestamp,
  });

  /// Double-tap location in local viewport coordinates.
  final InputVector2D position;

  /// Optional pointer identifier.
  final int pointerId;
}

/// Long press input at [position].
final class LongPressInputEvent extends GameInputEvent {
  /// Creates a [LongPressInputEvent].
  LongPressInputEvent({
    required this.position,
    this.duration = Duration.zero,
    this.pointerId = 0,
    super.timestamp,
  });

  /// Long-press location in local viewport coordinates.
  final InputVector2D position;

  /// Hold duration when triggered, if measured.
  final Duration duration;

  /// Optional pointer identifier.
  final int pointerId;
}

/// Drag input across [DragPhase] updates.
final class DragInputEvent extends GameInputEvent {
  /// Creates a [DragInputEvent].
  DragInputEvent({
    required this.phase,
    required this.position,
    this.delta = InputVector2D.zero,
    this.velocity = InputVector2D.zero,
    this.pointerId = 0,
    super.timestamp,
  });

  /// Drag phase (`start`, `update`, `end`, `cancel`).
  final DragPhase phase;

  /// Pointer location.
  final InputVector2D position;

  /// Position delta since previous update.
  final InputVector2D delta;

  /// Release velocity for [DragPhase.end].
  final InputVector2D velocity;

  /// Optional pointer identifier.
  final int pointerId;
}

/// Directional swipe gesture input.
final class SwipeInputEvent extends GameInputEvent {
  /// Creates a [SwipeInputEvent].
  SwipeInputEvent({
    required this.direction,
    this.velocity = 0.0,
    this.distance = 0.0,
    super.timestamp,
  });

  /// Primary direction of the swipe.
  final InputDirection direction;

  /// Swipe speed along primary axis.
  final double velocity;

  /// Distance travelled during the swipe.
  final double distance;
}

/// Discrete directional input (e.g., D-pad or arrow navigation).
final class DirectionalInputEvent extends GameInputEvent {
  /// Creates a [DirectionalInputEvent].
  DirectionalInputEvent({
    required this.direction,
    InputVector2D? vector,
    super.timestamp,
  }) : vector = vector ?? direction.toVector();

  /// Active direction (or [InputDirection.none] when released).
  final InputDirection direction;

  /// Vector representation of [direction].
  final InputVector2D vector;
}

/// Engine-independent keyboard input abstraction.
final class KeyInputEvent extends GameInputEvent {
  /// Creates a [KeyInputEvent].
  KeyInputEvent({
    required this.key,
    required this.phase,
    this.isShiftPressed = false,
    this.isControlPressed = false,
    this.isAltPressed = false,
    this.isMetaPressed = false,
    super.timestamp,
  });

  /// Logical key name (e.g., `'space'`, `'arrowLeft'`, `'keyW'`).
  final String key;

  /// Key transition phase (`down`, `up`, `repeat`).
  final KeyPhase phase;

  /// Whether Shift modifier is held.
  final bool isShiftPressed;

  /// Whether Control modifier is held.
  final bool isControlPressed;

  /// Whether Alt/Option modifier is held.
  final bool isAltPressed;

  /// Whether Meta/Command/Windows modifier is held.
  final bool isMetaPressed;
}

/// Continuous analog virtual joystick input abstraction.
final class JoystickInputEvent extends GameInputEvent {
  /// Creates a [JoystickInputEvent].
  JoystickInputEvent({
    required this.offset,
    this.isActive = true,
    super.timestamp,
  });

  /// Normalized joystick offset in `[-1, 1]` on both axes.
  final InputVector2D offset;

  /// Whether the joystick thumb is currently engaged (`false` on release).
  final bool isActive;

  /// Angle in radians (`atan2(y, x)`), or `0.0` at center.
  double get angle =>
      offset == InputVector2D.zero ? 0.0 : math.atan2(offset.y, offset.x);

  /// Clamped stick intensity in `[0.0, 1.0]`.
  double get intensity => math.min(1.0, offset.magnitude);
}
