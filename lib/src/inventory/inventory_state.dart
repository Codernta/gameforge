import 'package:meta/meta.dart';

import 'game_item.dart';

/// Immutable snapshot of all item slots and capacity usage in an
/// [InventoryManager].
@immutable
class InventoryState {
  /// Creates an [InventoryState].
  InventoryState({required List<GameItem> slots, this.capacity})
    : slots = List<GameItem>.unmodifiable(slots);

  /// Ordered list of occupied item slots/stacks.
  final List<GameItem> slots;

  /// Maximum number of slots permitted, or `null` if unlimited.
  final int? capacity;

  /// Number of currently occupied slots.
  int get usedSlots => slots.length;

  /// Number of free slots remaining, or `null` if [capacity] is unlimited.
  int? get remainingSlots => capacity == null ? null : capacity! - slots.length;

  /// Whether slot capacity has been reached.
  bool get isFull => capacity != null && slots.length >= capacity!;

  /// Whether the inventory contains zero items.
  bool get isEmpty => slots.isEmpty;

  /// Combined total quantity summed across all slots.
  int get totalQuantity =>
      slots.fold<int>(0, (sum, item) => sum + item.quantity);

  /// Total quantity held for [itemId].
  int quantityOf(String itemId) {
    var total = 0;
    for (final slot in slots) {
      if (slot.id == itemId) {
        total += slot.quantity;
      }
    }
    return total;
  }

  /// Serializes this inventory state into JSON-compatible data.
  Map<String, Object?> toJson() => {
    'capacity': capacity,
    'slots': slots.map((slot) => slot.toJson()).toList(growable: false),
  };
}
