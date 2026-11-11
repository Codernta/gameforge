import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

final class _PingEvent extends GameEvent {
  _PingEvent(this.count);
  final int count;
}

final class _PongEvent extends GameEvent {
  _PongEvent(this.count);
  final int count;
}

void main() {
  group('GameEventBus', () {
    test(
      'delivers strongly typed events with filtering and cancellation',
      () async {
        final bus = GameEventBus();
        final received = <int>[];

        final sub = bus.on<_PingEvent>(
          (event) => received.add(event.count),
          where: (event) => event.count.isEven,
        );

        bus.emit(_PingEvent(1));
        bus.emit(_PingEvent(2));
        bus.emit(_PongEvent(3));
        bus.emit(_PingEvent(4));

        await Future<void>.delayed(Duration.zero);
        expect(received, [2, 4]);

        await sub.cancel();
        bus.emit(_PingEvent(6));
        await Future<void>.delayed(Duration.zero);
        expect(received, [2, 4]);

        await bus.dispose();
      },
    );

    test(
      'supports broadcast stream<T> with multiple subscribers and once<T>',
      () async {
        final bus = GameEventBus();
        final stream = bus.stream<_PingEvent>();
        final listA = <int>[];
        final listB = <int>[];

        final subA = stream.listen((e) => listA.add(e.count));
        final subB = stream.listen((e) => listB.add(e.count));
        final nextFuture = bus.once<_PingEvent>(where: (e) => e.count == 99);

        bus.emit(_PingEvent(10));
        bus.emit(_PingEvent(99));

        expect((await nextFuture).count, 99);
        expect(listA, [10, 99]);
        expect(listB, [10, 99]);

        await subA.cancel();
        await subB.cancel();
        await bus.dispose();
      },
    );

    test(
      'routes subscriber exceptions to onError without breaking bus',
      () async {
        final errors = <Object>[];
        final bus = GameEventBus(onError: (error, _) => errors.add(error));
        final healthyReceived = <int>[];

        final sub1 = bus.on<_PingEvent>((_) => throw StateError('bad handler'));
        final sub2 = bus.on<_PingEvent>((e) => healthyReceived.add(e.count));

        bus.emit(_PingEvent(7));
        await Future<void>.delayed(Duration.zero);

        expect(errors, hasLength(1));
        expect(errors.first, isA<StateError>());
        expect(healthyReceived, [7]);

        await sub1.cancel();
        await sub2.cancel();
        await bus.dispose();
      },
    );

    test('prevents uncontrolled recursive event loops', () async {
      final captured = <Object>[];
      final bus = GameEventBus(
        maxCascadeDepth: 5,
        onError: (error, _) => captured.add(error),
      );

      final sub1 = bus.on<_PingEvent>((e) => bus.emit(_PongEvent(e.count + 1)));
      final sub2 = bus.on<_PongEvent>((e) => bus.emit(_PingEvent(e.count + 1)));

      bus.emit(_PingEvent(0));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(captured.whereType<GameEventLoopException>(), isNotEmpty);

      await sub1.cancel();
      await sub2.cancel();
      await bus.dispose();
    });

    test('closes streams and guards operations after dispose', () async {
      final bus = GameEventBus();
      var done = false;
      final sub = bus.stream<_PingEvent>().listen(
        (_) {},
        onDone: () => done = true,
      );

      await bus.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(bus.isDisposed, isTrue);
      expect(done, isTrue);
      expect(() => bus.emit(_PingEvent(1)), throwsA(isA<GameStateException>()));
      expect(bus.tryEmit(_PingEvent(1)), isFalse);
      expect(
        () => bus.on<_PingEvent>((_) {}),
        throwsA(isA<GameStateException>()),
      );
      expect(bus.stream<_PingEvent>(), emitsDone);

      await sub.cancel();
    });
  });
}
