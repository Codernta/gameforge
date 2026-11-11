import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('GameAudioService & AudioSettings', () {
    test('calculates effective volumes and handles mute toggles', () async {
      final audio = RecordingGameAudioService(
        initialSettings: const AudioSettings(
          masterVolume: 0.8,
          musicVolume: 0.5,
          sfxVolume: 0.75,
        ),
      );
      expect(audio.settings.effectiveMusicVolume, closeTo(0.4, 0.0001));
      expect(audio.settings.effectiveSfxVolume, closeTo(0.6, 0.0001));

      await audio.initialize();
      await audio.preload(['coin.wav', 'hit.wav']);
      await audio.playMusic('bgm.mp3');
      await audio.playSfx('coin.wav');

      await audio.mute();
      expect(audio.settings.effectiveMusicVolume, 0.0);
      expect(audio.settings.effectiveSfxVolume, 0.0);

      await audio.toggleMute();
      expect(audio.settings.isMuted, isFalse);

      await audio.setMusicMuted(true);
      expect(audio.settings.effectiveMusicVolume, 0.0);
      expect(audio.settings.effectiveSfxVolume, closeTo(0.6, 0.0001));

      await audio.pauseMusic();
      expect(audio.isMusicPaused, isTrue);
      await audio.resumeMusic();
      expect(audio.isMusicPlaying, isTrue);
      await audio.stopMusic();
      expect(audio.currentMusicTrack, isNull);

      expect(
        () => audio.setMasterVolume(1.5),
        throwsA(isA<GameConfigurationException>()),
      );

      await audio.dispose();
    });
  });
}
