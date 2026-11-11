# gameforge_audioplayers

Optional `audioplayers` (`^6.8.1`, MIT) adapter implementing GameForge's `GameAudioService`.

## Usage

```dart
final audio = AudioplayersGameAudioService();
final game = GameForge(audio: audio);
await game.initialize();
await audio.playMusic('audio/theme.mp3');
await audio.playSfx('audio/coin.wav');
```
