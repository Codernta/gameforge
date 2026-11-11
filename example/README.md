# Coin Rush Example

**Coin Rush** is a complete playable Flutter arcade example demonstrating the `gameforge` gameplay toolkit.

## What It Demonstrates

- **Lifecycle & State**: `GameForge.initialize()`, `start()`, `pause()`, `resume()`, `restart()`, `dispose()`, and reactive `GameForgeScope` / `GameForgeBuilder` / `GameForgeStatusBuilder`.
- **Score & Combos**: Real-time score increments, combo streaks, multiplier boosts, and high-score tracking with `GameScoreWidget`.
- **Health, Lives & Invincibility**: 3 starting lives, obstacle collisions, 2-second post-damage invincibility window, and `GameHealthWidget`.
- **Timers**: Level countdown timer (`CountdownTimer`) that pauses automatically when the game pauses, rendered via `GameTimerWidget`.
- **Levels & Progression**: 4 progressive levels unlocked upon completion with star ratings and level replay/selection.
- **Inventory & Rewards**: Coin collection grants inventory items and spendable coins exchangeable in the Reward Shop for Extra Hearts, Turbo Boots, or a 2x Multiplier.
- **Achievements & Events**: Unlockable achievements (`first_coin`, `century_scorer`, `level_clearer`) with reward payouts and live event feed updates.
- **Persistence**: Automatic progress saving and restoration across app restarts via `GameStorage` backed by `shared_preferences`.

## Running

```bash
cd example
flutter pub get
flutter run
```
