import 'package:flutter/material.dart';

import '../../timer/game_timer.dart';
import '../../timer/timer_state.dart';

/// Signature for formatting a [TimerState] duration into display text.
typedef GameTimerFormatter = String Function(TimerState state);

/// Displays remaining or elapsed time reactively from any [GameTimer].
class GameTimerWidget extends StatelessWidget {
  /// Creates a [GameTimerWidget].
  const GameTimerWidget({
    required this.timer,
    this.showHours = false,
    this.showMilliseconds = false,
    this.warningThreshold,
    this.warningColor,
    this.showProgressBar = false,
    this.icon = Icons.timer_outlined,
    this.showIcon = true,
    this.textStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.decoration,
    this.formatter,
    this.builder,
    super.key,
  });

  /// Timer instance to observe.
  final GameTimer timer;

  /// Whether hours (`HH:MM:SS`) are included when formatting durations.
  final bool showHours;

  /// Whether tenths of a second (`MM:SS.d`) are displayed.
  final bool showMilliseconds;

  /// Optional remaining-time threshold below which [warningColor] is applied.
  final Duration? warningThreshold;

  /// Accent color used when remaining time is at or below [warningThreshold].
  final Color? warningColor;

  /// Whether to render a linear progress indicator beneath the time text.
  final bool showProgressBar;

  /// Optional leading icon displayed when [showIcon] is `true`.
  final IconData icon;

  /// Whether to render [icon].
  final bool showIcon;

  /// Text style override; defaults to theme `titleMedium` with tabular figures.
  final TextStyle? textStyle;

  /// Inner padding around the timer display.
  final EdgeInsetsGeometry padding;

  /// Container decoration override.
  final BoxDecoration? decoration;

  /// Custom formatter replacing default duration formatting.
  final GameTimerFormatter? formatter;

  /// Optional full custom builder receiving the latest [TimerState].
  final Widget Function(BuildContext context, TimerState state)? builder;

  /// Formats [duration] into `MM:SS` or `HH:MM:SS` (with optional tenths).
  static String formatDuration(
    Duration duration, {
    bool showHours = false,
    bool showMilliseconds = false,
  }) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    final tenths = safe.inMilliseconds.remainder(1000) ~/ 100;

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    final base = (showHours || hours > 0)
        ? '${hours.toString().padLeft(2, '0')}:$mm:$ss'
        : '$mm:$ss';

    return showMilliseconds ? '$base.$tenths' : base;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TimerState>(
      initialData: timer.state,
      stream: timer.stateStream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? timer.state;
        if (builder != null) {
          return builder!(context, state);
        }

        final displayDuration = state.remaining ?? state.elapsed;
        final text =
            formatter?.call(state) ??
            formatDuration(
              displayDuration,
              showHours: showHours,
              showMilliseconds: showMilliseconds,
            );

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isWarning =
            warningThreshold != null &&
            state.remaining != null &&
            state.remaining! <= warningThreshold!;
        final accentColor = isWarning
            ? (warningColor ?? colorScheme.error)
            : colorScheme.onSurface;

        final effectiveStyle = (textStyle ?? theme.textTheme.titleMedium)
            ?.copyWith(
              color: isWarning ? accentColor : textStyle?.color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            );

        final effectiveDecoration =
            decoration ??
            BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            );

        return Semantics(
          label: 'Timer: $text',
          liveRegion: true,
          child: Container(
            padding: padding,
            decoration: effectiveDecoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showIcon) ...[
                      Icon(icon, size: 18, color: accentColor),
                      const SizedBox(width: 6),
                    ],
                    Text(text, style: effectiveStyle),
                  ],
                ),
                if (showProgressBar && state.totalDuration != null) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 110,
                    child: LinearProgressIndicator(
                      value: (1.0 - state.progress).clamp(0.0, 1.0),
                      color: isWarning ? accentColor : colorScheme.primary,
                      backgroundColor: colorScheme.surface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
