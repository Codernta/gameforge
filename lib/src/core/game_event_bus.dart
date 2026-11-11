import 'dart:async';

import 'game_event.dart';
import 'game_exception.dart';

/// Signature for handling errors thrown by event bus listeners.
typedef GameEventErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class _EventEnvelope {
  const _EventEnvelope(this.event, this.depth);

  final GameEvent event;
  final int depth;
}

/// Strongly typed publish-subscribe event bus for GameForge modules and games.
///
/// By default events are broadcast asynchronously on the microtask queue so
/// listeners do not mutate state mid-call. Uncontrolled listener-to-listener
/// event loops are guarded using [maxCascadeDepth], throwing
/// [GameEventLoopException] (or routing it to [onError]) if exceeded.
class GameEventBus {
  /// Creates a [GameEventBus].
  GameEventBus({bool sync = false, this.maxCascadeDepth = 64, this.onError})
    : assert(maxCascadeDepth > 0, 'maxCascadeDepth must be positive.'),
      _controller = StreamController<_EventEnvelope>.broadcast(sync: sync);

  final StreamController<_EventEnvelope> _controller;
  final List<StreamSubscription<Object?>> _managedSubscriptions = [];
  final Object _depthZoneKey = Object();

  /// Maximum nested listener-triggered emission depth before assuming a loop.
  final int maxCascadeDepth;

  /// Optional error handler invoked when a subscriber throws an exception.
  final GameEventErrorHandler? onError;

  bool _isDisposed = false;

  /// Whether [dispose] has been called on this event bus.
  bool get isDisposed => _isDisposed;

  /// Broadcast stream of all events of subtype [T].
  ///
  /// Listeners registered on this stream execute in a cascade-tracked zone
  /// so nested [emit] calls are guarded against infinite event loops.
  Stream<T> stream<T extends GameEvent>() {
    if (_isDisposed) {
      return Stream<T>.empty();
    }
    return Stream<T>.multi((controller) {
      if (_isDisposed) {
        unawaited(controller.close());
        return;
      }
      final subscription = _controller.stream.listen(
        (envelope) {
          final event = envelope.event;
          if (event is T) {
            runZoned(
              () => controller.add(event),
              zoneValues: {_depthZoneKey: envelope.depth},
            );
          }
        },
        onDone: () => unawaited(controller.close()),
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  /// Subscribes [handler] to events of type [T], returning a
  /// [StreamSubscription] that should be cancelled when no longer needed.
  ///
  /// Optional [where] filters incoming events before invoking [handler].
  /// Errors thrown by [handler] are caught and passed to [onError] (or the
  /// bus-level [GameEventBus.onError]) rather than leaving unhandled errors.
  StreamSubscription<T> on<T extends GameEvent>(
    void Function(T event) handler, {
    bool Function(T event)? where,
    GameEventErrorHandler? onError,
  }) {
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot subscribe to events after GameEventBus has been disposed.',
      );
    }

    late final StreamSubscription<_EventEnvelope> subscription;
    subscription = _controller.stream.listen((envelope) {
      final event = envelope.event;
      if (event is! T) {
        return;
      }
      runZoned(() {
        try {
          if (where != null && !where(event)) {
            return;
          }
          handler(event);
        } catch (error, stackTrace) {
          final handlerError = onError ?? this.onError;
          if (handlerError != null) {
            handlerError(error, stackTrace);
          } else {
            Zone.current.handleUncaughtError(error, stackTrace);
          }
        }
      }, zoneValues: {_depthZoneKey: envelope.depth});
    });

    _managedSubscriptions.add(subscription);
    return _TypedEventSubscription<T>(subscription, () {
      _managedSubscriptions.remove(subscription);
    });
  }

  /// Returns a [Future] completing with the next event of type [T] matching
  /// [where], optionally failing with [TimeoutException] after [timeout].
  Future<T> once<T extends GameEvent>({
    bool Function(T event)? where,
    Duration? timeout,
  }) {
    if (_isDisposed) {
      return Future<T>.error(
        const GameStateException(
          'Cannot await events after GameEventBus has been disposed.',
        ),
      );
    }

    final completer = Completer<T>();
    late final StreamSubscription<T> subscription;
    subscription = on<T>(
      (event) {
        if (!completer.isCompleted) {
          completer.complete(event);
        }
        unawaited(subscription.cancel());
      },
      where: where,
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        unawaited(subscription.cancel());
      },
    );

    if (timeout != null) {
      return completer.future.timeout(
        timeout,
        onTimeout: () {
          unawaited(subscription.cancel());
          throw TimeoutException(
            'Timed out waiting for event of type $T.',
            timeout,
          );
        },
      );
    }

    return completer.future;
  }

  /// Broadcasts [event] to all matching subscribers.
  ///
  /// Throws [GameStateException] if the bus has already been disposed, or
  /// [GameEventLoopException] if the listener cascade depth exceeds
  /// [maxCascadeDepth].
  void emit(GameEvent event) {
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot emit events after GameEventBus has been disposed.',
      );
    }
    final currentDepth = Zone.current[_depthZoneKey] as int? ?? 0;
    if (currentDepth >= maxCascadeDepth) {
      throw GameEventLoopException(
        'Maximum event cascade depth ($maxCascadeDepth) exceeded while '
        'emitting ${event.runtimeType}. Check for cyclic event listeners.',
      );
    }
    _controller.add(_EventEnvelope(event, currentDepth + 1));
  }

  /// Attempts to emit [event], returning `false` if disposed or if an event
  /// loop limit would be exceeded.
  bool tryEmit(GameEvent event) {
    if (_isDisposed) {
      return false;
    }
    final currentDepth = Zone.current[_depthZoneKey] as int? ?? 0;
    if (currentDepth >= maxCascadeDepth) {
      onError?.call(
        GameEventLoopException(
          'Maximum event cascade depth ($maxCascadeDepth) exceeded while '
          'emitting ${event.runtimeType}.',
        ),
        StackTrace.current,
      );
      return false;
    }
    _controller.add(_EventEnvelope(event, currentDepth + 1));
    return true;
  }

  /// Cancels all tracked subscriptions and closes the underlying stream.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    final subscriptions = List<StreamSubscription<Object?>>.of(
      _managedSubscriptions,
    );
    _managedSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await _controller.close();
  }
}

class _TypedEventSubscription<T extends GameEvent>
    implements StreamSubscription<T> {
  _TypedEventSubscription(this._inner, this._onCancel);

  final StreamSubscription<_EventEnvelope> _inner;
  final void Function() _onCancel;

  @override
  Future<void> cancel() {
    _onCancel();
    return _inner.cancel();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture<E>(futureValue);

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void onData(void Function(T data)? handleData) {
    if (handleData == null) {
      _inner.onData(null);
      return;
    }
    _inner.onData((envelope) {
      final event = envelope.event;
      if (event is T) {
        handleData(event);
      }
    });
  }

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();
}
