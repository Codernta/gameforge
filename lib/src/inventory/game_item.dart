import 'package:meta/meta.dart';

import '../core/game_exception.dart';
import '../persistence/serialization.dart';

/// Immutable representation of an item stored in an [InventoryManager].
@immutable
class GameItem {
  /// Creates a [GameItem].
  const GameItem({
    required this.id,
    required this.name,
    this.description = '',
    this.type = 'generic',
    this.quantity = 1,
    this.stackable = true,
    this.maxStackSize,
    this.metadata = const {},
  });

  /// Restores a [GameItem] from serialized JSON data.
  factory GameItem.fromJson(Map<String, Object?> json) {
    final id = GameSerialization.readString(json, 'id');
    final name = GameSerialization.readString(json, 'name');
    final description = GameSerialization.readString(
      json,
      'description',
      defaultValue: '',
    );
    final type = GameSerialization.readString(
      json,
      'type',
      defaultValue: 'generic',
    );
    final quantity = GameSerialization.readInt(json, 'quantity');
    final stackable = GameSerialization.readBool(
      json,
      'stackable',
      defaultValue: true,
    );
    final maxStackRaw = json['maxStackSize'];
    final maxStackSize = maxStackRaw == null
        ? null
        : GameSerialization.readInt(json, 'maxStackSize');
    final metadata = GameSerialization.readMap(
      json,
      'metadata',
      defaultValue: const {},
    );

    final item = GameItem(
      id: id,
      name: name,
      description: description,
      type: type,
      quantity: quantity,
      stackable: stackable,
      maxStackSize: maxStackSize,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
    item.validate();
    return item;
  }

  /// Unique identifier for this item or item template.
  final String id;

  /// Human-readable item name.
  final String name;

  /// Descriptive text for UI tooltips or details.
  final String description;

  /// Category/type tag (e.g., `'currency'`, `'consumable'`, `'equipment'`).
  final String type;

  /// Number of units in this item stack.
  final int quantity;

  /// Whether multiple units can be stacked together.
  final bool stackable;

  /// Optional maximum stack capacity per slot.
  final int? maxStackSize;

  /// Optional custom key-value attributes.
  final Map<String, Object?> metadata;

  /// Effective maximum stack limit per slot (`1` when non-stackable).
  int? get effectiveMaxStackSize => stackable ? maxStackSize : 1;

  /// Validates field invariants on this item.
  void validate({bool allowZeroQuantity = false}) {
    if (id.trim().isEmpty) {
      throw const InvalidItemException('GameItem id cannot be empty.');
    }
    if (name.trim().isEmpty) {
      throw InvalidItemException('GameItem "$id" name cannot be empty.');
    }
    if (type.trim().isEmpty) {
      throw InvalidItemException('GameItem "$id" type cannot be empty.');
    }
    if (allowZeroQuantity ? quantity < 0 : quantity <= 0) {
      throw InvalidItemException(
        'GameItem "$id" quantity ($quantity) is invalid.',
      );
    }
    if (maxStackSize != null && maxStackSize! < 1) {
      throw InvalidItemException(
        'GameItem "$id" maxStackSize ($maxStackSize) must be >= 1.',
      );
    }
    if (!stackable && quantity > 1) {
      throw InvalidItemException(
        'Non-stackable GameItem "$id" cannot have quantity > 1 (got $quantity).',
      );
    }
    if (stackable && maxStackSize != null && quantity > maxStackSize!) {
      throw InvalidItemException(
        'GameItem "$id" quantity ($quantity) exceeds maxStackSize '
        '($maxStackSize).',
      );
    }
  }

  /// Returns a modified copy of this [GameItem].
  GameItem copyWith({
    String? id,
    String? name,
    String? description,
    String? type,
    int? quantity,
    bool? stackable,
    int? maxStackSize,
    Map<String, Object?>? metadata,
  }) {
    return GameItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      stackable: stackable ?? this.stackable,
      maxStackSize: maxStackSize ?? this.maxStackSize,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Serializes this item into JSON-compatible data.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type,
    'quantity': quantity,
    'stackable': stackable,
    'maxStackSize': maxStackSize,
    'metadata': GameSerialization.normalizeMap(metadata),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameItem &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.type == type &&
        other.quantity == quantity &&
        other.stackable == stackable &&
        other.maxStackSize == maxStackSize &&
        _mapsEqual(other.metadata, metadata);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    type,
    quantity,
    stackable,
    maxStackSize,
    Object.hashAllUnordered(
      metadata.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _mapsEqual(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'GameItem(id: $id, name: $name, quantity: $quantity, '
      'stackable: $stackable)';
}
