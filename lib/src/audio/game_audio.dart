import 'dart:async';

import '../core/game_exception.dart';
import '../utils/validators.dart';
import 'audio_settings.dart';

/// Engine-independent audio service interface for background music, sound
/// effects, volume controls, muting, and lifecycle hooks.
abstract interface class GameAudioService {
  /// Current [AudioSettings].
  AudioSettings get settings;

  /// Stream emitting whenever [settings] change.
  Stream<AudioSettings> get settingsStream;

  /// Initializes the audio backend.
  Future<void> initialize();

  /// Preloads sound assets identified by [assetIds].
  Future<void> preload(List<String> assetIds);

  /// Plays a background music track identified by [trackId].
  Future<void> playMusic(String trackId, {bool loop = true, double? volume});

  /// Stops active background music playback.
  Future<void> stopMusic();

  /// Pauses active background music playback.
  Future<void> pauseMusic();

  /// Resumes previously paused background music playback.
  Future<void> resumeMusic();

  /// Plays a one-shot sound effect identified by [soundId].
  Future<void> playSfx(String soundId, {double? volume});

  /// Updates master volume (`0.0` to `1.0`).
  Future<void> setMasterVolume(double volume);

  /// Updates music volume (`0.0` to `1.0`).
  Future<void> setMusicVolume(double volume);

  /// Updates sound effect volume (`0.0` to `1.0`).
  Future<void> setSfxVolume(double volume);

  /// Mutes all audio output.
  Future<void> mute();

  /// Unmutes global audio output.
  Future<void> unmute();

  /// Toggles global mute state.
  Future<void> toggleMute();

  /// Enables or disables music-only mute.
  Future<void> setMusicMuted(bool muted);

  /// Enables or disables SFX-only mute.
  Future<void> setSfxMuted(bool muted);

  /// Applies a complete [AudioSettings] snapshot.
  Future<void> applySettings(AudioSettings settings);

  /// Releases audio backend resources.
  Future<void> dispose();
}

/// Default no-op [GameAudioService] used when audio playback is not attached
/// (e.g., pure Dart tests or headless simulations).
class NoopGameAudioService implements GameAudioService {
  /// Creates a [NoopGameAudioService].
  NoopGameAudioService({AudioSettings initialSettings = const AudioSettings()})
    : _settings = initialSettings {
    _settings.validate();
  }

  final StreamController<AudioSettings> _settingsController =
      StreamController<AudioSettings>.broadcast();

  AudioSettings _settings;
  bool _isDisposed = false;

  @override
  AudioSettings get settings => _settings;

  @override
  Stream<AudioSettings> get settingsStream => _settingsController.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> preload(List<String> assetIds) async {
    for (final id in assetIds) {
      Validators.requireSafeAssetId(id, 'assetId');
    }
  }

  @override
  Future<void> playMusic(
    String trackId, {
    bool loop = true,
    double? volume,
  }) async {
    Validators.requireSafeAssetId(trackId, 'trackId');
    if (volume != null) {
      _validateVolume(volume);
    }
  }

  @override
  Future<void> stopMusic() async {}

  @override
  Future<void> pauseMusic() async {}

  @override
  Future<void> resumeMusic() async {}

  @override
  Future<void> playSfx(String soundId, {double? volume}) async {
    Validators.requireSafeAssetId(soundId, 'soundId');
    if (volume != null) {
      _validateVolume(volume);
    }
  }

  @override
  Future<void> setMasterVolume(double volume) =>
      applySettings(_settings.copyWith(masterVolume: _validateVolume(volume)));

  @override
  Future<void> setMusicVolume(double volume) =>
      applySettings(_settings.copyWith(musicVolume: _validateVolume(volume)));

  @override
  Future<void> setSfxVolume(double volume) =>
      applySettings(_settings.copyWith(sfxVolume: _validateVolume(volume)));

  @override
  Future<void> mute() => applySettings(_settings.copyWith(isMuted: true));

  @override
  Future<void> unmute() => applySettings(_settings.copyWith(isMuted: false));

  @override
  Future<void> toggleMute() =>
      applySettings(_settings.copyWith(isMuted: !_settings.isMuted));

  @override
  Future<void> setMusicMuted(bool muted) =>
      applySettings(_settings.copyWith(isMusicMuted: muted));

  @override
  Future<void> setSfxMuted(bool muted) =>
      applySettings(_settings.copyWith(isSfxMuted: muted));

  @override
  Future<void> applySettings(AudioSettings settings) async {
    settings.validate();
    if (_isDisposed) {
      return;
    }
    _settings = settings;
    if (!_settingsController.isClosed) {
      _settingsController.add(_settings);
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _settingsController.close();
  }

  static double _validateVolume(double volume) {
    if (!volume.isFinite || volume < 0.0 || volume > 1.0) {
      throw GameConfigurationException(
        'Audio volume must be within [0.0, 1.0] (got $volume).',
      );
    }
    return volume;
  }
}

/// Recorded audio action captured by [RecordingGameAudioService] for tests.
class RecordedAudioCall {
  /// Creates a [RecordedAudioCall].
  const RecordedAudioCall({
    required this.action,
    this.assetId,
    this.loop,
    this.volume,
  });

  /// Method/action name invoked (e.g., `'playMusic'`, `'playSfx'`).
  final String action;

  /// Track or sound identifier, if applicable.
  final String? assetId;

  /// Loop flag for music calls, if applicable.
  final bool? loop;

  /// Effective or explicit volume, if applicable.
  final double? volume;
}

/// Deterministic in-memory [GameAudioService] recording all music/SFX calls
/// and lifecycle transitions for unit tests and headless games.
class RecordingGameAudioService extends NoopGameAudioService {
  /// Creates a [RecordingGameAudioService].
  RecordingGameAudioService({super.initialSettings});

  final List<RecordedAudioCall> _calls = [];
  final List<String> _preloaded = [];

  bool _isInitialized = false;
  bool _isMusicPlaying = false;
  bool _isMusicPaused = false;
  String? _currentMusicTrack;

  /// Ordered log of recorded audio invocations.
  List<RecordedAudioCall> get calls =>
      List<RecordedAudioCall>.unmodifiable(_calls);

  /// Preloaded asset IDs.
  List<String> get preloadedAssets => List<String>.unmodifiable(_preloaded);

  /// Whether [initialize] has been called.
  bool get isInitialized => _isInitialized;

  /// Whether music is currently active (not stopped or paused).
  bool get isMusicPlaying => _isMusicPlaying && !_isMusicPaused;

  /// Whether music is currently paused.
  bool get isMusicPaused => _isMusicPaused;

  /// Track ID of currently loaded background music, or `null`.
  String? get currentMusicTrack => _currentMusicTrack;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
    _calls.add(const RecordedAudioCall(action: 'initialize'));
  }

  @override
  Future<void> preload(List<String> assetIds) async {
    for (final id in assetIds) {
      Validators.requireSafeAssetId(id, 'assetId');
    }
    _preloaded.addAll(assetIds);
    for (final id in assetIds) {
      _calls.add(RecordedAudioCall(action: 'preload', assetId: id));
    }
  }

  @override
  Future<void> playMusic(
    String trackId, {
    bool loop = true,
    double? volume,
  }) async {
    Validators.requireSafeAssetId(trackId, 'trackId');
    if (volume != null) {
      NoopGameAudioService._validateVolume(volume);
    }
    _currentMusicTrack = trackId;
    _isMusicPlaying = true;
    _isMusicPaused = false;
    _calls.add(
      RecordedAudioCall(
        action: 'playMusic',
        assetId: trackId,
        loop: loop,
        volume: volume ?? settings.effectiveMusicVolume,
      ),
    );
  }

  @override
  Future<void> stopMusic() async {
    _isMusicPlaying = false;
    _isMusicPaused = false;
    _currentMusicTrack = null;
    _calls.add(const RecordedAudioCall(action: 'stopMusic'));
  }

  @override
  Future<void> pauseMusic() async {
    if (_isMusicPlaying) {
      _isMusicPaused = true;
    }
    _calls.add(const RecordedAudioCall(action: 'pauseMusic'));
  }

  @override
  Future<void> resumeMusic() async {
    if (_isMusicPlaying && _isMusicPaused) {
      _isMusicPaused = false;
    }
    _calls.add(const RecordedAudioCall(action: 'resumeMusic'));
  }

  @override
  Future<void> playSfx(String soundId, {double? volume}) async {
    Validators.requireSafeAssetId(soundId, 'soundId');
    if (volume != null) {
      NoopGameAudioService._validateVolume(volume);
    }
    _calls.add(
      RecordedAudioCall(
        action: 'playSfx',
        assetId: soundId,
        volume: volume ?? settings.effectiveSfxVolume,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _calls.add(const RecordedAudioCall(action: 'dispose'));
    await super.dispose();
  }
}
