import '../core/game_exception.dart';
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
  }) {
    for (final entry in initialEntries.entries) {
      _store[entry.key] = GameSerialization.normalizeMap(entry.value);
    }
  }

  final Map<String, Map<String, Object?>> _store = {};

  /// Snapshot of currently stored keys.
  List<String> get keys => List<String>.unmodifiable(_store.keys);

  /// Returns `true` if [key] currently exists in memory.
  bool containsKey(String key) => _store.containsKey(key);

  @override
  Future<void> save(String key, Map<String, Object?> data) async {
    if (key.trim().isEmpty) {
      throw const PersistenceException('Storage key cannot be empty.');
    }
    // Validate and copy completely before replacing the stored slot (atomic).
    final copy = GameSerialization.normalizeMap(data);
    _store[key] = copy;
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final existing = _store[key];
    if (existing == null) {
      return null;
    }
    return GameSerialization.normalizeMap(existing);
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}
