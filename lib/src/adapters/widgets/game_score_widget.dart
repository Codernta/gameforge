import 'package:flutter/material.dart';

import '../../score/score_manager.dart';
import '../../score/score_state.dart';
import '../flutter/game_forge_scope.dart';

/// Displays and animates a player's current score from a [ScoreManager].
class GameScoreWidget extends StatefulWidget {
  /// Creates a [GameScoreWidget].
  const GameScoreWidget({
    this.scoreManager,
    this.label = 'Score',
    this.showLabel = true,
    this.showMultiplier = true,
    this.showCombo = false,
    this.showHighScore = false,
    this.animationDuration = const Duration(milliseconds: 280),
    this.curve = Curves.easeOutCubic,
    this.scoreFormatter,
    this.textStyle,
    this.labelStyle,
    this.badgeStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.decoration,
    this.builder,
    super.key,
  });

  /// Score manager to observe; falls back to `GameForgeScope.of(context).score`.
  final ScoreManager? scoreManager;

  /// Optional prefix/caption label shown when [showLabel] is `true`.
  final String label;

  /// Whether to render [label].
  final bool showLabel;

  /// Whether to render an active multiplier badge when multiplier != `1.0`.
  final bool showMultiplier;

  /// Whether to render an active combo badge when `comboCount > 0`.
  final bool showCombo;

  /// Whether to render the current high score beneath or alongside score.
  final bool showHighScore;

  /// Duration of animated numeric score transitions.
  final Duration animationDuration;

  /// Animation curve for score transitions.
  final Curve curve;

  /// Optional formatter converting an integer score to display text.
  final String Function(int score)? scoreFormatter;

  /// Text style for the score value; defaults to theme `titleLarge`.
  final TextStyle? textStyle;

  /// Text style for [label]; defaults to theme `labelMedium`.
  final TextStyle? labelStyle;

  /// Text style for multiplier/combo badges.
  final TextStyle? badgeStyle;

  /// Inner padding around the widget content.
  final EdgeInsetsGeometry padding;

  /// Optional container decoration; defaults to a theme-tinted rounded card.
  final BoxDecoration? decoration;

  /// Optional full custom builder receiving the current animated score and
  /// [ScoreState].
  final Widget Function(
    BuildContext context,
    int animatedScore,
    ScoreState state,
  )?
  builder;

  @override
  State<GameScoreWidget> createState() => _GameScoreWidgetState();
}

class _GameScoreWidgetState extends State<GameScoreWidget> {
  int _previousTarget = 0;
  bool _initialized = false;

  ScoreManager _resolveManager(BuildContext context) =>
      widget.scoreManager ?? GameForgeScope.of(context).score;

  @override
  Widget build(BuildContext context) {
    final manager = _resolveManager(context);
    return StreamBuilder<ScoreState>(
      initialData: manager.state,
      stream: manager.stream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? manager.state;
        final target = state.currentScore;
        final begin = _initialized ? _previousTarget : target;
        _initialized = true;
        _previousTarget = target;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: begin.toDouble(), end: target.toDouble()),
          duration: widget.animationDuration,
          curve: widget.curve,
          builder: (context, value, _) {
            final animatedValue = value.round();
            if (widget.builder != null) {
              return widget.builder!(context, animatedValue, state);
            }

            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final formatted =
                widget.scoreFormatter?.call(animatedValue) ?? '$animatedValue';
            final effectiveDecoration =
                widget.decoration ??
                BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                );
            final effectiveScoreStyle =
                widget.textStyle ??
                theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                );
            final effectiveLabelStyle =
                widget.labelStyle ??
                theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                );
            final effectiveBadgeStyle =
                widget.badgeStyle ??
                theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                );

            return Semantics(
              label: '${widget.label}: $target',
              liveRegion: true,
              child: Container(
                padding: widget.padding,
                decoration: effectiveDecoration,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showLabel)
                      Text(widget.label, style: effectiveLabelStyle),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(formatted, style: effectiveScoreStyle),
                        if (widget.showMultiplier &&
                            state.multiplier != 1.0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${state.multiplier.toStringAsFixed(1)}x',
                              style: effectiveBadgeStyle,
                            ),
                          ),
                        ],
                        if (widget.showCombo && state.comboCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${state.comboCount}x combo',
                              style: effectiveBadgeStyle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.showHighScore) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Best: ${state.highScore}',
                        style: effectiveLabelStyle,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
