import 'package:meta/meta.dart';

import '../core/game_exception.dart';
import 'serialization.dart';

/// Migrates raw serialized save data from [fromVersion] to [toVersion].
abstract interface class SaveMigration {
  /// Source schema version expected by this migration.
  int get fromVersion;

  /// Target schema version produced by this migration (`toVersion > fromVersion`).
  int get toVersion;

  /// Transforms [data] from [fromVersion] to [toVersion].
  Map<String, Object?> migrate(Map<String, Object?> data);
}

/// Applies ordered [SaveMigration] steps to upgrade older save files up to a
/// target schema version.
class SaveMigrationRunner {
  /// Creates a [SaveMigrationRunner] with [migrations].
  SaveMigrationRunner(List<SaveMigration> migrations)
    : _migrations = List<SaveMigration>.unmodifiable(migrations) {
    for (final migration in _migrations) {
      if (migration.toVersion <= migration.fromVersion) {
        throw SaveMigrationException(
          'Invalid SaveMigration ${migration.fromVersion} -> '
          '${migration.toVersion}: toVersion must be greater than fromVersion.',
        );
      }
    }
  }

  final List<SaveMigration> _migrations;

  /// Migrates [rawData] from its recorded `version` up to [targetVersion].
  ///
  /// When [rawData] already matches [targetVersion], returns a normalized copy.
  /// Throws [SaveMigrationException] on missing migration paths or downgrades.
  Map<String, Object?> migrateTo({
    required Map<String, Object?> rawData,
    required int targetVersion,
  }) {
    final current = GameSerialization.normalizeMap(rawData);
    var version = GameSerialization.readInt(current, 'version');

    if (version == targetVersion) {
      return current;
    }
    if (version > targetVersion) {
      throw SaveMigrationException(
        'Cannot downgrade save version $version to older target version '
        '$targetVersion.',
      );
    }

    var working = current;
    final visited = <int>{version};

    while (version < targetVersion) {
      final candidates =
          _migrations
              .where(
                (m) => m.fromVersion == version && m.toVersion <= targetVersion,
              )
              .toList()
            ..sort((a, b) => b.toVersion.compareTo(a.toVersion));

      if (candidates.isEmpty) {
        throw SaveMigrationException(
          'No SaveMigration path found from version $version to '
          '$targetVersion.',
        );
      }

      final chosen = candidates.first;
      if (!visited.add(chosen.toVersion)) {
        throw SaveMigrationException(
          'Cyclic SaveMigration detected at version ${chosen.toVersion}.',
        );
      }

      final migrated = chosen.migrate(GameSerialization.normalizeMap(working));
      working = GameSerialization.normalizeMap(migrated);
      working['version'] = chosen.toVersion;
      version = chosen.toVersion;
    }

    // Recompute checksum if the input carried one, reflecting the migrated data.
    if (working.containsKey('checksum')) {
      working['checksum'] = GameSerialization.computeChecksum(working);
    }
    return working;
  }
}

/// Versioned, integrity-checked snapshot of complete GameForge progression.
@immutable
class GameSaveData {
  /// Creates a [GameSaveData].
  GameSaveData({
    required this.version,
    required this.savedAt,
    this.score,
    this.health,
    this.levels,
    this.inventory,
    this.rewards,
    this.achievements,
    this.session,
    Map<String, Map<String, Object?>> modules = const {},
    Map<String, Object?> metadata = const {},
    this.checksum,
  }) : modules = Map<String, Map<String, Object?>>.unmodifiable({
         for (final entry in modules.entries)
           entry.key: Map<String, Object?>.unmodifiable(entry.value),
       }),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  /// Parses and validates a [GameSaveData] from raw storage [data].
  ///
  /// Verifies integrity checksum if `'checksum'` is present in [data] unless
  /// [verifyChecksum] is `false`.
  factory GameSaveData.fromJson(
    Map<String, Object?> data, {
    bool verifyChecksum = true,
  }) {
    final normalized = GameSerialization.normalizeMap(data);
    final version = GameSerialization.readInt(normalized, 'version');
    if (version < 1) {
      throw CorruptSaveDataException(
        'Save version must be >= 1 (got $version).',
      );
    }

    final savedChecksum = GameSerialization.readOptionalString(
      normalized,
      'checksum',
    );
    if (verifyChecksum && savedChecksum != null) {
      final computed = GameSerialization.computeChecksum(normalized);
      if (computed != savedChecksum) {
        throw CorruptSaveDataException(
          'Save data checksum mismatch (expected $savedChecksum, '
          'computed $computed).',
        );
      }
    }

    final savedAt = GameSerialization.readDateTime(normalized, 'savedAt');
    final payload = GameSerialization.readMap(normalized, 'payload');

    Map<String, Object?>? readOptionalSection(String key) {
      if (!payload.containsKey(key) || payload[key] == null) {
        return null;
      }
      return GameSerialization.readMap(payload, key);
    }

    final rawModules = GameSerialization.readMap(
      payload,
      'modules',
      defaultValue: const {},
    );
    final modules = <String, Map<String, Object?>>{};
    for (final entry in rawModules.entries) {
      final value = entry.value;
      if (value is! Map<Object?, Object?>) {
        throw CorruptSaveDataException(
          'Expected map for custom module "${entry.key}" in save payload.',
        );
      }
      modules[entry.key] = GameSerialization.normalizeMap(value);
    }

    final metadata = GameSerialization.readMap(
      normalized,
      'metadata',
      defaultValue: const {},
    );

    return GameSaveData(
      version: version,
      savedAt: savedAt,
      score: readOptionalSection('score'),
      health: readOptionalSection('health'),
      levels: readOptionalSection('levels'),
      inventory: readOptionalSection('inventory'),
      rewards: readOptionalSection('rewards'),
      achievements: readOptionalSection('achievements'),
      session: readOptionalSection('session'),
      modules: modules,
      metadata: metadata,
      checksum: savedChecksum,
    );
  }

  /// Schema version of this save snapshot.
  final int version;

  /// Timestamp when this snapshot was written.
  final DateTime savedAt;

  /// Serialized score module state, if present.
  final Map<String, Object?>? score;

  /// Serialized health module state, if present.
  final Map<String, Object?>? health;

  /// Serialized level module state, if present.
  final Map<String, Object?>? levels;

  /// Serialized inventory module state, if present.
  final Map<String, Object?>? inventory;

  /// Serialized reward module state, if present.
  final Map<String, Object?>? rewards;

  /// Serialized achievement module state, if present.
  final Map<String, Object?>? achievements;

  /// Serialized session module state, if present.
  final Map<String, Object?>? session;

  /// Serialized custom module snapshots keyed by [GameModule.id].
  final Map<String, Map<String, Object?>> modules;

  /// Optional developer metadata attached to the save snapshot.
  final Map<String, Object?> metadata;

  /// Integrity checksum computed at serialization time, if present.
  final String? checksum;

  /// Serializes this save snapshot into a JSON-compatible map including an
  /// integrity checksum when [includeChecksum] is `true`.
  Map<String, Object?> toJson({bool includeChecksum = true}) {
    final map = <String, Object?>{
      'version': version,
      'savedAt': savedAt.toUtc().toIso8601String(),
      'payload': <String, Object?>{
        if (score != null) 'score': GameSerialization.normalizeMap(score!),
        if (health != null) 'health': GameSerialization.normalizeMap(health!),
        if (levels != null) 'levels': GameSerialization.normalizeMap(levels!),
        if (inventory != null)
          'inventory': GameSerialization.normalizeMap(inventory!),
        if (rewards != null)
          'rewards': GameSerialization.normalizeMap(rewards!),
        if (achievements != null)
          'achievements': GameSerialization.normalizeMap(achievements!),
        if (session != null)
          'session': GameSerialization.normalizeMap(session!),
        if (modules.isNotEmpty)
          'modules': {
            for (final entry in modules.entries)
              entry.key: GameSerialization.normalizeMap(entry.value),
          },
      },
      'metadata': GameSerialization.normalizeMap(metadata),
    };
    if (includeChecksum) {
      map['checksum'] = GameSerialization.computeChecksum(map);
    }
    return map;
  }
}
