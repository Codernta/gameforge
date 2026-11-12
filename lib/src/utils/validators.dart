import '../core/game_exception.dart';
import 'security.dart';

/// Shared validation helpers for GameForge inputs and configuration values.
abstract final class Validators {
  /// Default maximum character length for storage keys.
  static const int maxKeyLength = 128;

  /// Default maximum character length for runtime identifiers.
  static const int maxIdLength = 128;

  /// Default maximum character length for relative asset identifiers.
  static const int maxAssetIdLength = 256;

  /// Ensures [value] is non-empty after trimming.
  static String requireNonEmpty(
    String value,
    String fieldName, {
    GameException Function(String message)? exceptionBuilder,
  }) {
    if (value.trim().isEmpty) {
      final message = '$fieldName must not be empty.';
      throw exceptionBuilder?.call(message) ??
          GameConfigurationException(message);
    }
    return value;
  }

  /// Ensures [value] is a safe storage key without whitespace padding,
  /// control characters, path separators, or traversal segments.
  static String requireSafeKey(
    String value,
    String fieldName, {
    int maxLength = maxKeyLength,
    GameException Function(String message)? exceptionBuilder,
  }) {
    GameException fail(String message) =>
        exceptionBuilder?.call(message) ?? GameConfigurationException(message);

    if (value.trim().isEmpty) {
      throw fail('$fieldName must not be empty.');
    }
    if (value != value.trim()) {
      throw fail('$fieldName must not have leading or trailing whitespace.');
    }
    if (value.length > maxLength) {
      throw fail('$fieldName exceeds maximum length of $maxLength characters.');
    }
    if (_containsControlChar(value)) {
      throw fail('$fieldName contains invalid control characters.');
    }
    if (value.startsWith('.') ||
        value.contains('..') ||
        value.contains('/') ||
        value.contains(r'\')) {
      throw fail('$fieldName contains unsafe path or traversal characters.');
    }
    return value;
  }

  /// Ensures [value] is a safe identifier without whitespace padding,
  /// control characters, or excessive length.
  static String requireSafeId(
    String value,
    String fieldName, {
    int maxLength = maxIdLength,
    GameException Function(String message)? exceptionBuilder,
  }) {
    GameException fail(String message) =>
        exceptionBuilder?.call(message) ?? GameConfigurationException(message);

    if (value.trim().isEmpty) {
      throw fail('$fieldName must not be empty.');
    }
    if (value != value.trim()) {
      throw fail('$fieldName must not have leading or trailing whitespace.');
    }
    if (value.length > maxLength) {
      throw fail('$fieldName exceeds maximum length of $maxLength characters.');
    }
    if (_containsControlChar(value)) {
      throw fail('$fieldName contains invalid control characters.');
    }
    return value;
  }

  /// Ensures [value] is a safe relative asset identifier without control
  /// characters, backslashes, leading slashes, scheme prefixes, or `..`
  /// traversal segments.
  static String requireSafeAssetId(
    String value,
    String fieldName, {
    int maxLength = maxAssetIdLength,
    GameException Function(String message)? exceptionBuilder,
  }) {
    GameException fail(String message) =>
        exceptionBuilder?.call(message) ?? GameConfigurationException(message);

    requireSafeId(
      value,
      fieldName,
      maxLength: maxLength,
      exceptionBuilder: exceptionBuilder,
    );
    if (value.startsWith('/') ||
        value.contains(r'\') ||
        value.contains('..') ||
        value.contains('://')) {
      throw fail('$fieldName contains unsafe asset path characters.');
    }
    return value;
  }

  /// Ensures [value] is greater than or equal to zero.
  static T requireNonNegative<T extends num>(
    T value,
    String fieldName, {
    GameException Function(String message)? exceptionBuilder,
  }) {
    if (value.isNaN || value < 0) {
      final message = '$fieldName must be non-negative (got $value).';
      throw exceptionBuilder?.call(message) ??
          GameConfigurationException(message);
    }
    return value;
  }

  /// Ensures [value] is strictly greater than zero.
  static T requirePositive<T extends num>(
    T value,
    String fieldName, {
    GameException Function(String message)? exceptionBuilder,
  }) {
    if (value.isNaN || value <= 0) {
      final message = '$fieldName must be greater than zero (got $value).';
      throw exceptionBuilder?.call(message) ??
          GameConfigurationException(message);
    }
    return value;
  }

  /// Ensures [value] is finite (not NaN or infinite).
  static double requireFinite(
    double value,
    String fieldName, {
    GameException Function(String message)? exceptionBuilder,
  }) {
    if (!value.isFinite) {
      final message = '$fieldName must be a finite number (got $value).';
      throw exceptionBuilder?.call(message) ??
          GameConfigurationException(message);
    }
    return value;
  }

  /// Ensures [value] falls within `[min, max]`.
  static T requireInRange<T extends num>(
    T value,
    T min,
    T max,
    String fieldName, {
    GameException Function(String message)? exceptionBuilder,
  }) {
    if (value.isNaN || value < min || value > max) {
      final message = '$fieldName must be between $min and $max (got $value).';
      throw exceptionBuilder?.call(message) ??
          GameConfigurationException(message);
    }
    return value;
  }

  /// Adds [a] and [b], throwing if the sum would overflow or fall outside
  /// `[min, max]`.
  static int safeAddInt(
    int a,
    int b,
    String fieldName, {
    int min = -GameSecurity.maxSafeInteger,
    int max = GameSecurity.maxSafeInteger,
    GameException Function(String message)? exceptionBuilder,
  }) {
    if (a >= -0x3FFFFFFF &&
        a <= 0x3FFFFFFF &&
        b >= -0x3FFFFFFF &&
        b <= 0x3FFFFFFF) {
      final sum = a + b;
      if (sum >= min && sum <= max) {
        return sum;
      }
    }
    final bigSum = BigInt.from(a) + BigInt.from(b);
    if (bigSum < BigInt.from(min) || bigSum > BigInt.from(max)) {
      final message = '$fieldName must remain between $min and $max.';
      throw exceptionBuilder?.call(message) ??
          GameConfigurationException(message);
    }
    return bigSum.toInt();
  }

  /// Multiplies [a] by [factor] and rounds to an integer, throwing if [factor]
  /// is not finite or the rounded result falls outside `[min, max]`.
  static int safeMultiplyAndRound(
    int a,
    double factor,
    String fieldName, {
    int min = -GameSecurity.maxSafeInteger,
    int max = GameSecurity.maxSafeInteger,
    GameException Function(String message)? exceptionBuilder,
  }) {
    GameException fail(String message) =>
        exceptionBuilder?.call(message) ?? GameConfigurationException(message);

    if (!factor.isFinite) {
      throw fail('$fieldName multiplier must be finite (got $factor).');
    }
    final product = a * factor;
    if (!product.isFinite ||
        product < min.toDouble() - 0.5 ||
        product > max.toDouble() + 0.5) {
      throw fail('$fieldName overflows safe integer bounds.');
    }
    final rounded = product.round();
    if (rounded < min || rounded > max) {
      throw fail('$fieldName must remain between $min and $max.');
    }
    return rounded;
  }

  static bool _containsControlChar(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x20 || unit == 0x7F) {
        return true;
      }
    }
    return false;
  }
}
