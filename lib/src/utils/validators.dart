import '../core/game_exception.dart';

/// Shared validation helpers for GameForge inputs and configuration values.
abstract final class Validators {
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
}
