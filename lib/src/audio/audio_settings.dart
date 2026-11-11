import 'package:meta/meta.dart';

import '../core/game_exception.dart';
import '../persistence/serialization.dart';

/// Immutable audio volume and mute settings.
@immutable
class AudioSettings {
  /// Creates an [AudioSettings] instance.
  const AudioSettings({
    this.masterVolume = 1.0,
    this.musicVolume = 1.0,
    this.sfxVolume = 1.0,
    this.isMuted = false,
    this.isMusicMuted = false,
    this.isSfxMuted = false,
  }) : assert(masterVolume >= 0.0 && masterVolume <= 1.0),
       assert(musicVolume >= 0.0 && musicVolume <= 1.0),
       assert(sfxVolume >= 0.0 && sfxVolume <= 1.0);

  /// Restores [AudioSettings] from JSON data.
  factory AudioSettings.fromJson(Map<String, Object?> json) {
    final master = GameSerialization.readDouble(
      json,
      'masterVolume',
      defaultValue: 1.0,
    );
    final music = GameSerialization.readDouble(
      json,
      'musicVolume',
      defaultValue: 1.0,
    );
    final sfx = GameSerialization.readDouble(
      json,
      'sfxVolume',
      defaultValue: 1.0,
    );
    for (final entry in {
      'masterVolume': master,
      'musicVolume': music,
      'sfxVolume': sfx,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0.0 || entry.value > 1.0) {
        throw SaveValidationException(
          'Saved ${entry.key} (${entry.value}) must be within [0.0, 1.0].',
        );
      }
    }

    return AudioSettings(
      masterVolume: master,
      musicVolume: music,
      sfxVolume: sfx,
      isMuted: GameSerialization.readBool(json, 'isMuted', defaultValue: false),
      isMusicMuted: GameSerialization.readBool(
        json,
        'isMusicMuted',
        defaultValue: false,
      ),
      isSfxMuted: GameSerialization.readBool(
        json,
        'isSfxMuted',
        defaultValue: false,
      ),
    );
  }

  /// Master volume multiplier in `[0.0, 1.0]`.
  final double masterVolume;

  /// Background music volume multiplier in `[0.0, 1.0]`.
  final double musicVolume;

  /// Sound effects volume multiplier in `[0.0, 1.0]`.
  final double sfxVolume;

  /// Global mute toggle silencing both music and SFX.
  final bool isMuted;

  /// Music-only mute toggle.
  final bool isMusicMuted;

  /// Sound-effects-only mute toggle.
  final bool isSfxMuted;

  /// Computed effective music playback volume (`0.0` when muted).
  double get effectiveMusicVolume =>
      (isMuted || isMusicMuted) ? 0.0 : masterVolume * musicVolume;

  /// Computed effective SFX playback volume (`0.0` when muted).
  double get effectiveSfxVolume =>
      (isMuted || isSfxMuted) ? 0.0 : masterVolume * sfxVolume;

  /// Validates that all volume sliders lie in `[0.0, 1.0]`.
  void validate() {
    for (final entry in {
      'masterVolume': masterVolume,
      'musicVolume': musicVolume,
      'sfxVolume': sfxVolume,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0.0 || entry.value > 1.0) {
        throw GameConfigurationException(
          'AudioSettings.${entry.key} (${entry.value}) must be in [0.0, 1.0].',
        );
      }
    }
  }

  /// Returns a modified copy of these settings.
  AudioSettings copyWith({
    double? masterVolume,
    double? musicVolume,
    double? sfxVolume,
    bool? isMuted,
    bool? isMusicMuted,
    bool? isSfxMuted,
  }) {
    return AudioSettings(
      masterVolume: masterVolume ?? this.masterVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      isMuted: isMuted ?? this.isMuted,
      isMusicMuted: isMusicMuted ?? this.isMusicMuted,
      isSfxMuted: isSfxMuted ?? this.isSfxMuted,
    );
  }

  /// Serializes these settings into JSON-compatible data.
  Map<String, Object?> toJson() => {
    'masterVolume': masterVolume,
    'musicVolume': musicVolume,
    'sfxVolume': sfxVolume,
    'isMuted': isMuted,
    'isMusicMuted': isMusicMuted,
    'isSfxMuted': isSfxMuted,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioSettings &&
        other.masterVolume == masterVolume &&
        other.musicVolume == musicVolume &&
        other.sfxVolume == sfxVolume &&
        other.isMuted == isMuted &&
        other.isMusicMuted == isMusicMuted &&
        other.isSfxMuted == isSfxMuted;
  }

  @override
  int get hashCode => Object.hash(
    masterVolume,
    musicVolume,
    sfxVolume,
    isMuted,
    isMusicMuted,
    isSfxMuted,
  );
}
