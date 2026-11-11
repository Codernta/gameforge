import 'package:gameforge/gameforge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists GameForge snapshots locally via `shared_preferences`.
class LocalPrefsGameStorage implements GameStorage {
  LocalPrefsGameStorage({this.prefix = 'coin_rush:'});

  final String prefix;

  @override
  Future<void> save(String key, Map<String, Object?> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$prefix$key', GameSerialization.encodeJson(data));
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$prefix$key');
    if (raw == null) return null;
    return GameSerialization.decodeJson(raw);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$prefix$key');
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await prefs.remove(key);
    }
  }
}
