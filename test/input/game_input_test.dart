import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('GameInputHandler & Input abstractions', () {
    test(
      'dispatches typed input events, key states, and action bindings',
      () async {
        final bus = GameEventBus();
        final handler = GameInputHandler(
          eventBus: bus,
          forwardToEventBus: true,
        );

        final actions = <String>[];
        final taps = <TapInputEvent>[];
        final forwarded = <GameInputEvent>[];

        final actionSub = handler.actionStream.listen(actions.add);
        final tapSub = handler.on<TapInputEvent>().listen(taps.add);
        final busSub = bus.on<GameInputEvent>(forwarded.add);

        handler.bindKey('Space', 'jump');
        handler.bindAction('fire', (event) => event is DoubleTapInputEvent);

        handler.dispatch(TapInputEvent(position: const InputVector2D(10, 20)));
        handler.dispatch(
          DoubleTapInputEvent(position: const InputVector2D(15, 25)),
        );
        handler.dispatch(KeyInputEvent(key: 'Space', phase: KeyPhase.down));
        expect(handler.isKeyPressed('Space'), isTrue);

        handler.dispatch(KeyInputEvent(key: 'Space', phase: KeyPhase.up));
        expect(handler.isKeyPressed('Space'), isFalse);

        final joy = JoystickInputEvent(offset: const InputVector2D(0.6, -0.8));
        handler.dispatch(joy);
        expect(handler.joystickOffset, const InputVector2D(0.6, -0.8));
        expect(joy.intensity, closeTo(1.0, 0.001));

        handler.dispatch(
          DirectionalInputEvent(direction: InputDirection.upLeft),
        );
        expect(handler.currentDirection, InputDirection.upLeft);

        handler.setEnabled(false);
        handler.dispatch(TapInputEvent(position: InputVector2D.zero));

        await Future<void>.delayed(Duration.zero);
        expect(taps, hasLength(1));
        expect(actions, ['fire', 'jump']);
        expect(forwarded, hasLength(6));

        await actionSub.cancel();
        await tapSub.cancel();
        await busSub.cancel();
        await handler.dispose();
        await bus.dispose();
      },
    );
  });
}
