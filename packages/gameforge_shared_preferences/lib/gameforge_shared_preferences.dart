/// Optional SharedPreferences persistence backend for GameForge.
library;

import 'package:gameforge/gameforge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [GameStorage] implementation backed by `shared_preferences`.
///
/// Keys are automatically namespaced with [keyPrefix] so [clear] only removes
/// GameForge entries without deleting unrelated app preferences.
class SharedPreferencesGameStorage implements GameStorage {
  /// Creates a [SharedPreferencesGameStorage].
  SharedPreferencesGameStorage({
    SharedPreferences? preferences,
    this.keyPrefix = 'gameforge:',
  }) : _preferences = preferences;

  final SharedPreferences? _preferences;

  /// Prefix applied to all stored preference keys.
  final String keyPrefix;

  Future<SharedPreferences> _resolvePrefs() async =>
      _preferences ?? await SharedPreferences.getInstance();

  String _scopedKey(String key) {
    if (key.trim().isEmpty) {
      throw const PersistenceException('Storage key cannot be empty.');
    }
    return '$keyPrefix$key';
  }

  @override
  Future<void> save(String key, Map<String, Object?> data) async {
    final scoped = _scopedKey(key);
    final encoded = GameSerialization.encodeJson(data);
    final prefs = await _resolvePrefs();
    final ok = await prefs.setString(scoped, encoded);
    if (!ok) {
      throw PersistenceException(
        'SharedPreferences failed to persist key "$key".',
      );
    }
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final scoped = _scopedKey(key);
    final prefs = await _resolvePrefs();
    final raw = prefs.getString(scoped);
    if (raw == null) {
      return null;
    }
    return GameSerialization.decodeJson(raw);
  }

  @override
  Future<void> delete(String key) async {
    final scoped = _scopedKey(key);
    final prefs = await _resolvePrefs();
    await prefs.remove(scoped);
  }

  @override
  Future<void> clear() async {
    final prefs = await _resolvePrefs();
    final keysToRemove = prefs
        .getKeys()
        .where((key) => key.startsWith(keyPrefix))
        .toList(growable: false);
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }
}
