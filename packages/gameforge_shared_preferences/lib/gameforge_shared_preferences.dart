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
    this.maxSaveBytes = GameSerialization.defaultMaxJsonBytes,
    this.maxNestingDepth = GameSerialization.defaultMaxNestingDepth,
  }) : _preferences = preferences {
    Validators.requireSafeId(
      keyPrefix,
      'keyPrefix',
      exceptionBuilder: (message) => PersistenceException(message),
    );
    if (keyPrefix.startsWith('.') ||
        keyPrefix.contains('..') ||
        keyPrefix.contains('/') ||
        keyPrefix.contains(r'\')) {
      throw const PersistenceException(
        'keyPrefix contains unsafe path or traversal characters.',
      );
    }
    Validators.requirePositive(maxSaveBytes, 'maxSaveBytes');
    Validators.requirePositive(maxNestingDepth, 'maxNestingDepth');
  }

  final SharedPreferences? _preferences;

  /// Prefix applied to all stored preference keys.
  final String keyPrefix;

  /// Maximum allowed serialized JSON save size in UTF-8 bytes.
  final int maxSaveBytes;

  /// Maximum allowed container nesting depth in save payloads.
  final int maxNestingDepth;

  Future<SharedPreferences> _resolvePrefs() async =>
      _preferences ?? await SharedPreferences.getInstance();

  String _scopedKey(String key) {
    final safeKey = Validators.requireSafeKey(
      key,
      'Storage key',
      exceptionBuilder: (message) => PersistenceException(message),
    );
    return '$keyPrefix$safeKey';
  }

  @override
  Future<void> save(String key, Map<String, Object?> data) async {
    final scoped = _scopedKey(key);
    final encoded = GameSerialization.encodeJson(
      data,
      maxBytes: maxSaveBytes,
      maxDepth: maxNestingDepth,
    );
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
    return GameSerialization.decodeJson(
      raw,
      maxBytes: maxSaveBytes,
      maxDepth: maxNestingDepth,
    );
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
