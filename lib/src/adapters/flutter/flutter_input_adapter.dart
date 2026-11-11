import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../input/game_input.dart';
import '../../input/game_input_handler.dart';
import 'game_forge_scope.dart';

/// Bridges Flutter gesture and keyboard events into an engine-independent
/// [GameInputHandler].
class GameForgeInputRegion extends StatefulWidget {
  /// Creates a [GameForgeInputRegion].
  const GameForgeInputRegion({
    required this.child,
    this.inputHandler,
    this.autofocus = true,
    this.focusNode,
    this.swipeVelocityThreshold = 250.0,
    this.enableKeyboard = true,
    this.enableGestures = true,
    super.key,
  });

  /// Child widget rendered inside the interactive input region.
  final Widget child;

  /// Target input handler; falls back to `GameForgeScope.of(context).input`.
  final GameInputHandler? inputHandler;

  /// Whether keyboard focus should be requested automatically.
  final bool autofocus;

  /// Optional external [FocusNode] for keyboard listening.
  final FocusNode? focusNode;

  /// Minimum velocity (pixels/sec) required to emit a [SwipeInputEvent].
  final double swipeVelocityThreshold;

  /// Whether keyboard events are forwarded.
  final bool enableKeyboard;

  /// Whether pointer/touch gestures are forwarded.
  final bool enableGestures;

  @override
  State<GameForgeInputRegion> createState() => _GameForgeInputRegionState();
}

class _GameForgeInputRegionState extends State<GameForgeInputRegion> {
  FocusNode? _ownedFocusNode;
  Offset _lastTapPosition = Offset.zero;
  Offset _dragStartPosition = Offset.zero;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  GameInputHandler _resolveHandler(BuildContext context) =>
      widget.inputHandler ?? GameForgeScope.of(context).input;

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  InputVector2D _toVec(Offset offset) => InputVector2D(offset.dx, offset.dy);

  void _handleKeyEvent(BuildContext context, KeyEvent event) {
    if (!widget.enableKeyboard) return;
    final handler = _resolveHandler(context);

    final phase = switch (event) {
      KeyDownEvent() => KeyPhase.down,
      KeyUpEvent() => KeyPhase.up,
      KeyRepeatEvent() => KeyPhase.repeat,
      _ => null,
    };
    if (phase == null) return;

    final keyboard = HardwareKeyboard.instance;
    final keyName = event.logicalKey.keyLabel.isNotEmpty
        ? event.logicalKey.keyLabel
        : event.logicalKey.debugName ?? '${event.logicalKey.keyId}';

    handler.dispatch(
      KeyInputEvent(
        key: keyName,
        phase: phase,
        isShiftPressed: keyboard.isShiftPressed,
        isControlPressed: keyboard.isControlPressed,
        isAltPressed: keyboard.isAltPressed,
        isMetaPressed: keyboard.isMetaPressed,
      ),
    );
  }

  void _handlePanEnd(BuildContext context, DragEndDetails details) {
    final handler = _resolveHandler(context);
    final velocity = details.velocity.pixelsPerSecond;
    handler.dispatch(
      DragInputEvent(
        phase: DragPhase.end,
        position: _toVec(details.localPosition),
        velocity: _toVec(velocity),
      ),
    );

    final speed = velocity.distance;
    if (speed >= widget.swipeVelocityThreshold) {
      final delta = details.localPosition - _dragStartPosition;
      final direction = velocity.dx.abs() >= velocity.dy.abs()
          ? (velocity.dx >= 0 ? InputDirection.right : InputDirection.left)
          : (velocity.dy >= 0 ? InputDirection.down : InputDirection.up);
      handler.dispatch(
        SwipeInputEvent(
          direction: direction,
          velocity: speed,
          distance: delta.distance,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = widget.child;

    if (widget.enableGestures) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _lastTapPosition = details.localPosition,
        onTap: () => _resolveHandler(
          context,
        ).dispatch(TapInputEvent(position: _toVec(_lastTapPosition))),
        onDoubleTapDown: (details) => _lastTapPosition = details.localPosition,
        onDoubleTap: () => _resolveHandler(
          context,
        ).dispatch(DoubleTapInputEvent(position: _toVec(_lastTapPosition))),
        onLongPressStart: (details) => _resolveHandler(context).dispatch(
          LongPressInputEvent(position: _toVec(details.localPosition)),
        ),
        onPanStart: (details) {
          _dragStartPosition = details.localPosition;
          _resolveHandler(context).dispatch(
            DragInputEvent(
              phase: DragPhase.start,
              position: _toVec(details.localPosition),
            ),
          );
        },
        onPanUpdate: (details) => _resolveHandler(context).dispatch(
          DragInputEvent(
            phase: DragPhase.update,
            position: _toVec(details.localPosition),
            delta: _toVec(details.delta),
          ),
        ),
        onPanEnd: (details) => _handlePanEnd(context, details),
        onPanCancel: () => _resolveHandler(context).dispatch(
          DragInputEvent(
            phase: DragPhase.cancel,
            position: _toVec(_lastTapPosition),
          ),
        ),
        child: content,
      );
    }

    if (widget.enableKeyboard) {
      content = KeyboardListener(
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        onKeyEvent: (event) => _handleKeyEvent(context, event),
        child: content,
      );
    }

    return content;
  }
}

/// Customizable, accessible virtual thumbstick emitting [JoystickInputEvent]s.
class VirtualJoystickWidget extends StatefulWidget {
  /// Creates a [VirtualJoystickWidget].
  const VirtualJoystickWidget({
    this.inputHandler,
    this.onChanged,
    this.size = 120.0,
    this.knobSize = 44.0,
    this.baseColor,
    this.knobColor,
    this.borderColor,
    this.semanticLabel = 'Virtual game joystick',
    super.key,
  });

  /// Target input handler; falls back to `GameForgeScope.maybeOf(context)?.input`.
  final GameInputHandler? inputHandler;

  /// Optional direct callback receiving normalized joystick offsets.
  final ValueChanged<JoystickInputEvent>? onChanged;

  /// Outer diameter of the joystick pad.
  final double size;

  /// Diameter of the movable inner thumb knob.
  final double knobSize;

  /// Optional custom pad fill color; defaults to theme color scheme.
  final Color? baseColor;

  /// Optional custom thumb knob color; defaults to theme primary color.
  final Color? knobColor;

  /// Optional custom pad border color.
  final Color? borderColor;

  /// Accessibility label exposed via [Semantics].
  final String semanticLabel;

  @override
  State<VirtualJoystickWidget> createState() => _VirtualJoystickWidgetState();
}

class _VirtualJoystickWidgetState extends State<VirtualJoystickWidget> {
  Offset _knobOffset = Offset.zero;

  double get _maxRadius => math.max(1.0, (widget.size - widget.knobSize) / 2.0);

  void _updateFromLocalOffset(Offset localPosition) {
    final center = Offset(widget.size / 2.0, widget.size / 2.0);
    var delta = localPosition - center;
    final distance = delta.distance;
    if (distance > _maxRadius) {
      delta = delta / distance * _maxRadius;
    }
    setState(() => _knobOffset = delta);

    final normalized = InputVector2D(
      (delta.dx / _maxRadius).clamp(-1.0, 1.0),
      (delta.dy / _maxRadius).clamp(-1.0, 1.0),
    );
    _emit(JoystickInputEvent(offset: normalized, isActive: true));
  }

  void _resetKnob() {
    if (_knobOffset == Offset.zero) return;
    setState(() => _knobOffset = Offset.zero);
    _emit(JoystickInputEvent(offset: InputVector2D.zero, isActive: false));
  }

  void _emit(JoystickInputEvent event) {
    widget.onChanged?.call(event);
    final handler =
        widget.inputHandler ?? GameForgeScope.maybeOf(context)?.input;
    handler?.dispatch(event);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseFill =
        widget.baseColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.65);
    final knobFill = widget.knobColor ?? colorScheme.primary;
    final border = widget.borderColor ?? colorScheme.outlineVariant;

    return Semantics(
      label: widget.semanticLabel,
      child: GestureDetector(
        onPanStart: (details) => _updateFromLocalOffset(details.localPosition),
        onPanUpdate: (details) => _updateFromLocalOffset(details.localPosition),
        onPanEnd: (_) => _resetKnob(),
        onPanCancel: _resetKnob,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: baseFill,
              border: Border.all(color: border, width: 2),
            ),
            child: Center(
              child: Transform.translate(
                offset: _knobOffset,
                child: SizedBox(
                  width: widget.knobSize,
                  height: widget.knobSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: knobFill,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
