import 'package:flutter/material.dart';

import '../../health/health_manager.dart';
import '../../health/health_state.dart';
import '../flutter/game_forge_scope.dart';

/// Visual presentation mode for [GameHealthWidget].
enum GameHealthDisplayMode {
  /// Displays remaining lives using filled/empty heart icons.
  hearts,

  /// Displays current/max health as an animated progress bar.
  bar,

  /// Displays both heart icons for lives and a health bar.
  both,
}

/// Displays player health and/or lives reactively from a [HealthManager].
class GameHealthWidget extends StatelessWidget {
  /// Creates a [GameHealthWidget].
  const GameHealthWidget({
    this.healthManager,
    this.mode = GameHealthDisplayMode.both,
    this.totalHearts,
    this.heartSize = 22.0,
    this.heartSpacing = 4.0,
    this.barWidth = 140.0,
    this.barHeight = 12.0,
    this.activeHeartColor,
    this.emptyHeartColor,
    this.barColor,
    this.barBackgroundColor,
    this.invincibleColor,
    this.showNumericValue = true,
    this.animationDuration = const Duration(milliseconds: 220),
    this.filledHeartIcon = Icons.favorite,
    this.emptyHeartIcon = Icons.favorite_border,
    this.builder,
    super.key,
  });

  /// Health manager to observe; falls back to `GameForgeScope.of(context).health`.
  final HealthManager? healthManager;

  /// Display mode (`hearts`, `bar`, or `both`).
  final GameHealthDisplayMode mode;

  /// Optional fixed number of heart icons to render; defaults to `maxLives` or
  /// current `lives`.
  final int? totalHearts;

  /// Size of each heart icon.
  final double heartSize;

  /// Horizontal spacing between heart icons.
  final double heartSpacing;

  /// Width of the health bar.
  final double barWidth;

  /// Height of the health bar.
  final double barHeight;

  /// Color for remaining life hearts; defaults to theme `error`.
  final Color? activeHeartColor;

  /// Color for lost life hearts; defaults to theme `outlineVariant`.
  final Color? emptyHeartColor;

  /// Fill color of the health bar; defaults to theme `primary`.
  final Color? barColor;

  /// Track color behind the health bar; defaults to theme
  /// `surfaceContainerHighest`.
  final Color? barBackgroundColor;

  /// Accent color used while the player is invincible.
  final Color? invincibleColor;

  /// Whether to show numeric `current / max` health label alongside the bar.
  final bool showNumericValue;

  /// Duration of health bar animations.
  final Duration animationDuration;

  /// Icon used for remaining lives.
  final IconData filledHeartIcon;

  /// Icon used for lost lives.
  final IconData emptyHeartIcon;

  /// Optional custom builder overriding default rendering.
  final Widget Function(BuildContext context, HealthState state)? builder;

  HealthManager _resolveManager(BuildContext context) =>
      healthManager ?? GameForgeScope.of(context).health;

  @override
  Widget build(BuildContext context) {
    final manager = _resolveManager(context);
    return StreamBuilder<HealthState>(
      initialData: manager.state,
      stream: manager.stream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? manager.state;
        if (builder != null) {
          return builder!(context, state);
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final resolvedHeartColor = activeHeartColor ?? colorScheme.error;
        final resolvedEmptyHeartColor =
            emptyHeartColor ?? colorScheme.outlineVariant;
        final resolvedBarColor = state.isInvincible
            ? (invincibleColor ?? colorScheme.tertiary)
            : (barColor ?? colorScheme.primary);
        final resolvedBarBg =
            barBackgroundColor ?? colorScheme.surfaceContainerHighest;

        final showHearts =
            state.supportsLives &&
            (mode == GameHealthDisplayMode.hearts ||
                mode == GameHealthDisplayMode.both);
        final showBar =
            mode == GameHealthDisplayMode.bar ||
            mode == GameHealthDisplayMode.both;

        final heartCount =
            totalHearts ??
            state.maxLives ??
            (state.lives > 0 ? state.lives : 0);

        return Semantics(
          label:
              'Health ${state.currentHealth.round()} of '
              '${state.maxHealth.round()}'
              '${state.supportsLives ? ', ${state.lives} lives' : ''}',
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHearts && heartCount > 0)
                Wrap(
                  spacing: heartSpacing,
                  children: List<Widget>.generate(heartCount, (index) {
                    final active = index < state.lives;
                    return Icon(
                      active ? filledHeartIcon : emptyHeartIcon,
                      size: heartSize,
                      color: active
                          ? resolvedHeartColor
                          : resolvedEmptyHeartColor,
                    );
                  }),
                ),
              if (showHearts && showBar && heartCount > 0)
                const SizedBox(height: 6),
              if (showBar)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: state.healthPercentage),
                      duration: animationDuration,
                      builder: (context, ratio, _) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(barHeight / 2),
                          child: Container(
                            width: barWidth,
                            height: barHeight,
                            color: resolvedBarBg,
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: ratio.clamp(0.0, 1.0),
                              child: Container(color: resolvedBarColor),
                            ),
                          ),
                        );
                      },
                    ),
                    if (showNumericValue) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${state.currentHealth.round()}/${state.maxHealth.round()}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
