/// Optional `audioplayers` adapter implementing GameForge's [GameAudioService].
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:gameforge/gameforge.dart';

/// Maps a logical track or sound identifier to an `audioplayers` [Source].
typedef AudioplayersSourceResolver = Source Function(String assetId);

/// Minimal playback port wrapping `audioplayers`' [AudioPlayer] for clean
/// dependency injection and unit testing.
abstract interface class AudioplayersPlayerPort {
  /// Configures release/loop mode.
  Future<void> setReleaseMode(ReleaseMode releaseMode);

  /// Plays [source] at [volume].
  Future<void> play(Source source, {double? volume});

  /// Updates playback [volume] (`0.0` to `1.0`).
  Future<void> setVolume(double volume);

  /// Pauses active playback.
  Future<void> pause();

  /// Resumes paused playback.
  Future<void> resume();

  /// Stops playback.
  Future<void> stop();

  /// Permanently disposes player resources.
  Future<void> dispose();
}

class _RealAudioPlayerPort implements AudioplayersPlayerPort {
  _RealAudioPlayerPort(this._player);

  final AudioPlayer _player;

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) =>
      _player.setReleaseMode(releaseMode);

  @override
  Future<void> play(Source source, {double? volume}) =>
      _player.play(source, volume: volume);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Factory creating [AudioplayersPlayerPort] instances.
typedef AudioPlayerPortFactory = AudioplayersPlayerPort Function();

/// [GameAudioService] implementation backed by the MIT-licensed `audioplayers`
/// package.
class AudioplayersGameAudioService implements GameAudioService {
  /// Creates an [AudioplayersGameAudioService].
  AudioplayersGameAudioService({
    AudioSettings initialSettings = const AudioSettings(),
    AudioplayersSourceResolver? sourceResolver,
    AudioPlayerPortFactory? playerFactory,
    this.maxConcurrentSfxPlayers = 6,
  }) : _settings = initialSettings,
       _sourceResolver = sourceResolver ?? AssetSource.new,
       _playerFactory =
           playerFactory ?? (() => _RealAudioPlayerPort(AudioPlayer())) {
    _settings.validate();
  }

  final AudioplayersSourceResolver _sourceResolver;
  final AudioPlayerPortFactory _playerFactory;

  /// Maximum reusable SFX players maintained in the pool.
  final int maxConcurrentSfxPlayers;

  final StreamController<AudioSettings> _settingsController =
      StreamController<AudioSettings>.broadcast();
  final List<AudioplayersPlayerPort> _sfxPlayers = [];

  AudioplayersPlayerPort? _musicPlayer;
  AudioSettings _settings;
  double? _musicTrackVolumeOverride;
  int _sfxCursor = 0;
  bool _isDisposed = false;

  @override
  AudioSettings get settings => _settings;

  @override
  Stream<AudioSettings> get settingsStream => _settingsController.stream;

  @override
  Future<void> initialize() async {
    if (_isDisposed) return;
    _musicPlayer ??= _playerFactory();
  }

  @override
  Future<void> preload(List<String> assetIds) async {
    // audioplayers loads sources lazily on play; kept as a safe hook.
  }

  @override
  Future<void> playMusic(
    String trackId, {
    bool loop = true,
    double? volume,
  }) async {
    if (_isDisposed) return;
    _musicPlayer ??= _playerFactory();
    _musicTrackVolumeOverride = volume;
    await _musicPlayer!.setReleaseMode(
      loop ? ReleaseMode.loop : ReleaseMode.release,
    );
    await _musicPlayer!.play(
      _sourceResolver(trackId),
      volume: _effectiveMusicVolume(),
    );
  }

  @override
  Future<void> stopMusic() async {
    await _musicPlayer?.stop();
  }

  @override
  Future<void> pauseMusic() async {
    await _musicPlayer?.pause();
  }

  @override
  Future<void> resumeMusic() async {
    await _musicPlayer?.resume();
  }

  @override
  Future<void> playSfx(String soundId, {double? volume}) async {
    if (_isDisposed) return;
    final player = _nextSfxPlayer();
    await player.setReleaseMode(ReleaseMode.release);
    final effective =
        ((volume ?? 1.0).clamp(0.0, 1.0)) * _settings.effectiveSfxVolume;
    await player.play(_sourceResolver(soundId), volume: effective);
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
    if (_isDisposed) return;
    _settings = settings;
    await _musicPlayer?.setVolume(_effectiveMusicVolume());
    if (!_settingsController.isClosed) {
      _settingsController.add(_settings);
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _musicPlayer?.dispose();
    _musicPlayer = null;
    for (final player in _sfxPlayers) {
      await player.dispose();
    }
    _sfxPlayers.clear();
    await _settingsController.close();
  }

  AudioplayersPlayerPort _nextSfxPlayer() {
    if (_sfxPlayers.length < maxConcurrentSfxPlayers) {
      final created = _playerFactory();
      _sfxPlayers.add(created);
      return created;
    }
    final player = _sfxPlayers[_sfxCursor % _sfxPlayers.length];
    _sfxCursor = (_sfxCursor + 1) % _sfxPlayers.length;
    return player;
  }

  double _effectiveMusicVolume() {
    final override = (_musicTrackVolumeOverride ?? 1.0).clamp(0.0, 1.0);
    return override * _settings.effectiveMusicVolume;
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
