## 0.1.0

* Initial production-ready release of the **GameForge** gameplay toolkit:
  * Core `GameForge` controller with `GameConfig`, `GameState`, `GameStatus` lifecycle validation, `GameModule` extensibility, and `GameEventBus` with loop protection and typed error handling.
  * `ScoreManager` with score arithmetic, base & combo multipliers, high-score tracking, and overflow/negative validation.
  * `HealthManager` supporting configurable health bars, lives, auto-respawn, and clock-driven invincibility windows.
  * `LevelManager` supporting sequential, prerequisite-graph, open, and custom `LevelProgressionStrategy` implementations, star ratings, and per-level best scores.
  * `InventoryManager` with `GameItem` stack management, slot capacity limits, duplicate detection, and atomic `addAll` / `transferTo` operations.
  * `RewardManager` supporting coins, points, items, XP, custom rewards, bundles, pending offer/claim queues, and duplicate one-time claim protection.
  * `AchievementManager` supporting incremental progress, custom `AchievementCondition` evaluation, and automatic reward payouts.
  * `CountdownTimer`, `StopwatchTimer`, `PeriodicTimer`, `GameTimerManager`, and deterministic `FakeGameClock` / `GameTicker` abstractions.
  * Persistence system with `GameStorage`, `MemoryGameStorage`, strict `GameSerialization`, `GameSaveData` checksums, atomic rollback on failed restore, and chained `SaveMigration` support.
  * `GameSessionManager` tracking active gameplay duration (excluding pauses), session statistics, and persisted history.
  * Engine-independent `GameInputHandler` and `GameAudioService` abstractions (`NoopGameAudioService`, `RecordingGameAudioService`).
  * Optional Flutter UI layer (`package:gameforge/flutter.dart`) with `GameForgeScope`, `GameForgeBuilder`, `GameForgeStatusBuilder`, `GameScoreWidget`, `GameHealthWidget`, `GameTimerWidget`, `GameForgeInputRegion`, and `VirtualJoystickWidget`.
  * Complete playable **Coin Rush** example application inside `example/`.
  * Optional companion adapter packages: `gameforge_flame`, `gameforge_audioplayers`, and `gameforge_shared_preferences`.
