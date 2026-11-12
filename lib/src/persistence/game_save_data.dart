import 'package:meta/meta.dart';

import '../core/game_exception.dart';
import '../utils/validators.dart';
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
  /// When [verifyChecksum] is `true`, verifies any present `'checksum'` field
  /// against [rawData] before executing migration steps so a downgraded
  /// version cannot bypass integrity verification. When [requireChecksum] is
  /// `true`, rejects payloads that omit `'checksum'`.
  ///
  /// When [rawData] already matches [targetVersion], returns a normalized copy.
  /// Throws [SaveIntegrityException] on integrity failure and
  /// [SaveMigrationException] on missing migration paths or downgrades.
  Map<String, Object?> migrateTo({
    required Map<String, Object?> rawData,
    required int targetVersion,
    bool verifyChecksum = true,
    bool requireChecksum = false,
    List<int>? secretKey,
    int maxDepth = GameSerialization.defaultMaxNestingDepth,
  }) {
    if (targetVersion < 1) {
      throw SaveMigrationException(
        'Target save version must be >= 1 (got $targetVersion).',
      );
    }
    if (secretKey != null && secretKey.isEmpty) {
      throw const GameConfigurationException(
        'Save signing key must not be empty.',
      );
    }

    final current = GameSerialization.normalizeMap(rawData, maxDepth: maxDepth);
    var version = GameSerialization.readInt(current, 'version');
    if (version < 1) {
      throw CorruptSaveDataException(
        'Save version must be >= 1 (got $version).',
      );
    }

    final savedChecksum = GameSerialization.readOptionalString(
      current,
      'checksum',
    );
    if (requireChecksum && (savedChecksum == null || savedChecksum.isEmpty)) {
      throw const SaveIntegrityException(
        'Save data is missing a required integrity checksum.',
      );
    }
    if (verifyChecksum && savedChecksum != null) {
      if (!GameSerialization.verifyChecksum(
        current,
        savedChecksum,
        secretKey: secretKey,
        maxDepth: maxDepth,
      )) {
        throw const SaveIntegrityException(
          'Save data integrity verification failed before migration.',
        );
      }
    }

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

      final migrated = chosen.migrate(
        GameSerialization.normalizeMap(working, maxDepth: maxDepth),
      );
      working = GameSerialization.normalizeMap(migrated, maxDepth: maxDepth);
      working['version'] = chosen.toVersion;
      version = chosen.toVersion;
    }

    // Recompute checksum after verifying the pre-migration payload.
    if (savedChecksum != null || requireChecksum) {
      working['checksum'] = GameSerialization.computeChecksum(
        working,
        secretKey: secretKey,
        maxDepth: maxDepth,
      );
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
    bool requireChecksum = false,
    List<int>? secretKey,
    int maxDepth = GameSerialization.defaultMaxNestingDepth,
  }) {
    if (secretKey != null && secretKey.isEmpty) {
      throw const GameConfigurationException(
        'Save signing key must not be empty.',
      );
    }

    final normalized = GameSerialization.normalizeMap(data, maxDepth: maxDepth);
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
    if (requireChecksum && (savedChecksum == null || savedChecksum.isEmpty)) {
      throw const SaveIntegrityException(
        'Save data is missing a required integrity checksum.',
      );
    }
    if (verifyChecksum && savedChecksum != null) {
      if (!GameSerialization.verifyChecksum(
        normalized,
        savedChecksum,
        secretKey: secretKey,
        maxDepth: maxDepth,
      )) {
        // Deliberately omit expected/computed digests to avoid exposing a
        // verification oracle.
        throw const SaveIntegrityException('Save data integrity check failed.');
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
      Validators.requireSafeId(
        entry.key,
        'module id',
        exceptionBuilder: (message) => CorruptSaveDataException(message),
      );
      final value = entry.value;
      if (value is! Map<Object?, Object?>) {
        throw CorruptSaveDataException(
          'Expected map for custom module "${entry.key}" in save payload.',
        );
      }
      modules[entry.key] = GameSerialization.normalizeMap(
        value,
        maxDepth: maxDepth,
      );
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
  /// integrity digest when [includeChecksum] is `true` (HMAC-SHA256 when
  /// [secretKey] is provided, or SHA-256 otherwise).
  Map<String, Object?> toJson({
    bool includeChecksum = true,
    List<int>? secretKey,
    int maxDepth = GameSerialization.defaultMaxNestingDepth,
  }) {
    if (secretKey != null && secretKey.isEmpty) {
      throw const GameConfigurationException(
        'Save signing key must not be empty.',
      );
    }
    final map = <String, Object?>{
      'version': version,
      'savedAt': savedAt.toUtc().toIso8601String(),
      'payload': <String, Object?>{
        if (score != null)
          'score': GameSerialization.normalizeMap(score!, maxDepth: maxDepth),
        if (health != null)
          'health': GameSerialization.normalizeMap(health!, maxDepth: maxDepth),
        if (levels != null)
          'levels': GameSerialization.normalizeMap(levels!, maxDepth: maxDepth),
        if (inventory != null)
          'inventory': GameSerialization.normalizeMap(
            inventory!,
            maxDepth: maxDepth,
          ),
        if (rewards != null)
          'rewards': GameSerialization.normalizeMap(
            rewards!,
            maxDepth: maxDepth,
          ),
        if (achievements != null)
          'achievements': GameSerialization.normalizeMap(
            achievements!,
            maxDepth: maxDepth,
          ),
        if (session != null)
          'session': GameSerialization.normalizeMap(
            session!,
            maxDepth: maxDepth,
          ),
        if (modules.isNotEmpty)
          'modules': {
            for (final entry in modules.entries)
              entry.key: GameSerialization.normalizeMap(
                entry.value,
                maxDepth: maxDepth,
              ),
          },
      },
      'metadata': GameSerialization.normalizeMap(metadata, maxDepth: maxDepth),
    };
    if (includeChecksum) {
      map['checksum'] = GameSerialization.computeChecksum(
        map,
        secretKey: secretKey,
        maxDepth: maxDepth,
      );
    }
    return map;
  }
}
