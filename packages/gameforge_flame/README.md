# gameforge_flame

Optional Flame (`^1.38.2`) engine adapter for `gameforge`.

## Features

- `GameForgeFlameBridge`: Composition component synchronizing `GameForge` lifecycle, `pauseEngine`/`resumeEngine`, and cleanup.
- `GameForgeFlameMixin`: Bidirectional mixin for `FlameGame` subclasses.
- `GameForgeScoreComponent` & `GameForgeHealthComponent`: Reactive Flame components syncing score and health streams with automatic cleanup in `onRemove`.
- `GameForgeEventListenerComponent<T>`: Lifecycle-safe `GameEventBus` listener component.
