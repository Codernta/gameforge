import 'dart:convert';

import '../core/game_exception.dart';

/// Strict serialization and type-safe deserialization utilities for GameForge
/// persistence payloads.
abstract final class GameSerialization {
  /// Encodes [data] as a JSON string, throwing [PersistenceException] if
  /// [data] contains non-encodable objects.
  static String encodeJson(Map<String, Object?> data) {
    try {
      return jsonEncode(data);
    } catch (error, stackTrace) {
      throw PersistenceException(
        'Failed to encode save payload to JSON.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Decodes a JSON object string into a `Map<String, Object?>`, throwing
  /// [CorruptSaveDataException] on malformed JSON or non-object roots.
  static Map<String, Object?> decodeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const CorruptSaveDataException(
          'Expected top-level JSON object for save data.',
        );
      }
      return normalizeMap(decoded);
    } on CorruptSaveDataException {
      rethrow;
    } catch (error, stackTrace) {
      throw CorruptSaveDataException(
        'Save payload contains malformed JSON.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Recursively copies and normalizes maps/lists into safe JSON-compatible
  /// `Map<String, Object?>` and `List<Object?>` structures.
  static Map<String, Object?> normalizeMap(Map<Object?, Object?> source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) {
        throw CorruptSaveDataException(
          'Expected string key in save map, found ${key.runtimeType}.',
        );
      }
      result[key] = _normalizeValue(entry.value);
    }
    return result;
  }

  static Object? _normalizeValue(Object? value) {
    if (value == null || value is bool || value is num || value is String) {
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Duration) {
      return value.inMicroseconds;
    }
    if (value is Map<Object?, Object?>) {
      return normalizeMap(value);
    }
    if (value is List<Object?>) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    if (value is Iterable<Object?>) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    throw CorruptSaveDataException(
      'Unsupported value type in save data: ${value.runtimeType}.',
    );
  }

  /// Computes a deterministic cross-platform integrity checksum over canonical
  /// JSON representation of [data] (ignoring any `'checksum'` key).
  static String computeChecksum(Map<String, Object?> data) {
    final canonical = _canonicalizeWithoutChecksum(data);
    final encoded = jsonEncode(canonical);
    final units = utf8.encode(encoded);

    // Paired 32-bit FNV-1a and DJB2 digests using 32-bit masking so output is
    // identical across Dart VM, JS, and Wasm targets.
    var fnv = 0x811c9dc5;
    var djb = 5381;
    for (final byte in units) {
      fnv ^= byte;
      fnv = (fnv * 0x01000193) & 0xFFFFFFFF;
      djb = (((djb << 5) + djb) ^ byte) & 0xFFFFFFFF;
    }
    final fnvHex = fnv.toRadixString(16).padLeft(8, '0');
    final djbHex = djb.toRadixString(16).padLeft(8, '0');
    return '$fnvHex$djbHex';
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map<Object?, Object?>) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final ordered = <String, Object?>{};
      for (final key in sortedKeys) {
        ordered[key] = _canonicalize(value[key]);
      }
      return ordered;
    }
    if (value is List<Object?>) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  static Map<String, Object?> _canonicalizeWithoutChecksum(
    Map<String, Object?> data,
  ) {
    final copy = Map<String, Object?>.of(data)..remove('checksum');
    return _canonicalize(copy)! as Map<String, Object?>;
  }

  /// Reads an integer field [key] from [map], or returns [defaultValue] if
  /// absent and provided.
  static int readInt(
    Map<String, Object?> map,
    String key, {
    int? defaultValue,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required integer field "$key".');
    }
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num && value == value.truncateToDouble()) {
      return value.toInt();
    }
    throw CorruptSaveDataException(
      'Expected integer for "$key", got ${value.runtimeType}.',
    );
  }

  /// Reads a double field [key] from [map], or returns [defaultValue] if
  /// absent and provided.
  static double readDouble(
    Map<String, Object?> map,
    String key, {
    double? defaultValue,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required double field "$key".');
    }
    final value = map[key];
    if (value is num) {
      final result = value.toDouble();
      if (!result.isFinite) {
        throw CorruptSaveDataException('Non-finite double value for "$key".');
      }
      return result;
    }
    throw CorruptSaveDataException(
      'Expected number for "$key", got ${value.runtimeType}.',
    );
  }

  /// Reads a boolean field [key] from [map].
  static bool readBool(
    Map<String, Object?> map,
    String key, {
    bool? defaultValue,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required boolean field "$key".');
    }
    final value = map[key];
    if (value is bool) {
      return value;
    }
    throw CorruptSaveDataException(
      'Expected boolean for "$key", got ${value.runtimeType}.',
    );
  }

  /// Reads a string field [key] from [map].
  static String readString(
    Map<String, Object?> map,
    String key, {
    String? defaultValue,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required string field "$key".');
    }
    final value = map[key];
    if (value is String) {
      return value;
    }
    throw CorruptSaveDataException(
      'Expected string for "$key", got ${value.runtimeType}.',
    );
  }

  /// Reads an optional string field [key] from [map].
  static String? readOptionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw CorruptSaveDataException(
      'Expected string or null for "$key", got ${value.runtimeType}.',
    );
  }

  /// Reads an ISO-8601 [DateTime] field [key] from [map].
  static DateTime readDateTime(
    Map<String, Object?> map,
    String key, {
    DateTime? defaultValue,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required DateTime field "$key".');
    }
    final value = map[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw CorruptSaveDataException(
      'Invalid ISO-8601 DateTime value for "$key": $value.',
    );
  }

  /// Reads a nested map field [key] from [map].
  static Map<String, Object?> readMap(
    Map<String, Object?> map,
    String key, {
    Map<String, Object?>? defaultValue,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required map field "$key".');
    }
    final value = map[key];
    if (value is Map<Object?, Object?>) {
      return normalizeMap(value);
    }
    throw CorruptSaveDataException(
      'Expected map for "$key", got ${value.runtimeType}.',
    );
  }

  /// Reads a list field [key] from [map].
  static List<Object?> readList(
    Map<String, Object?> map,
    String key, {
    List<Object?>? defaultValue,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required list field "$key".');
    }
    final value = map[key];
    if (value is List<Object?>) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    throw CorruptSaveDataException(
      'Expected list for "$key", got ${value.runtimeType}.',
    );
  }
}
