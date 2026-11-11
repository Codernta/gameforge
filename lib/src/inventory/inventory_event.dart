import '../core/game_event.dart';
import 'game_item.dart';

/// Emitted when an item or stack is added to an [InventoryManager].
final class ItemAddedEvent extends GameEvent {
  /// Creates an [ItemAddedEvent].
  ItemAddedEvent({
    required this.item,
    required this.addedQuantity,
    required this.totalQuantity,
    super.timestamp,
  });

  /// Template/item added.
  final GameItem item;

  /// Quantity added in this operation.
  final int addedQuantity;

  /// Resulting total quantity for [GameItem.id].
  final int totalQuantity;
}

/// Emitted when items are removed from an [InventoryManager].
final class ItemRemovedEvent extends GameEvent {
  /// Creates an [ItemRemovedEvent].
  ItemRemovedEvent({
    required this.itemId,
    required this.removedQuantity,
    required this.remainingQuantity,
    super.timestamp,
  });

  /// Identifier of the removed item.
  final String itemId;

  /// Quantity removed.
  final int removedQuantity;

  /// Quantity remaining in inventory.
  final int remainingQuantity;
}

/// Emitted when an item quantity is explicitly updated.
final class ItemQuantityUpdatedEvent extends GameEvent {
  /// Creates an [ItemQuantityUpdatedEvent].
  ItemQuantityUpdatedEvent({
    required this.itemId,
    required this.previousQuantity,
    required this.newQuantity,
    super.timestamp,
  });

  /// Identifier of the updated item.
  final String itemId;

  /// Quantity prior to update.
  final int previousQuantity;

  /// Quantity after update.
  final int newQuantity;
}

/// Emitted when an item is consumed via [InventoryManager.consume].
final class ItemConsumedEvent extends GameEvent {
  /// Creates an [ItemConsumedEvent].
  ItemConsumedEvent({
    required this.item,
    required this.consumedQuantity,
    required this.remainingQuantity,
    super.timestamp,
  });

  /// Metadata snapshot of the consumed item.
  final GameItem item;

  /// Quantity consumed.
  final int consumedQuantity;

  /// Quantity remaining in inventory.
  final int remainingQuantity;
}

/// Emitted when items are transferred between two [InventoryManager] instances.
final class ItemTransferredEvent extends GameEvent {
  /// Creates an [ItemTransferredEvent].
  ItemTransferredEvent({
    required this.itemId,
    required this.quantity,
    super.timestamp,
  });

  /// Identifier of the transferred item.
  final String itemId;

  /// Quantity transferred.
  final int quantity;
}

/// Emitted when an [InventoryManager] is cleared.
final class InventoryClearedEvent extends GameEvent {
  /// Creates an [InventoryClearedEvent].
  InventoryClearedEvent({super.timestamp});
}
