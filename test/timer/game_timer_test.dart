import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('Timers & FakeGameClock', () {
    test(
      'CountdownTimer tracks ticks, pause/resume, completion, and reset deterministically',
      () async {
        final clock = FakeGameClock();
        final bus = GameEventBus();
        var completed = 0;

        final timer = CountdownTimer(
          id: 'round',
          duration: const Duration(seconds: 5),
          tickInterval: const Duration(seconds: 1),
          ticker: clock,
          clock: clock,
          eventBus: bus,
          onComplete: () => completed += 1,
        );

        expect(timer.status, TimerStatus.idle);
        expect(timer.remaining, const Duration(seconds: 5));

        timer.start();
        clock.advance(const Duration(seconds: 2));
        expect(timer.elapsed, const Duration(seconds: 2));
        expect(timer.remaining, const Duration(seconds: 3));
        expect(timer.state.tickCount, 2);

        timer.pause();
        expect(timer.status, TimerStatus.paused);
        clock.advance(const Duration(seconds: 10));
        expect(timer.remaining, const Duration(seconds: 3));
        expect(clock.activeTickerCount, 0);

        timer.resume();
        expect(timer.status, TimerStatus.running);
        clock.advance(const Duration(seconds: 3));
        expect(timer.status, TimerStatus.completed);
        expect(timer.remaining, Duration.zero);
        expect(completed, 1);

        // Further clock advances after completion do nothing
        clock.advance(const Duration(seconds: 5));
        expect(completed, 1);

        timer.reset();
        expect(timer.status, TimerStatus.idle);
        expect(timer.remaining, const Duration(seconds: 5));

        await timer.dispose();
        expect(timer.status, TimerStatus.disposed);
        expect(() => timer.start(), throwsA(isA<TimerException>()));
        await bus.dispose();
      },
    );

    test(
      'StopwatchTimer and PeriodicTimer honor pause/resume and max limits',
      () async {
        final clock = FakeGameClock();

        final stopwatch = StopwatchTimer(
          id: 'sw',
          maxDuration: const Duration(seconds: 4),
          tickInterval: const Duration(seconds: 1),
          ticker: clock,
          clock: clock,
        );
        stopwatch.start();
        clock.advance(const Duration(milliseconds: 2500));
        expect(stopwatch.elapsed, const Duration(seconds: 2));
        clock.advance(const Duration(seconds: 2));
        expect(stopwatch.status, TimerStatus.completed);
        expect(stopwatch.elapsed, const Duration(seconds: 4));

        var periodicTicks = 0;
        var periodicDone = false;
        final periodic = PeriodicTimer(
          id: 'spawn',
          period: const Duration(seconds: 2),
          tickInterval: const Duration(milliseconds: 500),
          maxTicks: 2,
          ticker: clock,
          clock: clock,
          onTick: (_) => periodicTicks += 1,
          onComplete: () => periodicDone = true,
        );

        periodic.start();
        clock.advance(const Duration(milliseconds: 1500));
        expect(periodicTicks, 0);
        periodic.pause();
        clock.advance(const Duration(seconds: 5));
        periodic.resume();
        clock.advance(const Duration(milliseconds: 500));
        expect(periodicTicks, 1);

        clock.advance(const Duration(seconds: 2));
        expect(periodic.status, TimerStatus.completed);
        expect(periodicDone, isTrue);

        await stopwatch.dispose();
        await periodic.dispose();
      },
    );

    test(
      'GameForge pause/resume only resumes timers paused by the game pause',
      () async {
        final clock = FakeGameClock();
        final game = GameForge(clock: clock, ticker: clock);
        await game.initialize();
        game.start();

        final activeTimer = game.timers.countdown(
          id: 'active',
          duration: const Duration(seconds: 10),
          tickInterval: const Duration(seconds: 1),
          autoStart: true,
        );
        final manuallyPausedTimer = game.timers.countdown(
          id: 'manual_paused',
          duration: const Duration(seconds: 10),
          tickInterval: const Duration(seconds: 1),
          autoStart: true,
        );

        clock.advance(const Duration(seconds: 2));
        manuallyPausedTimer.pause();

        game.pause();
        expect(activeTimer.status, TimerStatus.paused);
        expect(manuallyPausedTimer.status, TimerStatus.paused);

        clock.advance(const Duration(seconds: 5));
        expect(activeTimer.remaining, const Duration(seconds: 8));

        game.resume();
        expect(activeTimer.status, TimerStatus.running);
        expect(manuallyPausedTimer.status, TimerStatus.paused);

        await game.dispose();
        expect(clock.activeTickerCount, 0);
      },
    );
  });
}
