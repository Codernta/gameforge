import '../core/game_exception.dart';
import 'game_timer.dart';
import 'timer_state.dart';

/// Countdown timer that decrements from [duration] down to [Duration.zero].
class CountdownTimer extends GameTimer {
  /// Creates a [CountdownTimer].
  CountdownTimer({
    required super.id,
    required this.duration,
    super.tickInterval = const Duration(milliseconds: 100),
    super.ticker,
    super.clock,
    super.eventBus,
    super.emitTickEvents,
    super.onTick,
    super.onComplete,
  }) {
    if (duration <= Duration.zero) {
      throw TimerException(
        'CountdownTimer "$id" duration must be greater than Duration.zero.',
      );
    }
    initState(
      TimerState(
        id: id,
        status: TimerStatus.idle,
        elapsed: Duration.zero,
        totalDuration: duration,
        remaining: duration,
      ),
    );
  }

  /// Initial countdown duration.
  final Duration duration;

  @override
  void onHandleTick(Duration delta) {
    var nextElapsed = state.elapsed + delta;
    final nextTicks = state.tickCount + 1;

    if (nextElapsed >= duration) {
      nextElapsed = duration;
      markCompleted(
        state.copyWith(
          elapsed: duration,
          remaining: Duration.zero,
          tickCount: nextTicks,
        ),
      );
      return;
    }

    updateState(
      state.copyWith(
        elapsed: nextElapsed,
        remaining: duration - nextElapsed,
        tickCount: nextTicks,
      ),
      isTick: true,
    );
  }

  @override
  void onResetState() {
    initState(
      TimerState(
        id: id,
        status: TimerStatus.idle,
        elapsed: Duration.zero,
        totalDuration: duration,
        remaining: duration,
      ),
    );
  }
}
