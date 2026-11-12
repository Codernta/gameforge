import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';
import 'package:gameforge_audioplayers/gameforge_audioplayers.dart';

class _FakeAudioPlayerPort implements AudioplayersPlayerPort {
  final List<String> log = [];
  double? lastVolume;
  ReleaseMode? lastReleaseMode;
  bool disposed = false;

  @override
  Future<void> play(Source source, {double? volume}) async {
    lastVolume = volume;
    log.add('play:$source');
  }

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {
    lastReleaseMode = releaseMode;
    log.add('releaseMode:${releaseMode.name}');
  }

  @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
    log.add('volume:$volume');
  }

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> resume() async => log.add('resume');

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<void> dispose() async {
    disposed = true;
    log.add('dispose');
  }
}

void main() {
  group('AudioplayersGameAudioService', () {
    test(
      'routes music, SFX pool, volume updates, mute, and disposal',
      () async {
        final createdPlayers = <_FakeAudioPlayerPort>[];
        final audio = AudioplayersGameAudioService(
          initialSettings: const AudioSettings(
            masterVolume: 0.5,
            musicVolume: 0.8,
            sfxVolume: 0.6,
          ),
          maxConcurrentSfxPlayers: 2,
          playerFactory: () {
            final player = _FakeAudioPlayerPort();
            createdPlayers.add(player);
            return player;
          },
        );

        final game = GameForge(audio: audio);
        await game.initialize();
        expect(createdPlayers, hasLength(1));

        await audio.playMusic('bgm.mp3', loop: true);
        final musicPlayer = createdPlayers.first;
        expect(musicPlayer.lastReleaseMode, ReleaseMode.loop);
        expect(musicPlayer.lastVolume, closeTo(0.4, 0.0001));

        game.start();
        game.pause();
        await Future<void>.delayed(Duration.zero);
        expect(musicPlayer.log, contains('pause'));

        game.resume();
        await Future<void>.delayed(Duration.zero);
        expect(musicPlayer.log, contains('resume'));

        await audio.playSfx('coin.wav');
        await audio.playSfx('hit.wav');
        await audio.playSfx('jump.wav'); // reuses pooled SFX player!
        expect(createdPlayers, hasLength(3)); // 1 music + max 2 SFX players

        await audio.mute();
        expect(musicPlayer.lastVolume, 0.0);

        await game.dispose();
        expect(createdPlayers.every((p) => p.disposed), isTrue);
      },
    );

    test(
      'rejects unsafe asset IDs, invalid volumes, and bad pool size',
      () async {
        expect(
          () => AudioplayersGameAudioService(maxConcurrentSfxPlayers: 0),
          throwsA(isA<GameConfigurationException>()),
        );

        final audio = AudioplayersGameAudioService(
          playerFactory: _FakeAudioPlayerPort.new,
        );
        await expectLater(
          audio.preload(const ['../secret.mp3']),
          throwsA(isA<GameConfigurationException>()),
        );
        await expectLater(
          audio.playMusic('file:///etc/passwd'),
          throwsA(isA<GameConfigurationException>()),
        );
        await expectLater(
          audio.playSfx('coin.wav', volume: double.nan),
          throwsA(isA<GameConfigurationException>()),
        );
        await expectLater(
          audio.playSfx('coin.wav', volume: 1.25),
          throwsA(isA<GameConfigurationException>()),
        );
        await audio.dispose();
      },
    );
  });
}
