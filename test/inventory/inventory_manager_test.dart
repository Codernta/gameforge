import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('InventoryManager', () {
    test('handles add, remove, consume, updateQuantity, and stacks', () async {
      final bus = GameEventBus();
      final events = <GameEvent>[];
      final sub = bus.on<GameEvent>(events.add);

      final inventory = InventoryManager(capacity: 3, eventBus: bus);

      inventory.add(
        const GameItem(
          id: 'coin',
          name: 'Gold Coin',
          quantity: 50,
          maxStackSize: 60,
        ),
      );
      expect(inventory.hasItem('coin'), isTrue);
      expect(inventory.hasItem('coin', quantity: 50), isTrue);

      // Adds 30 coins -> fills slot 1 to 60 and spills 20 to slot 2
      inventory.add(
        const GameItem(
          id: 'coin',
          name: 'Gold Coin',
          quantity: 30,
          maxStackSize: 60,
        ),
      );
      expect(inventory.quantityOf('coin'), 80);
      expect(inventory.state.usedSlots, 2);

      inventory.remove('coin', quantity: 10);
      expect(inventory.quantityOf('coin'), 70);

      inventory.consume('coin', quantity: 15);
      expect(inventory.quantityOf('coin'), 55);
      expect(inventory.state.usedSlots, 1);

      inventory.updateQuantity('coin', 100);
      expect(inventory.quantityOf('coin'), 100);
      expect(inventory.state.usedSlots, 2);

      inventory.updateQuantity('coin', 0);
      expect(inventory.hasItem('coin'), isFalse);
      expect(inventory.state.isEmpty, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<ItemAddedEvent>(), hasLength(2));
      expect(events.whereType<ItemRemovedEvent>(), hasLength(1));
      expect(events.whereType<ItemConsumedEvent>(), hasLength(1));
      expect(events.whereType<ItemQuantityUpdatedEvent>(), hasLength(2));

      await sub.cancel();
      await inventory.dispose();
      await bus.dispose();
    });

    test(
      'validates duplicates, capacity, and atomic rollback on addAll/transfer',
      () async {
        final source = InventoryManager(capacity: 3);
        final target = InventoryManager(capacity: 1);

        const sword = GameItem(
          id: 'excalibur',
          name: 'Excalibur',
          stackable: false,
        );
        source.add(sword);

        // Duplicate non-stackable item rejected
        expect(() => source.add(sword), throwsA(isA<DuplicateItemException>()));

        // Atomic addAll rolls back completely if second item fails
        expect(
          () => source.addAll([
            const GameItem(id: 'potion', name: 'Potion', quantity: 2),
            sword, // duplicate!
          ]),
          throwsA(isA<DuplicateItemException>()),
        );
        expect(source.hasItem('potion'), isFalse);

        // Atomic transferTo fails cleanly without mutating source
        target.add(
          const GameItem(id: 'key', name: 'Iron Key', stackable: false),
        );
        expect(target.state.isFull, isTrue);

        expect(
          () => source.transferTo(target, 'excalibur'),
          throwsA(isA<InventoryFullException>()),
        );
        expect(source.hasItem('excalibur'), isTrue);
        expect(target.hasItem('excalibur'), isFalse);

        // Succeeds once capacity allows
        final spacious = InventoryManager(capacity: 2);
        source.add(const GameItem(id: 'gem', name: 'Gem', quantity: 5));
        source.transferTo(spacious, 'gem', quantity: 3);
        expect(source.quantityOf('gem'), 2);
        expect(spacious.quantityOf('gem'), 3);

        await source.dispose();
        await target.dispose();
        await spacious.dispose();
      },
    );

    test('throws appropriate errors on missing or insufficient items', () {
      final inventory = InventoryManager();
      expect(
        () => inventory.remove('missing'),
        throwsA(isA<ItemNotFoundException>()),
      );
      inventory.add(const GameItem(id: 'arrow', name: 'Arrow', quantity: 3));
      expect(
        () => inventory.remove('arrow', quantity: 5),
        throwsA(isA<InsufficientItemException>()),
      );
      expect(
        () => inventory.consume('arrow', quantity: 5),
        throwsA(isA<InsufficientItemException>()),
      );
    });
  });
}
