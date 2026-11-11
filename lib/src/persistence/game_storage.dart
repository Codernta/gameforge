/// Engine-independent asynchronous key-value storage abstraction for game
/// persistence.
///
/// Implementations should perform atomic writes wherever supported by the
/// underlying storage backend so partial writes never corrupt existing saves.
abstract interface class GameStorage {
  /// Persists [data] under [key], replacing any previous value.
  Future<void> save(String key, Map<String, Object?> data);

  /// Reads the JSON-compatible map stored under [key], or returns `null` if
  /// no entry exists.
  Future<Map<String, Object?>?> read(String key);

  /// Deletes the entry stored under [key], if any.
  Future<void> delete(String key);

  /// Removes all entries managed by this storage instance.
  Future<void> clear();
}
