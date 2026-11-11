import 'dart:async';
import 'dart:math' as math;

import '../core/game_event.dart';
import '../core/game_event_bus.dart';
import '../core/game_exception.dart';
import '../core/game_module.dart';
import '../persistence/serialization.dart';
import '../utils/game_clock.dart';
import 'game_item.dart';
import 'inventory_event.dart';
import 'inventory_state.dart';

/// Manages player items, stacking rules, slot capacity, atomic batch/transfer
/// operations, and persistence.
class InventoryManager extends GameModule {
  /// Creates an [InventoryManager].
  InventoryManager({
    int? capacity,
    this.allowSplitStacks = true,
    GameEventBus? eventBus,
    GameClock clock = const SystemGameClock(),
  }) : _capacity = capacity,
       _eventBus = eventBus,
       _clock = clock {
    if (_capacity != null && _capacity < 0) {
      throw GameConfigurationException(
        'InventoryManager capacity ($_capacity) cannot be negative.',
      );
    }
    _state = InventoryState(slots: const [], capacity: _capacity);
  }

  /// Module identifier used when registered in [GameForge].
  static const String moduleId = 'inventory';

  final int? _capacity;

  /// Whether stackable items whose addition exceeds `maxStackSize` may spill
  /// into additional slots when capacity allows.
  final bool allowSplitStacks;

  GameEventBus? _eventBus;
  GameClock _clock;
  final StreamController<InventoryState> _stateController =
      StreamController<InventoryState>.broadcast();

  final List<GameItem> _slots = [];
  late InventoryState _state;
  bool _isDisposed = false;

  @override
  String get id => moduleId;

  /// Configured slot capacity, or `null` if unlimited.
  int? get capacity => _capacity;

  /// Current immutable [InventoryState].
  InventoryState get state => _state;

  /// Unmodifiable list of current item slots.
  List<GameItem> get items => _state.slots;

  /// Broadcast stream emitting whenever inventory contents change.
  Stream<InventoryState> get stream => _stateController.stream;

  @override
  void onInitialize(GameModuleContext context) {
    _eventBus ??= context.events;
    _clock = context.clock;
  }

  @override
  void onReset() {
    clear();
  }

  @override
  Future<void> onDispose() async {
    await dispose();
  }

  /// Adds [item] to the inventory atomically.
  ///
  /// Throws [InvalidItemException], [DuplicateItemException], or
  /// [InventoryFullException] if constraints are violated without mutating state.
  void add(GameItem item) {
    addAll([item]);
  }

  /// Atomically adds all [items] to the inventory; either all succeed or none
  /// are applied.
  void addAll(List<GameItem> items) {
    _ensureNotDisposed();
    if (items.isEmpty) {
      return;
    }

    final workingSlots = List<GameItem>.of(_slots);
    final addedSummary = <String, ({GameItem item, int quantity})>{};

    for (final item in items) {
      item.validate();
      _applyAddToSlots(workingSlots, item);
      final prev = addedSummary[item.id];
      addedSummary[item.id] = (
        item: item,
        quantity: (prev?.quantity ?? 0) + item.quantity,
      );
    }

    _slots
      ..clear()
      ..addAll(workingSlots);
    _commitState();

    final now = _clock.now();
    for (final entry in addedSummary.entries) {
      _emitEvent(
        ItemAddedEvent(
          item: entry.value.item,
          addedQuantity: entry.value.quantity,
          totalQuantity: quantityOf(entry.key),
          timestamp: now,
        ),
      );
    }
  }

  /// Removes [quantity] units of [itemId] from the inventory atomically.
  ///
  /// Throws [ItemNotFoundException] or [InsufficientItemException] if absent
  /// or insufficient.
  void remove(String itemId, {int quantity = 1}) {
    _ensureNotDisposed();
    if (quantity <= 0) {
      throw InvalidItemException(
        'Removal quantity for "$itemId" must be positive (got $quantity).',
      );
    }

    final available = quantityOf(itemId);
    if (available == 0) {
      throw ItemNotFoundException(itemId);
    }
    if (available < quantity) {
      throw InsufficientItemException(
        itemId: itemId,
        requested: quantity,
        available: available,
      );
    }

    _removeFromSlots(_slots, itemId, quantity);
    _commitState();
    _emitEvent(
      ItemRemovedEvent(
        itemId: itemId,
        removedQuantity: quantity,
        remainingQuantity: quantityOf(itemId),
        timestamp: _clock.now(),
      ),
    );
  }

  /// Sets the total quantity of [itemId] to [quantity].
  ///
  /// Removing all units when `quantity == 0`. Throws [ItemNotFoundException]
  /// if [itemId] is not currently present.
  void updateQuantity(String itemId, int quantity) {
    _ensureNotDisposed();
    if (quantity < 0) {
      throw InvalidItemException(
        'Updated quantity for "$itemId" cannot be negative (got $quantity).',
      );
    }

    final existingSlots = _slots.where((slot) => slot.id == itemId).toList();
    if (existingSlots.isEmpty) {
      throw ItemNotFoundException(itemId);
    }

    final previous = existingSlots.fold<int>(0, (s, item) => s + item.quantity);
    if (previous == quantity) {
      return;
    }

    if (quantity == 0) {
      _slots.removeWhere((slot) => slot.id == itemId);
      _commitState();
      _emitEvent(
        ItemQuantityUpdatedEvent(
          itemId: itemId,
          previousQuantity: previous,
          newQuantity: 0,
          timestamp: _clock.now(),
        ),
      );
      return;
    }

    final template = existingSlots.first;
    if (!template.stackable && quantity > 1) {
      throw InvalidItemException(
        'Cannot set quantity > 1 on non-stackable item "$itemId".',
      );
    }

    final workingSlots = List<GameItem>.of(_slots)
      ..removeWhere((slot) => slot.id == itemId);
    _applyAddToSlots(workingSlots, template.copyWith(quantity: quantity));

    _slots
      ..clear()
      ..addAll(workingSlots);
    _commitState();
    _emitEvent(
      ItemQuantityUpdatedEvent(
        itemId: itemId,
        previousQuantity: previous,
        newQuantity: quantity,
        timestamp: _clock.now(),
      ),
    );
  }

  /// Consumes [quantity] units of [itemId], emitting [ItemConsumedEvent].
  void consume(String itemId, {int quantity = 1}) {
    _ensureNotDisposed();
    if (quantity <= 0) {
      throw InvalidItemException(
        'Consume quantity for "$itemId" must be positive (got $quantity).',
      );
    }

    final template = getItem(itemId);
    if (template == null) {
      throw ItemNotFoundException(itemId);
    }
    final available = quantityOf(itemId);
    if (available < quantity) {
      throw InsufficientItemException(
        itemId: itemId,
        requested: quantity,
        available: available,
      );
    }

    _removeFromSlots(_slots, itemId, quantity);
    _commitState();
    _emitEvent(
      ItemConsumedEvent(
        item: template,
        consumedQuantity: quantity,
        remainingQuantity: quantityOf(itemId),
        timestamp: _clock.now(),
      ),
    );
  }

  /// Atomically transfers [quantity] units of [itemId] from `this` inventory
  /// to [target].
  ///
  /// If [target] rejects the items (e.g., capacity full or duplicate item),
  /// neither inventory is modified.
  void transferTo(InventoryManager target, String itemId, {int quantity = 1}) {
    _ensureNotDisposed();
    target._ensureNotDisposed();
    if (identical(this, target)) {
      return;
    }
    if (quantity <= 0) {
      throw InvalidItemException(
        'Transfer quantity for "$itemId" must be positive (got $quantity).',
      );
    }

    final available = quantityOf(itemId);
    if (available == 0) {
      throw ItemNotFoundException(itemId);
    }
    if (available < quantity) {
      throw InsufficientItemException(
        itemId: itemId,
        requested: quantity,
        available: available,
      );
    }

    // Build staged copies for both source and target before committing either.
    final sourceWorking = List<GameItem>.of(_slots);
    final extracted = _removeFromSlots(sourceWorking, itemId, quantity);
    final targetWorking = List<GameItem>.of(target._slots);
    for (final chunk in extracted) {
      target._applyAddToSlots(targetWorking, chunk);
    }

    _slots
      ..clear()
      ..addAll(sourceWorking);
    target._slots
      ..clear()
      ..addAll(targetWorking);

    _commitState();
    target._commitState();

    final now = _clock.now();
    _emitEvent(
      ItemRemovedEvent(
        itemId: itemId,
        removedQuantity: quantity,
        remainingQuantity: quantityOf(itemId),
        timestamp: now,
      ),
    );
    target._emitEvent(
      ItemAddedEvent(
        item: extracted.first.copyWith(quantity: quantity),
        addedQuantity: quantity,
        totalQuantity: target.quantityOf(itemId),
        timestamp: now,
      ),
    );
    _emitEvent(
      ItemTransferredEvent(itemId: itemId, quantity: quantity, timestamp: now),
    );
  }

  /// Returns `true` if at least [quantity] units of [itemId] are present.
  bool hasItem(String itemId, {int quantity = 1}) {
    if (quantity <= 0) return false;
    return quantityOf(itemId) >= quantity;
  }

  /// Returns the total quantity of [itemId] held across all slots.
  int quantityOf(String itemId) => _state.quantityOf(itemId);

  /// Returns the first matching [GameItem] stack for [itemId], or `null`.
  GameItem? getItem(String itemId) {
    for (final slot in _slots) {
      if (slot.id == itemId) {
        return slot;
      }
    }
    return null;
  }

  /// Returns all slots matching [itemId].
  List<GameItem> slotsFor(String itemId) =>
      _slots.where((slot) => slot.id == itemId).toList(growable: false);

  /// Removes all items from the inventory.
  void clear() {
    _ensureNotDisposed();
    if (_slots.isEmpty) {
      return;
    }
    _slots.clear();
    _commitState();
    _emitEvent(InventoryClearedEvent(timestamp: _clock.now()));
  }

  @override
  Map<String, Object?> toSaveData() => _state.toJson();

  @override
  void fromSaveData(Map<String, Object?> data) {
    _ensureNotDisposed();
    final rawSlots = GameSerialization.readList(data, 'slots');
    final restored = <GameItem>[];
    for (final entry in rawSlots) {
      if (entry is! Map<Object?, Object?>) {
        throw const CorruptSaveDataException(
          'Expected map entry inside inventory slots list.',
        );
      }
      restored.add(GameItem.fromJson(GameSerialization.normalizeMap(entry)));
    }
    if (_capacity != null && restored.length > _capacity) {
      throw SaveValidationException(
        'Saved inventory slot count (${restored.length}) exceeds configured '
        'capacity ($_capacity).',
      );
    }

    // Validate duplicate non-stackables and stack consistency.
    final validated = <GameItem>[];
    for (final item in restored) {
      _applyAddToSlots(validated, item);
    }

    _slots
      ..clear()
      ..addAll(validated);
    _commitState();
  }

  /// Releases resources owned by this manager.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _stateController.close();
  }

  void _applyAddToSlots(List<GameItem> slots, GameItem item) {
    final existingWithId = slots.where((slot) => slot.id == item.id).toList();
    if (!item.stackable) {
      if (existingWithId.isNotEmpty) {
        throw DuplicateItemException(
          item.id,
          'Non-stackable item "${item.id}" already exists in the inventory.',
        );
      }
      _ensureSlotAvailable(slots, item.id);
      slots.add(item);
      return;
    }

    if (existingWithId.isNotEmpty) {
      final first = existingWithId.first;
      if (!first.stackable) {
        throw DuplicateItemException(
          item.id,
          'Item "${item.id}" already exists as a non-stackable item.',
        );
      }
      if (first.type != item.type) {
        throw DuplicateItemException(
          item.id,
          'Conflicting type "${item.type}" for existing item "${item.id}" '
          '(expected "${first.type}").',
        );
      }
    }

    var remaining = item.quantity;
    final stackLimit =
        item.maxStackSize ?? existingWithId.firstOrNull?.maxStackSize;

    // Fill existing stacks first.
    for (var i = 0; i < slots.length && remaining > 0; i++) {
      final current = slots[i];
      if (current.id != item.id) {
        continue;
      }
      final effectiveLimit = current.maxStackSize ?? stackLimit;
      if (effectiveLimit == null) {
        slots[i] = current.copyWith(quantity: current.quantity + remaining);
        remaining = 0;
      } else if (current.quantity < effectiveLimit) {
        final room = effectiveLimit - current.quantity;
        final addAmount = math.min(room, remaining);
        slots[i] = current.copyWith(quantity: current.quantity + addAmount);
        remaining -= addAmount;
      }
    }

    if (remaining > 0 && !allowSplitStacks && existingWithId.isNotEmpty) {
      throw InventoryFullException(
        'Cannot add $remaining more of "${item.id}" without exceeding stack '
        'limit ($stackLimit).',
      );
    }

    while (remaining > 0) {
      _ensureSlotAvailable(slots, item.id);
      final chunk = stackLimit == null
          ? remaining
          : math.min(remaining, stackLimit);
      slots.add(item.copyWith(quantity: chunk));
      remaining -= chunk;
    }
  }

  void _ensureSlotAvailable(List<GameItem> slots, String itemId) {
    if (_capacity != null && slots.length >= _capacity) {
      throw InventoryFullException(
        'Inventory is full (${slots.length}/$_capacity slots) while adding '
        '"$itemId".',
      );
    }
  }

  List<GameItem> _removeFromSlots(
    List<GameItem> slots,
    String itemId,
    int quantity,
  ) {
    var remaining = quantity;
    final removedChunks = <GameItem>[];
    for (var i = slots.length - 1; i >= 0 && remaining > 0; i--) {
      final slot = slots[i];
      if (slot.id != itemId) {
        continue;
      }
      if (slot.quantity <= remaining) {
        removedChunks.add(slot);
        remaining -= slot.quantity;
        slots.removeAt(i);
      } else {
        removedChunks.add(slot.copyWith(quantity: remaining));
        slots[i] = slot.copyWith(quantity: slot.quantity - remaining);
        remaining = 0;
      }
    }
    return removedChunks;
  }

  void _commitState() {
    _state = InventoryState(slots: _slots, capacity: _capacity);
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _emitEvent(GameEvent event) {
    final bus = _eventBus;
    if (bus != null && !bus.isDisposed) {
      bus.emit(event);
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw const GameStateException(
        'Cannot use InventoryManager after it has been disposed.',
      );
    }
  }
}
