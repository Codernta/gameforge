# gameforge_shared_preferences

Optional `shared_preferences` (`^2.5.6`) storage adapter implementing GameForge's `GameStorage`.

## Usage

```dart
final storage = SharedPreferencesGameStorage(keyPrefix: 'my_game:');
final game = GameForge(storage: storage);
await game.initialize();
await game.load();
```
