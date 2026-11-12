## 0.2.0

* **Security & Integrity Hardening**:
  * Replaced the legacy 32-bit FNV-1a/DJB2 save checksum with pure-Dart cross-platform **SHA-256** (FIPS 180-4 / RFC 6234) and keyed **HMAC-SHA256** (RFC 2104) via `GameSecurity` (plus `constantTimeEquals`, `constantTimeHexEquals`, `generateRandomBytes`, `generateSecureToken`, and `zeroBytes`).
  * Hardened `GameForge` persistence (`GameConfig.requireSaveIntegrity = true` by default, optional `saveSigningKey` parameter zeroed on `dispose()`, pre-migration integrity verification in `SaveMigrationRunner.migrateTo` to prevent version-downgrade re-signing attacks, and sanitized `SaveIntegrityException` errors without digest oracle leakage).
  * Added deserialization DoS and cycle protection in `GameSerialization` (`defaultMaxJsonBytes = 5 MiB`, `defaultMaxNestingDepth = 64`, O(N) pre-parse JSON bracket depth scan, ancestor-cycle tracking across DAG structures, non-finite double rejection, and safe-integer checks in `readInt`).
  * Added path-traversal, control-character, whitespace-padding, and length validation (`Validators.requireSafeKey`, `Validators.requireSafeId`, `Validators.requireSafeAssetId`) across `GameConfig`, `GameForge`, `MemoryGameStorage`, `SharedPreferencesGameStorage`, `GameSessionManager`, `NoopGameAudioService`, `RecordingGameAudioService`, and `AudioplayersGameAudioService`.
  * Added overflow-safe integer arithmetic (`Validators.safeAddInt`, `Validators.safeMultiplyAndRound`) and strict validation in `ScoreManager`, `RewardManager`, `AchievementManager`, `GameSessionManager`, and `SessionState`.
* **Dependencies**:
  * Verified and refreshed transitive dependency lockfiles across `example/` and `packages/` (`shared_preferences_android` `2.5.4` -> `2.5.5`), aligning companion package constraints (`shared_preferences: ^2.5.6`, `audioplayers: ^6.8.1`).

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
