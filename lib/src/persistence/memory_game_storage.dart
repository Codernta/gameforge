import '../core/game_exception.dart';
import '../utils/validators.dart';
import 'game_storage.dart';
import 'serialization.dart';

/// In-memory [GameStorage] implementation suitable for tests, prototypes, and
/// ephemeral sessions.
///
/// All saved and read maps are deep-copied through [GameSerialization] so
/// caller mutations never corrupt stored snapshots.
class MemoryGameStorage implements GameStorage {
  /// Creates a [MemoryGameStorage], optionally seeded with [initialEntries].
  MemoryGameStorage({
    Map<String, Map<String, Object?>> initialEntries = const {},
    this.maxNestingDepth = GameSerialization.defaultMaxNestingDepth,
  }) {
    Validators.requirePositive(maxNestingDepth, 'maxNestingDepth');
    for (final entry in initialEntries.entries) {
      final safeKey = _validateKey(entry.key);
      _store[safeKey] = GameSerialization.normalizeMap(
        entry.value,
        maxDepth: maxNestingDepth,
      );
    }
  }

  /// Maximum allowed container nesting depth for stored payloads.
  final int maxNestingDepth;

  final Map<String, Map<String, Object?>> _store = {};

  /// Snapshot of currently stored keys.
  List<String> get keys => List<String>.unmodifiable(_store.keys);

  /// Returns `true` if [key] currently exists in memory.
  bool containsKey(String key) => _store.containsKey(key);

  String _validateKey(String key) => Validators.requireSafeKey(
    key,
    'Storage key',
    exceptionBuilder: (message) => PersistenceException(message),
  );

  @override
  Future<void> save(String key, Map<String, Object?> data) async {
    final safeKey = _validateKey(key);
    // Validate and copy completely before replacing the stored slot (atomic).
    final copy = GameSerialization.normalizeMap(
      data,
      maxDepth: maxNestingDepth,
    );
    _store[safeKey] = copy;
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final safeKey = _validateKey(key);
    final existing = _store[safeKey];
    if (existing == null) {
      return null;
    }
    return GameSerialization.normalizeMap(existing, maxDepth: maxNestingDepth);
  }

  @override
  Future<void> delete(String key) async {
    final safeKey = _validateKey(key);
    _store.remove(safeKey);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}
