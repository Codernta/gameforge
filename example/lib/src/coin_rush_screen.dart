import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:gameforge/flutter.dart';

import 'coin_rush_engine.dart';
import 'coin_rush_storage.dart';

/// Interactive Flutter gameplay screen for Coin Rush.
class CoinRushScreen extends StatefulWidget {
  const CoinRushScreen({this.storage, super.key});

  final GameStorage? storage;

  @override
  State<CoinRushScreen> createState() => _CoinRushScreenState();
}

class _CoinRushScreenState extends State<CoinRushScreen>
    with SingleTickerProviderStateMixin {
  late final CoinRushEngine _engine;
  late final Ticker _frameTicker;
  Duration _lastElapsed = Duration.zero;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _engine = CoinRushEngine(
      storage: widget.storage ?? LocalPrefsGameStorage(),
    );
    _frameTicker = createTicker(_onTick);
    unawaited(_initGame());
  }

  Future<void> _initGame() async {
    await _engine.initialize();
    if (!mounted) return;
    setState(() => _initialized = true);
    _frameTicker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (!_initialized || _engine.game.status != GameStatus.running) {
      return;
    }
    setState(() {
      _engine.step(dt);
    });
  }

  @override
  void dispose() {
    _frameTicker.dispose();
    unawaited(_engine.dispose());
    super.dispose();
  }

  void _openShopSheet() {
    final wasRunning = _engine.game.status == GameStatus.running;
    if (wasRunning) {
      _engine.game.pause();
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return GameForgeBuilder(
          game: _engine.game,
          builder: (context, state, _) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reward Shop',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Chip(
                        avatar: const Icon(Icons.monetization_on, size: 18),
                        label: Text('${state.rewards.coinBalance} Coins'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final offer in CoinRushEngine.shopOffers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(offer.title),
                      subtitle: Text(offer.description),
                      trailing: FilledButton(
                        onPressed: state.rewards.coinBalance >= offer.costCoins
                            ? () async {
                                await _engine.purchaseOffer(offer);
                                if (mounted) setState(() {});
                              }
                            : null,
                        child: Text('${offer.costCoins}c'),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted && wasRunning && _engine.game.status == GameStatus.paused) {
        _engine.game.resume();
      }
    });
  }

  void _openLevelsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return GameForgeBuilder(
          game: _engine.game,
          builder: (context, state, _) {
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Text('Levels', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final level in _engine.game.levels.levels)
                  Builder(
                    builder: (context) {
                      final progress = state.levels.progressById[level.id]!;
                      final isCurrent = state.levels.currentLevelId == level.id;
                      return ListTile(
                        leading: CircleAvatar(child: Text('${level.number}')),
                        title: Text(level.name),
                        subtitle: Text(
                          progress.isCompleted
                              ? 'Completed • ${progress.stars}★ • Best ${progress.bestScore}'
                              : (progress.isUnlocked ? 'Unlocked' : 'Locked'),
                        ),
                        trailing: progress.isUnlocked
                            ? FilledButton.tonal(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  await _engine.selectLevel(level.id);
                                  if (mounted) setState(() {});
                                },
                                child: Text(isCurrent ? 'Current' : 'Play'),
                              )
                            : const Icon(Icons.lock_outline),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final game = _engine.game;
    return GameForgeScope(
      game: game,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Coin Rush'),
          actions: [
            IconButton(
              tooltip: 'Save Progress',
              icon: const Icon(Icons.save_outlined),
              onPressed: () async {
                await game.save();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Progress saved!')),
                );
              },
            ),
            IconButton(
              tooltip: 'Levels',
              icon: const Icon(Icons.map_outlined),
              onPressed: _openLevelsSheet,
            ),
            IconButton(
              tooltip: 'Reward Shop',
              icon: const Icon(Icons.storefront_outlined),
              onPressed: _openShopSheet,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // HUD Header driven by GameForge Flutter widgets
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  const GameScoreWidget(
                    showMultiplier: true,
                    showCombo: true,
                    showHighScore: true,
                  ),
                  const GameHealthWidget(
                    mode: GameHealthDisplayMode.hearts,
                    totalHearts: 5,
                  ),
                  GameTimerWidget(
                    timer: _engine.levelTimer,
                    warningThreshold: const Duration(seconds: 10),
                    showProgressBar: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GameForgeBuilder(
                builder: (context, state, _) {
                  final level = game.levels.currentLevel;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Level ${level.number}: ${level.name} '
                        '(${_engine.levelCoinsCollected}/${_engine.currentLevelTargetCoins} coins)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Chip(
                        avatar: const Icon(Icons.monetization_on, size: 16),
                        label: Text('${state.rewards.coinBalance}c'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              // Interactive Arena
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        GameForgeInputRegion(
                          child: Listener(
                            onPointerDown: (event) {
                              if (game.status != GameStatus.running) return;
                              final normX =
                                  (event.localPosition.dx /
                                          constraints.maxWidth)
                                      .clamp(0.05, 0.95);
                              final normY =
                                  (event.localPosition.dy /
                                          constraints.maxHeight)
                                      .clamp(0.05, 0.95);
                              game.input.dispatch(
                                TapInputEvent(
                                  position: InputVector2D(normX, normY),
                                ),
                              );
                            },
                            child: CustomPaint(
                              size: Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: _CoinRushPainter(engine: _engine),
                            ),
                          ),
                        ),
                        if (game.status == GameStatus.running)
                          const Positioned(
                            right: 12,
                            bottom: 12,
                            child: Opacity(
                              opacity: 0.85,
                              child: VirtualJoystickWidget(size: 104),
                            ),
                          ),
                        GameForgeStatusBuilder(
                          builder: (context, status, _) {
                            if (status == GameStatus.running) {
                              return const SizedBox.shrink();
                            }
                            return _StatusOverlay(
                              status: status,
                              score: game.score.currentScore,
                              highScore: game.score.highScore,
                              onStartOrResume: () {
                                if (status == GameStatus.paused) {
                                  game.resume();
                                } else {
                                  _engine.startRun();
                                }
                                setState(() {});
                              },
                              onRestart: () {
                                _engine.game.restart(autoStart: true);
                                _engine.startRun();
                                setState(() {});
                              },
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Controls and Event Feed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _engine.recentEvents.isEmpty
                          ? 'Move with WASD/Arrows, tap arena, or use joystick.'
                          : _engine.recentEvents.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Row(
                    children: [
                      if (game.status == GameStatus.running)
                        OutlinedButton.icon(
                          onPressed: () {
                            game.pause();
                            setState(() {});
                          },
                          icon: const Icon(Icons.pause),
                          label: const Text('Pause'),
                        ),
                      if (game.status == GameStatus.paused)
                        FilledButton.icon(
                          onPressed: () {
                            game.resume();
                            setState(() {});
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Resume'),
                        ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          game.restart(autoStart: true);
                          _engine.startRun();
                          setState(() {});
                        },
                        child: const Text('Restart'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  const _StatusOverlay({
    required this.status,
    required this.score,
    required this.highScore,
    required this.onStartOrResume,
    required this.onRestart,
  });

  final GameStatus status;
  final int score;
  final int highScore;
  final VoidCallback onStartOrResume;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final title = switch (status) {
      GameStatus.ready => 'Coin Rush',
      GameStatus.paused => 'Paused',
      GameStatus.completed => 'Victory! All Levels Cleared!',
      GameStatus.gameOver => 'Game Over',
      _ => status.name,
    };
    final actionLabel = switch (status) {
      GameStatus.ready => 'Start Game',
      GameStatus.paused => 'Resume',
      GameStatus.completed || GameStatus.gameOver => 'Play Again',
      _ => 'Continue',
    };

    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Score: $score  •  Best: $highScore'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: onStartOrResume,
                      child: Text(actionLabel),
                    ),
                    if (status == GameStatus.paused)
                      OutlinedButton(
                        onPressed: onRestart,
                        child: const Text('Restart'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoinRushPainter extends CustomPainter {
  _CoinRushPainter({required this.engine});

  final CoinRushEngine engine;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF161B26);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      bgPaint,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final dx = size.width * i / 6;
      final dy = size.height * i / 6;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    final minDim = size.shortestSide;
    for (final coin in engine.coins) {
      final paint = Paint()
        ..color = coin.isBonus
            ? const Color(0xFF38BDF8)
            : const Color(0xFFFACC15);
      canvas.drawCircle(
        Offset(coin.x * size.width, coin.y * size.height),
        coin.radius * minDim,
        paint,
      );
    }

    final obstaclePaint = Paint()..color = const Color(0xFFEF4444);
    for (final obstacle in engine.obstacles) {
      canvas.drawCircle(
        Offset(obstacle.x * size.width, obstacle.y * size.height),
        obstacle.radius * minDim,
        obstaclePaint,
      );
    }

    final isInvincible = engine.game.health.isInvincible;
    final playerPaint = Paint()
      ..color = isInvincible
          ? const Color(0xFF34D399).withValues(alpha: 0.65)
          : const Color(0xFF34D399);
    canvas.drawCircle(
      Offset(engine.playerX * size.width, engine.playerY * size.height),
      engine.playerRadius * minDim,
      playerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CoinRushPainter oldDelegate) => true;
}
