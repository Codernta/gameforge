import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

void main() {
  group('Utilities', () {
    test('SequentialIdGenerator and RandomIdGenerator generate unique IDs', () {
      final seq = SequentialIdGenerator();
      expect(seq.nextId('item'), 'item_1');
      expect(seq.nextId('item'), 'item_2');
      expect(seq.nextId(), '3');
      seq.reset();
      expect(seq.nextId('item'), 'item_1');

      final rand = RandomIdGenerator();
      final ids = {for (var i = 0; i < 50; i++) rand.nextId('e')};
      expect(ids, hasLength(50));
      expect(ids.first.startsWith('e_'), isTrue);
    });

    test('Validators enforce boundaries and throw typed exceptions', () {
      expect(Validators.requireNonEmpty('ok', 'field'), 'ok');
      expect(
        () => Validators.requireNonEmpty('  ', 'field'),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(Validators.requireNonNegative(0, 'n'), 0);
      expect(
        () => Validators.requireNonNegative(-1, 'n'),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(Validators.requirePositive(1, 'p'), 1);
      expect(
        () => Validators.requirePositive(0, 'p'),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(Validators.requireInRange(5, 1, 10, 'r'), 5);
      expect(
        () => Validators.requireInRange(11, 1, 10, 'r'),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => Validators.requireFinite(double.infinity, 'f'),
        throwsA(isA<GameConfigurationException>()),
      );
    });
  });
}
