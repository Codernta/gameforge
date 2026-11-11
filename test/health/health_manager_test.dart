import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('HealthManager', () {
    test('handles damage, healing, lives, auto-respawn, and death', () async {
      final clock = FakeGameClock();
      final bus = GameEventBus();
      final events = <GameEvent>[];
      final sub = bus.on<GameEvent>(events.add);

      final health = HealthManager(
        config: const HealthConfig(
          maxHealth: 100,
          initialLives: 2,
          maxLives: 3,
        ),
        clock: clock,
        eventBus: bus,
      );

      expect(health.takeDamage(20), 20);
      expect(health.currentHealth, 80);
      expect(health.heal(10), 10);
      expect(health.currentHealth, 90);
      expect(health.heal(50), 10); // clamped at 100
      expect(health.currentHealth, 100);

      // Fatal hit consumes 1 life and respawns to full health
      health.takeDamage(100);
      expect(health.lives, 1);
      expect(health.currentHealth, 100);
      expect(health.isAlive, isTrue);

      health.addLife();
      expect(health.lives, 2);
      health.addLife(count: 5); // clamped at maxLives = 3
      expect(health.lives, 3);

      health.loseLife();
      expect(health.lives, 2);
      health.loseLife();
      expect(health.lives, 1);
      health.loseLife();
      expect(health.lives, 0);
      expect(health.isDead, isTrue);

      // Damage & heal ignored when permanently dead
      expect(health.takeDamage(10), 0);
      expect(health.heal(10), 0);

      health.revive(health: 60, lives: 2);
      expect(health.isAlive, isTrue);
      expect(health.currentHealth, 60);
      expect(health.lives, 2);

      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<PlayerRespawnedEvent>(), isNotEmpty);
      expect(events.whereType<PlayerDiedEvent>(), hasLength(1));

      await sub.cancel();
      await health.dispose();
      await bus.dispose();
    });

    test('supports deterministic invincibility windows with FakeGameClock', () {
      final clock = FakeGameClock();
      final health = HealthManager(
        config: const HealthConfig(
          maxHealth: 100,
          initialLives: 3,
          invincibilityDuration: Duration(seconds: 2),
          invincibilityOnDamage: true,
        ),
        clock: clock,
      );

      expect(health.takeDamage(25), 25);
      expect(health.isInvincible, isTrue);

      // Blocked during invincibility
      expect(health.takeDamage(25), 0);
      expect(health.currentHealth, 75);

      // Override invincibility explicitly
      expect(health.takeDamage(10, ignoreInvincibility: true), 10);
      expect(health.currentHealth, 65);

      clock.advance(const Duration(seconds: 2));
      expect(health.isInvincible, isFalse);

      expect(health.takeDamage(15), 15);
      expect(health.currentHealth, 50);

      health.clearInvincibility();
      expect(health.isInvincible, isFalse);
    });

    test('supports non-lives health-only mode and validation errors', () {
      final health = HealthManager(
        config: const HealthConfig(maxHealth: 50, supportsLives: false),
      );
      expect(() => health.addLife(), throwsA(isA<HealthValidationException>()));
      expect(
        () => health.loseLife(),
        throwsA(isA<HealthValidationException>()),
      );
      expect(
        () => health.takeDamage(-1),
        throwsA(isA<HealthValidationException>()),
      );
      expect(() => health.heal(-1), throwsA(isA<HealthValidationException>()));

      health.takeDamage(50);
      expect(health.isDead, isTrue);

      health.setMaxHealth(80, healToFull: true);
      expect(health.maxHealth, 80);
      expect(health.currentHealth, 80);
    });
  });
}
