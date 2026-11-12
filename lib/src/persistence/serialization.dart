import 'dart:convert';

import '../core/game_exception.dart';
import '../utils/security.dart';
import '../utils/validators.dart';

/// Strict serialization and type-safe deserialization utilities for GameForge
/// persistence payloads.
abstract final class GameSerialization {
  /// Default maximum allowed JSON save payload size in UTF-8 bytes (5 MiB).
  static const int defaultMaxJsonBytes = 5 * 1024 * 1024;

  /// Default maximum allowed container nesting depth in save payloads.
  static const int defaultMaxNestingDepth = 64;

  /// Encodes [data] as a JSON string, throwing [PersistenceException] if
  /// [data] contains cycles, non-finite floats, exceeds [maxDepth] or
  /// [maxBytes], or contains non-encodable objects.
  static String encodeJson(
    Map<String, Object?> data, {
    int maxBytes = defaultMaxJsonBytes,
    int maxDepth = defaultMaxNestingDepth,
  }) {
    Validators.requirePositive(maxBytes, 'maxBytes');
    Validators.requirePositive(maxDepth, 'maxDepth');
    try {
      final normalized = normalizeMap(data, maxDepth: maxDepth);
      final encoded = jsonEncode(normalized);
      if (!_fitsUtf8ByteLimit(encoded, maxBytes)) {
        throw PersistenceException(
          'Encoded save payload exceeds maximum allowed size of '
          '$maxBytes bytes.',
        );
      }
      return encoded;
    } on PersistenceException {
      rethrow;
    } catch (error, stackTrace) {
      throw PersistenceException(
        'Failed to encode save payload to JSON.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Decodes a JSON object string into a `Map<String, Object?>`, throwing
  /// [CorruptSaveDataException] on oversized payloads, excessive nesting,
  /// malformed JSON, or non-object roots.
  static Map<String, Object?> decodeJson(
    String raw, {
    int maxBytes = defaultMaxJsonBytes,
    int maxDepth = defaultMaxNestingDepth,
  }) {
    Validators.requirePositive(maxBytes, 'maxBytes');
    Validators.requirePositive(maxDepth, 'maxDepth');

    if (!_fitsUtf8ByteLimit(raw, maxBytes)) {
      throw CorruptSaveDataException(
        'Save payload exceeds maximum allowed size of $maxBytes bytes.',
      );
    }
    _validateJsonNestingDepth(raw, maxDepth);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const CorruptSaveDataException(
          'Expected top-level JSON object for save data.',
        );
      }
      return normalizeMap(decoded, maxDepth: maxDepth);
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
  static Map<String, Object?> normalizeMap(
    Map<Object?, Object?> source, {
    int maxDepth = defaultMaxNestingDepth,
  }) {
    Validators.requirePositive(maxDepth, 'maxDepth');
    return _normalizeMapInternal(
      source,
      depth: 1,
      maxDepth: maxDepth,
      seen: Set<Object>.identity(),
    );
  }

  static Map<String, Object?> _normalizeMapInternal(
    Map<Object?, Object?> source, {
    required int depth,
    required int maxDepth,
    required Set<Object> seen,
  }) {
    if (depth > maxDepth) {
      throw CorruptSaveDataException(
        'Save payload exceeds maximum nesting depth of $maxDepth.',
      );
    }
    if (!seen.add(source)) {
      throw const CorruptSaveDataException(
        'Cyclic reference detected in save payload.',
      );
    }
    try {
      final result = <String, Object?>{};
      for (final entry in source.entries) {
        final key = entry.key;
        if (key is! String) {
          throw CorruptSaveDataException(
            'Expected string key in save map, found ${key.runtimeType}.',
          );
        }
        result[key] = _normalizeValue(
          entry.value,
          depth: depth + 1,
          maxDepth: maxDepth,
          seen: seen,
        );
      }
      return result;
    } finally {
      seen.remove(source);
    }
  }

  static Object? _normalizeValue(
    Object? value, {
    required int depth,
    required int maxDepth,
    required Set<Object> seen,
  }) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const CorruptSaveDataException(
          'Non-finite floating-point value is not allowed in save data.',
        );
      }
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Duration) {
      return value.inMicroseconds;
    }
    if (value is Map<Object?, Object?>) {
      return _normalizeMapInternal(
        value,
        depth: depth,
        maxDepth: maxDepth,
        seen: seen,
      );
    }
    if (value is Iterable<Object?>) {
      if (depth > maxDepth) {
        throw CorruptSaveDataException(
          'Save payload exceeds maximum nesting depth of $maxDepth.',
        );
      }
      if (!seen.add(value)) {
        throw const CorruptSaveDataException(
          'Cyclic reference detected in save payload.',
        );
      }
      try {
        return value
            .map(
              (item) => _normalizeValue(
                item,
                depth: depth + 1,
                maxDepth: maxDepth,
                seen: seen,
              ),
            )
            .toList(growable: false);
      } finally {
        seen.remove(value);
      }
    }
    throw CorruptSaveDataException(
      'Unsupported value type in save data: ${value.runtimeType}.',
    );
  }

  /// Computes a deterministic cross-platform integrity digest over canonical
  /// JSON representation of [data] (ignoring any `'checksum'` key).
  ///
  /// Uses SHA-256 by default, or HMAC-SHA256 when [secretKey] is provided.
  /// Throws [GameConfigurationException] if [secretKey] is empty.
  static String computeChecksum(
    Map<String, Object?> data, {
    List<int>? secretKey,
    int maxDepth = defaultMaxNestingDepth,
  }) {
    if (secretKey != null && secretKey.isEmpty) {
      throw const GameConfigurationException(
        'Save signing key must not be empty.',
      );
    }
    Validators.requirePositive(maxDepth, 'maxDepth');
    final canonical = _canonicalizeWithoutChecksum(data, maxDepth: maxDepth);
    final encoded = jsonEncode(canonical);
    final units = utf8.encode(encoded);
    if (secretKey != null) {
      return GameSecurity.hmacSha256Hex(key: secretKey, data: units);
    }
    return GameSecurity.sha256Hex(units);
  }

  /// Verifies [expectedChecksum] against [data] using constant-time
  /// hexadecimal comparison.
  static bool verifyChecksum(
    Map<String, Object?> data,
    String expectedChecksum, {
    List<int>? secretKey,
    int maxDepth = defaultMaxNestingDepth,
  }) {
    final computed = computeChecksum(
      data,
      secretKey: secretKey,
      maxDepth: maxDepth,
    );
    return GameSecurity.constantTimeHexEquals(expectedChecksum, computed);
  }

  static Object? _canonicalize(
    Object? value, {
    required int depth,
    required int maxDepth,
    required Set<Object> seen,
  }) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const CorruptSaveDataException(
          'Non-finite floating-point value is not allowed in save data.',
        );
      }
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Duration) {
      return value.inMicroseconds;
    }
    if (value is Map<Object?, Object?>) {
      if (depth > maxDepth) {
        throw CorruptSaveDataException(
          'Save payload exceeds maximum nesting depth of $maxDepth.',
        );
      }
      if (!seen.add(value)) {
        throw const CorruptSaveDataException(
          'Cyclic reference detected in save payload.',
        );
      }
      try {
        final sortedKeys = <String>[];
        for (final key in value.keys) {
          if (key is! String) {
            throw CorruptSaveDataException(
              'Expected string key in save map, found ${key.runtimeType}.',
            );
          }
          sortedKeys.add(key);
        }
        sortedKeys.sort();
        final ordered = <String, Object?>{};
        for (final key in sortedKeys) {
          ordered[key] = _canonicalize(
            value[key],
            depth: depth + 1,
            maxDepth: maxDepth,
            seen: seen,
          );
        }
        return ordered;
      } finally {
        seen.remove(value);
      }
    }
    if (value is Iterable<Object?>) {
      if (depth > maxDepth) {
        throw CorruptSaveDataException(
          'Save payload exceeds maximum nesting depth of $maxDepth.',
        );
      }
      if (!seen.add(value)) {
        throw const CorruptSaveDataException(
          'Cyclic reference detected in save payload.',
        );
      }
      try {
        return value
            .map(
              (item) => _canonicalize(
                item,
                depth: depth + 1,
                maxDepth: maxDepth,
                seen: seen,
              ),
            )
            .toList(growable: false);
      } finally {
        seen.remove(value);
      }
    }
    throw CorruptSaveDataException(
      'Unsupported value type in save data: ${value.runtimeType}.',
    );
  }

  static Map<String, Object?> _canonicalizeWithoutChecksum(
    Map<String, Object?> data, {
    required int maxDepth,
  }) {
    final copy = Map<String, Object?>.of(data)..remove('checksum');
    return _canonicalize(
          copy,
          depth: 1,
          maxDepth: maxDepth,
          seen: Set<Object>.identity(),
        )!
        as Map<String, Object?>;
  }

  static bool _fitsUtf8ByteLimit(String value, int maxBytes) {
    if (value.length > maxBytes) {
      return false;
    }
    if (value.length * 3 <= maxBytes) {
      return true;
    }
    return utf8.encode(value).length <= maxBytes;
  }

  static void _validateJsonNestingDepth(String raw, int maxDepth) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5C) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
      } else if (code == 0x7B || code == 0x5B) {
        depth++;
        if (depth > maxDepth) {
          throw CorruptSaveDataException(
            'Save payload exceeds maximum nesting depth of $maxDepth.',
          );
        }
      } else if (code == 0x7D || code == 0x5D) {
        if (depth > 0) {
          depth--;
        }
      }
    }
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
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value.abs() <= GameSecurity.maxSafeInteger) {
      return value.toInt();
    }
    throw CorruptSaveDataException(
      'Expected safe integer for "$key", got ${value.runtimeType}.',
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
    int maxDepth = defaultMaxNestingDepth,
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw CorruptSaveDataException('Missing required list field "$key".');
    }
    final value = map[key];
    if (value is List<Object?>) {
      return _normalizeValue(
            value,
            depth: 1,
            maxDepth: maxDepth,
            seen: Set<Object>.identity(),
          )!
          as List<Object?>;
    }
    throw CorruptSaveDataException(
      'Expected list for "$key", got ${value.runtimeType}.',
    );
  }
}
