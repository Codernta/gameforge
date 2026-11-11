# Contributing to GameForge

Thank you for your interest in contributing to **GameForge**!

## Development Setup

1. Ensure you have Flutter stable (`>=3.29.0`) and Dart (`^3.8.0`) installed.
2. Fetch dependencies:

```bash
flutter pub get
```

3. Run static analysis, formatting checks, and tests:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## Workspace Layout

- `lib/` — Core `gameforge` package (`lib/gameforge.dart` pure Dart core + `lib/flutter.dart` Flutter widgets and input adapters).
- `test/` — Unit and widget tests for all modules.
- `example/` — Playable **Coin Rush** example game.
- `packages/gameforge_flame/` — Optional Flame (`^1.38.2`) engine integration package.
- `packages/gameforge_audioplayers/` — Optional `audioplayers` (`^6.8.1`) audio adapter package.
- `packages/gameforge_shared_preferences/` — Optional `shared_preferences` (`^2.5.6`) storage adapter package.

## Pull Request Guidelines

- Keep `lib/gameforge.dart` and everything under `lib/src/` (outside `lib/src/adapters/`) 100% free of Flutter UI (`package:flutter` / `dart:ui`) imports.
- Do not introduce unnecessary third-party dependencies to the root `gameforge` package.
- Add deterministic unit or widget tests for every new feature or bug fix using `FakeGameClock` rather than arbitrary `Future.delayed` timers.
- Document all public classes, constructors, methods, and fields (`public_member_api_docs` is enforced by `analysis_options.yaml`).
- Ensure `flutter analyze`, `dart format`, and `flutter test` pass cleanly across root, `example/`, and companion packages before opening a PR.
