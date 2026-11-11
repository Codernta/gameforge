import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('GameSessionManager', () {
    test(
      'tracks duration excluding paused time, stats, and persisted history',
      () async {
        final clock = FakeGameClock();
        final storage = MemoryGameStorage();
        final manager = GameSessionManager(
          clock: clock,
          idGenerator: SequentialIdGenerator(),
          historyStorage: storage,
        );

        final s1 = manager.startSession(statistics: {'coins': 0});
        expect(s1.sessionId, 'session_1');
        expect(manager.status, SessionStatus.active);

        clock.advance(const Duration(seconds: 10));
        manager.recordStat('coins', 5);
        manager.setScore(120);
        expect(manager.current.duration, const Duration(seconds: 10));

        manager.pauseSession();
        expect(manager.status, SessionStatus.paused);
        clock.advance(const Duration(seconds: 30)); // paused time excluded!

        manager.resumeSession();
        clock.advance(const Duration(seconds: 5));
        final completed = manager.completeSession(finalScore: 200);

        expect(completed.status, SessionStatus.completed);
        expect(completed.duration, const Duration(seconds: 15));
        expect(completed.sessionScore, 200);
        expect(completed.statistics['coins'], 5);
        expect(manager.history, hasLength(1));

        // Allow unawaited saveHistory microtask to settle
        await Future<void>.delayed(Duration.zero);

        final restored = GameSessionManager(
          clock: clock,
          historyStorage: storage,
        );
        final history = await restored.loadHistory();
        expect(history, hasLength(1));
        expect(history.first.sessionId, 'session_1');
        expect(history.first.duration, const Duration(seconds: 15));

        await manager.dispose();
        await restored.dispose();
      },
    );

    test('guards invalid session lifecycle operations', () {
      final manager = GameSessionManager();
      expect(() => manager.pauseSession(), throwsA(isA<SessionException>()));
      expect(() => manager.resumeSession(), throwsA(isA<SessionException>()));
      expect(() => manager.completeSession(), throwsA(isA<SessionException>()));
      expect(
        () => manager.recordStat('hits', 1),
        throwsA(isA<SessionException>()),
      );

      manager.startSession();
      expect(() => manager.startSession(), throwsA(isA<SessionException>()));
      final abandoned = manager.abandonSession();
      expect(abandoned.status, SessionStatus.abandoned);
    });
  });
}
