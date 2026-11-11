import 'dart:math';

/// Generates unique identifiers for sessions, rewards, timers, and entities.
abstract interface class IdGenerator {
  /// Generates the next identifier, optionally prefixed with [prefix].
  String nextId([String? prefix]);
}

/// Deterministic sequential [IdGenerator] ideal for testing and replayable logs.
class SequentialIdGenerator implements IdGenerator {
  /// Creates a [SequentialIdGenerator] starting at [initialValue].
  SequentialIdGenerator({int initialValue = 0}) : _counter = initialValue;

  int _counter;

  /// Current counter value.
  int get currentCount => _counter;

  @override
  String nextId([String? prefix]) {
    _counter += 1;
    if (prefix == null || prefix.isEmpty) {
      return '$_counter';
    }
    return '${prefix}_$_counter';
  }

  /// Resets the internal counter back to [value].
  void reset({int value = 0}) {
    _counter = value;
  }
}

/// Cryptographically backed random [IdGenerator] using `dart:math`.
class RandomIdGenerator implements IdGenerator {
  /// Creates a [RandomIdGenerator].
  RandomIdGenerator({Random? random}) : _random = random ?? _createRandom();

  final Random _random;
  int _sequence = 0;

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  @override
  String nextId([String? prefix]) {
    _sequence = (_sequence + 1) & 0xFFFF;
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final partA = _random.nextInt(0x10000000).toRadixString(16).padLeft(7, '0');
    final partB = _random.nextInt(0x10000000).toRadixString(16).padLeft(7, '0');
    final seqHex = _sequence.toRadixString(16).padLeft(4, '0');
    final id = '$timestamp-$seqHex-$partA$partB';
    if (prefix == null || prefix.isEmpty) {
      return id;
    }
    return '${prefix}_$id';
  }
}
