import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameforge/gameforge.dart';

class _TestMigration implements SaveMigration {
  _TestMigration({
    required this.fromVersion,
    required this.toVersion,
    required this.onMigrate,
  });

  @override
  final int fromVersion;

  @override
  final int toVersion;

  final Map<String, Object?> Function(Map<String, Object?> data) onMigrate;

  @override
  Map<String, Object?> migrate(Map<String, Object?> data) => onMigrate(data);
}

class _UnboundedCustomStorage implements GameStorage {
  _UnboundedCustomStorage(this.payload);

  final Map<String, Object?> payload;

  @override
  Future<void> clear() async {}

  @override
  Future<void> delete(String key) async {}

  @override
  Future<Map<String, Object?>?> read(String key) async => payload;

  @override
  Future<void> save(String key, Map<String, Object?> data) async {}
}

void main() {
  group('GameSecurity cryptography & constant-time utilities', () {
    test('SHA-256 matches official NIST FIPS 180-4 / RFC 6234 vectors', () {
      expect(
        GameSecurity.sha256Utf8(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        GameSecurity.sha256Utf8('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        GameSecurity.sha256Utf8(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );

      final oneMillionAs = Uint8List(1000000)..fillRange(0, 1000000, 0x61);
      expect(
        GameSecurity.sha256Hex(oneMillionAs),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });

    test('HMAC-SHA256 matches official RFC 4231 test vectors', () {
      // RFC 4231 Test Case 1: 20 bytes of 0x0b, "Hi There"
      expect(
        GameSecurity.hmacSha256Hex(
          key: List<int>.filled(20, 0x0b),
          data: utf8.encode('Hi There'),
        ),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );

      // RFC 4231 Test Case 2: "Jefe", "what do ya want for nothing?"
      expect(
        GameSecurity.hmacSha256Hex(
          key: utf8.encode('Jefe'),
          data: utf8.encode('what do ya want for nothing?'),
        ),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );

      // RFC 4231 Test Case 6: 131-byte key (tests key > blockSize hashing)
      expect(
        GameSecurity.hmacSha256Hex(
          key: List<int>.filled(131, 0xaa),
          data: utf8.encode(
            'Test Using Larger Than Block-Size Key - Hash Key First',
          ),
        ),
        '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
      );
    });

    test('rejects empty HMAC keys and invalid byte values', () {
      expect(
        () => GameSecurity.hmacSha256Bytes(key: const [], data: [1, 2]),
        throwsArgumentError,
      );
      expect(() => GameSecurity.sha256Bytes([0, 256]), throwsRangeError);
      expect(() => GameSecurity.sha256Bytes([-1]), throwsRangeError);
    });

    test('constant-time comparisons, random tokens, and zeroBytes work', () {
      expect(GameSecurity.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(GameSecurity.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(GameSecurity.constantTimeEquals([1, 2], [1, 2, 0]), isFalse);

      expect(GameSecurity.constantTimeHexEquals('a1b2c3', 'A1B2C3'), isTrue);
      expect(GameSecurity.constantTimeHexEquals('', ''), isFalse);
      expect(GameSecurity.constantTimeHexEquals('zzzz', 'zzzz'), isFalse);
      expect(GameSecurity.constantTimeHexEquals('00ff', '00fe'), isFalse);

      final t1 = GameSecurity.generateSecureToken();
      final t2 = GameSecurity.generateSecureToken();
      expect(t1, hasLength(64));
      expect(t2, hasLength(64));
      expect(t1, isNot(equals(t2)));

      final keyBuffer = Uint8List.fromList([10, 20, 30, 40]);
      GameSecurity.zeroBytes(keyBuffer);
      expect(keyBuffer, everyElement(0));
    });
  });

  group('Save integrity & anti-tampering', () {
    test(
      'rejects missing or null checksums by default on GameForge.load()',
      () async {
        final storage = MemoryGameStorage();
        final game = GameForge(storage: storage);
        await game.initialize();
        game.score.add(100);
        await game.save();

        // Attack: strip the checksum field completely or set it to null.
        final stripped = (await storage.read(game.config.saveKey))!
          ..remove('checksum');
        await storage.save('stripped_slot', stripped);

        await expectLater(
          game.load(key: 'stripped_slot'),
          throwsA(isA<SaveIntegrityException>()),
        );

        final nullChecksum = (await storage.read(game.config.saveKey))!
          ..['checksum'] = null;
        await storage.save('null_slot', nullChecksum);

        await expectLater(
          game.load(key: 'null_slot'),
          throwsA(isA<SaveIntegrityException>()),
        );

        // Score remained untouched after rejected loads.
        expect(game.score.currentScore, 100);
        await game.dispose();
      },
    );

    test(
      'prevents version-downgrade migration bypass when save is tampered',
      () async {
        final storage = MemoryGameStorage();
        var migrationCalls = 0;
        final migration = _TestMigration(
          fromVersion: 1,
          toVersion: 2,
          onMigrate: (data) {
            migrationCalls++;
            return data;
          },
        );

        final gameV2 = GameForge(
          config: const GameConfig(saveVersion: 2),
          storage: storage,
          saveMigrations: [migration],
        );
        await gameV2.initialize();
        gameV2.score.add(50);
        await gameV2.save();

        // Attacker edits score AND downgrades version from 2 -> 1 hoping
        // SaveMigrationRunner will re-compute a valid checksum after migrating.
        final tampered = (await storage.read(gameV2.config.saveKey))!;
        tampered['version'] = 1;
        final payload = Map<String, Object?>.from(
          tampered['payload']! as Map<Object?, Object?>,
        );
        final score = Map<String, Object?>.from(
          payload['score']! as Map<Object?, Object?>,
        );
        score['currentScore'] = 999999;
        payload['score'] = score;
        tampered['payload'] = payload;
        await storage.save(gameV2.config.saveKey, tampered);

        await expectLater(
          gameV2.load(),
          throwsA(isA<SaveIntegrityException>()),
        );
        expect(migrationCalls, 0);
        expect(gameV2.score.currentScore, 50);
        await gameV2.dispose();
      },
    );

    test(
      'supports keyed HMAC-SHA256 saves and leaks no digest oracle on mismatch',
      () async {
        final storage = MemoryGameStorage();
        final secretKey = utf8.encode('top-secret-hmac-key-32-bytes-ok!');
        final wrongKey = utf8.encode('wrong-secret-hmac-key-do-not-use');

        final writer = GameForge(storage: storage, saveSigningKey: secretKey);
        await writer.initialize();
        writer.score.add(300);
        await writer.save();
        await writer.dispose();

        // Unsigned/unkeyed SHA-256 forgery is rejected by keyed reader.
        final stored = (await storage.read('gameforge_save'))!;
        final storedHmac = stored['checksum']! as String;
        final unkeyedForgery = Map<String, Object?>.of(stored)
          ..['checksum'] = GameSerialization.computeChecksum(stored);

        final keyedReader = GameForge(
          storage: storage,
          saveSigningKey: secretKey,
        );
        await keyedReader.initialize();
        await storage.save('forged_unkeyed', unkeyedForgery);

        await expectLater(
          keyedReader.load(key: 'forged_unkeyed'),
          throwsA(
            isA<SaveIntegrityException>().having(
              (e) => e.message,
              'message',
              allOf(
                isNot(contains(storedHmac)),
                isNot(contains(unkeyedForgery['checksum']! as String)),
              ),
            ),
          ),
        );

        // Wrong HMAC key is rejected too.
        final wrongKeyReader = GameForge(
          storage: storage,
          saveSigningKey: wrongKey,
        );
        await wrongKeyReader.initialize();
        await expectLater(
          wrongKeyReader.load(),
          throwsA(isA<SaveIntegrityException>()),
        );
        await wrongKeyReader.dispose();

        // Matching key loads accurately.
        expect(await keyedReader.load(), isTrue);
        expect(keyedReader.score.currentScore, 300);
        await keyedReader.dispose();
      },
    );

    test('validates saveSigningKey and supports legacy opt-out', () async {
      expect(
        () => GameForge(saveSigningKey: const []),
        throwsA(isA<GameConfigurationException>()),
      );
      expect(
        () => GameForge(saveSigningKey: const [300]),
        throwsA(isA<GameConfigurationException>()),
      );

      final storage = MemoryGameStorage();
      final legacyWriter = GameForge(storage: storage);
      await legacyWriter.initialize();
      legacyWriter.score.add(42);
      final raw = legacyWriter.createSaveData().toJson(includeChecksum: false);
      await storage.save('legacy', raw);
      await legacyWriter.dispose();

      final legacyReader = GameForge(
        config: const GameConfig(requireSaveIntegrity: false),
        storage: storage,
      );
      await legacyReader.initialize();
      expect(await legacyReader.load(key: 'legacy'), isTrue);
      expect(legacyReader.score.currentScore, 42);
      await legacyReader.dispose();
    });
  });

  group('Deserialization DoS & cycle protections', () {
    test('rejects oversized JSON and excessively nested payloads', () {
      expect(
        () => GameSerialization.decodeJson('{"a":"1234567890"}', maxBytes: 8),
        throwsA(isA<CorruptSaveDataException>()),
      );
      expect(
        () => GameSerialization.encodeJson({'a': '1234567890'}, maxBytes: 8),
        throwsA(isA<PersistenceException>()),
      );

      // Deep JSON nested beyond limit fails during pre-scan before jsonDecode.
      final deepJson = '${'{"a":' * 70}1${'}' * 70}';
      expect(
        () => GameSerialization.decodeJson(deepJson, maxDepth: 64),
        throwsA(isA<CorruptSaveDataException>()),
      );
    });

    test('detects cyclic maps/lists while allowing shared DAG nodes', () {
      final sharedEmpty = <String, Object?>{};
      final dag = <String, Object?>{
        'first': sharedEmpty,
        'second': sharedEmpty,
      };
      final normalizedDag = GameSerialization.normalizeMap(dag);
      expect(normalizedDag['first'], isEmpty);
      expect(normalizedDag['second'], isEmpty);

      final cyclicMap = <String, Object?>{};
      cyclicMap['self'] = cyclicMap;
      expect(
        () => GameSerialization.normalizeMap(cyclicMap),
        throwsA(isA<CorruptSaveDataException>()),
      );

      final cyclicList = <Object?>[];
      cyclicList.add(cyclicList);
      expect(
        () => GameSerialization.computeChecksum({'loop': cyclicList}),
        throwsA(isA<CorruptSaveDataException>()),
      );
    });

    test('rejects non-finite doubles and non-string keys cleanly', () {
      expect(
        () => GameSerialization.normalizeMap({'bad': double.nan}),
        throwsA(isA<CorruptSaveDataException>()),
      );
      expect(
        () => GameSerialization.readInt({'count': double.infinity}, 'count'),
        throwsA(isA<CorruptSaveDataException>()),
      );
      expect(
        () => GameSerialization.computeChecksum({
          'nested': <Object?, Object?>{123: 'bad_key'},
        }),
        throwsA(isA<CorruptSaveDataException>()),
      );
    });

    test(
      'GameForge.load enforces configured maxSaveBytes on custom storage',
      () async {
        final bigStorage = _UnboundedCustomStorage({
          'version': 1,
          'savedAt': DateTime.utc(2026).toIso8601String(),
          'payload': {'blob': 'x' * 500},
          'metadata': <String, Object?>{},
        });
        final game = GameForge(
          config: const GameConfig(maxSaveBytes: 128),
          storage: bigStorage,
        );
        await game.initialize();
        await expectLater(
          game.load(),
          throwsA(isA<CorruptSaveDataException>()),
        );
        await game.dispose();
      },
    );
  });

  group('Key validation, path traversal guards, & numeric overflow limits', () {
    test('rejects unsafe storage keys and identifiers', () async {
      const badKeys = [
        '',
        '   ',
        ' padded ',
        '../escape',
        r'..\escape',
        '/etc/passwd',
        '.hidden',
        'bad\x00key',
        'line\nbreak',
      ];
      for (final key in badKeys) {
        expect(
          () => Validators.requireSafeKey(key, 'key'),
          throwsA(isA<GameConfigurationException>()),
          reason: 'Should reject unsafe key "$key"',
        );
      }

      final storage = MemoryGameStorage();
      await expectLater(
        storage.save('../bad', {'a': 1}),
        throwsA(isA<PersistenceException>()),
      );
      await expectLater(
        storage.read('../bad'),
        throwsA(isA<PersistenceException>()),
      );
      await expectLater(
        storage.delete('../bad'),
        throwsA(isA<PersistenceException>()),
      );

      expect(
        () => GameSessionManager(historyStorageKey: '../history'),
        throwsA(isA<GameConfigurationException>()),
      );
    });

    test('blocks score, combo, reward, and achievement integer overflows', () {
      final score = ScoreManager(
        rules: const ScoreRules(
          maxScore: ScoreRules.maxSafeScore,
          clampOnOverflow: false,
        ),
      );
      score.setMultiplier(10.0);
      expect(
        () => score.add(GameSecurity.maxSafeInteger),
        throwsA(isA<ScoreValidationException>()),
      );
      score.incrementCombo(by: 1);
      expect(
        () => score.incrementCombo(by: GameSecurity.maxSafeInteger),
        throwsA(isA<ScoreValidationException>()),
      );

      final rewards = RewardManager();
      rewards.grant(GameReward.coins(100));
      expect(
        () => rewards.grant(GameReward.coins(GameSecurity.maxSafeInteger)),
        throwsA(isA<RewardException>()),
      );
      expect(rewards.coinBalance, 100);

      expect(
        () => rewards.fromSaveData({
          'coinBalance': 500,
          'totalCoinsEarned': 100,
          'totalExperience': 0,
        }),
        throwsA(isA<SaveValidationException>()),
      );

      final achievements = AchievementManager(
        achievements: [
          const Achievement(id: 'big', name: 'Big', targetValue: 10),
        ],
      );
      achievements.increment('big', amount: 5);
      expect(
        () =>
            achievements.increment('big', amount: GameSecurity.maxSafeInteger),
        throwsA(isA<AchievementException>()),
      );
    });

    test(
      'validates audio asset identifiers, volume bounds, and session stats',
      () async {
        final audio = NoopGameAudioService();
        await expectLater(
          audio.playMusic('../secret.mp3'),
          throwsA(isA<GameConfigurationException>()),
        );
        await expectLater(
          audio.playSfx('sfx/coin.wav', volume: double.nan),
          throwsA(isA<GameConfigurationException>()),
        );
        await expectLater(
          audio.playSfx('sfx/coin.wav', volume: 1.5),
          throwsA(isA<GameConfigurationException>()),
        );
        await audio.playMusic('audio/bgm.mp3', volume: 0.75);
        await audio.dispose();

        final session = GameSessionManager(maxHistoryEntries: 5);
        session.startSession(sessionId: 'sess_1');
        expect(
          () => session.recordStat('accuracy', double.nan),
          throwsA(isA<SessionException>()),
        );
        expect(
          () => session.setStat('bad\x00stat', 1),
          throwsA(isA<SessionException>()),
        );
        await session.dispose();
      },
    );
  });
}
