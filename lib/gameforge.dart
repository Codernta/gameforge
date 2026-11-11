/// Modular, engine-independent gameplay toolkit for Dart and Flutter.
///
/// Import `package:gameforge/gameforge.dart` for pure Dart gameplay systems
/// without any Flutter UI dependency, or `package:gameforge/flutter.dart` for
/// Flutter HUD widgets and input adapters.
library;

// Achievements
export 'src/achievements/achievement.dart';
export 'src/achievements/achievement_manager.dart';
export 'src/achievements/achievement_progress.dart';

// Audio
export 'src/audio/audio_settings.dart';
export 'src/audio/game_audio.dart';

// Core
export 'src/core/game_config.dart';
export 'src/core/game_controller.dart';
export 'src/core/game_event.dart';
export 'src/core/game_event_bus.dart';
export 'src/core/game_exception.dart';
export 'src/core/game_module.dart';
export 'src/core/game_state.dart';
export 'src/core/game_status.dart';

// Health & Lives
export 'src/health/damage_event.dart';
export 'src/health/health_manager.dart';
export 'src/health/health_state.dart';

// Input
export 'src/input/game_input.dart';
export 'src/input/game_input_handler.dart';

// Inventory
export 'src/inventory/game_item.dart';
export 'src/inventory/inventory_event.dart';
export 'src/inventory/inventory_manager.dart';
export 'src/inventory/inventory_state.dart';

// Levels
export 'src/levels/level_config.dart';
export 'src/levels/level_event.dart';
export 'src/levels/level_manager.dart';
export 'src/levels/level_state.dart';

// Persistence
export 'src/persistence/game_save_data.dart';
export 'src/persistence/game_storage.dart';
export 'src/persistence/memory_game_storage.dart';
export 'src/persistence/serialization.dart';

// Rewards
export 'src/rewards/reward.dart';
export 'src/rewards/reward_event.dart';
export 'src/rewards/reward_manager.dart';

// Score
export 'src/score/score_event.dart';
export 'src/score/score_manager.dart';
export 'src/score/score_state.dart';

// Session
export 'src/session/game_session.dart';
export 'src/session/session_state.dart';

// Timers & Clocks
export 'src/timer/countdown_timer.dart';
export 'src/timer/game_timer.dart';
export 'src/timer/timer_state.dart';

// Utilities
export 'src/utils/game_clock.dart';
export 'src/utils/id_generator.dart';
export 'src/utils/validators.dart';
