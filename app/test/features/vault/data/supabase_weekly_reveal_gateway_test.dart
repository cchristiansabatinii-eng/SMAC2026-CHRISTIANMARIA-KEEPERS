import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/family/data/supabase_cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/vault/data/weekly_reveal_cloud_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late _WeeklyClient client;
  late WeeklyRevealCloudGateway gateway;

  setUp(() {
    client = _WeeklyClient();
    gateway = SupabaseCloudFamilyGateway(
      client,
      emailRedirectTo: 'https://example.supabase.co/functions/v1/auth',
    ) as WeeklyRevealCloudGateway;
  });

  tearDown(() => client.dispose());

  test('exact publish retry probes RPC and skips ciphertext upload', () async {
    client.rpcOutcomes.add(_remoteResponse);
    final encrypted = Uint8List.fromList(const [1, 2, 3]);

    await gateway.publish(_metadata, encrypted);

    expect(client.operations, ['rpc:publish_weekly_reveal_entry']);
    expect(client.uploads, isEmpty);
    expect(client.rpcCalls, hasLength(1));
    expect(client.rpcCalls.single.function, 'publish_weekly_reveal_entry');
    expect(client.rpcCalls.single.params, _publishParams);
  });

  test(
    'first publish probes RPC, creates ciphertext, then publishes metadata',
    () async {
      client.rpcOutcomes.addAll([
        const _RpcError(
          PostgrestException(
            code: 'P0001',
            message: 'OBJECT_NOT_FOUND',
            details: 'Bad Request',
          ),
        ),
        _remoteResponse,
      ]);
      final encrypted = Uint8List.fromList(const [1, 2, 3]);

      await gateway.publish(_metadata, encrypted);

      expect(client.operations, [
        'rpc:publish_weekly_reveal_entry',
        'upload:$_storagePath',
        'rpc:publish_weekly_reveal_entry',
      ]);
      expect(client.rpcCalls, hasLength(2));
      expect(
        client.rpcCalls.map((call) => call.params),
        everyElement(_publishParams),
      );
      expect(client.uploads, hasLength(1));
      expect(client.uploads.single.path, _storagePath);
      expect(client.uploads.single.bytes, orderedEquals(encrypted));
      expect(
        client.uploads.single.sha256,
        'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
      );
    },
  );

  test('only the exact missing-object RPC error permits an upload', () async {
    final errors = <PostgrestException>[
      const PostgrestException(
        code: 'OBJECT_NOT_FOUND',
        message: 'OBJECT_NOT_FOUND',
      ),
      const PostgrestException(code: 'P0001', message: 'object_not_found'),
      const PostgrestException(code: 'P0001', message: 'raw OBJECT_NOT_FOUND'),
      const PostgrestException(
        code: 'P0001',
        message: 'OBJECT_NOT_FOUND',
        details: 'raw detail',
      ),
      const PostgrestException(
        code: 'P0001',
        message: 'OBJECT_NOT_FOUND',
        hint: 'raw hint',
      ),
    ];

    for (final error in errors) {
      client.rpcOutcomes.add(_RpcError(error));

      await expectLater(
        gateway.publish(_metadata, Uint8List.fromList(const [1, 2, 3])),
        throwsA(
          isA<InvitationFailure>().having(
            (failure) => failure.code,
            'code',
            InvitationFailureCode.unknown,
          ),
        ),
        reason: error.toString(),
      );

      expect(client.uploads, isEmpty, reason: error.toString());
      client.operations.clear();
      client.rpcCalls.clear();
    }
  });

  test(
    'lists and downloads only the strict encrypted reveal projection',
    () async {
      client.rpcValue = [_remoteResponse];
      client.downloadValue = Uint8List.fromList(const [1, 2, 3]);

      final entries = await gateway.list(_metadata.familyId);
      final downloaded = await gateway.download(entries.single);

      expect(entries.single.metadata, _metadata);
      expect(entries.single.state, 'pending');
      expect(entries.single.blobBytes, 3);
      expect(downloaded, Uint8List.fromList(const [1, 2, 3]));
      expect(client.downloads, [entries.single.storagePath]);
    },
  );

  test('forwards family-scoped metadata change events', () async {
    final event = expectLater(gateway.watch(_metadata.familyId), emits(null));

    client.events.add(_metadata.familyId);

    await event;
  });
}

const _familyId = '11111111-1111-4111-8111-111111111111';
const _authorId = '22222222-2222-4222-8222-222222222222';
const _entryId = '33333333-3333-4333-8333-333333333333';
const _storagePath = '$_familyId/$_authorId/$_entryId.keeper';
final _createdAt = DateTime.utc(2026, 9, 8, 8);
final _metadata = EntryMetadata(
  id: _entryId,
  familyId: _familyId,
  authorId: _authorId,
  createdAt: _createdAt,
  format: MemoryFormat.photo,
  privacy: PrivacyTier.reveal,
);
final _remoteResponse = <String, Object?>{
  'entryId': _entryId,
  'familyId': _familyId,
  'authorId': _authorId,
  'createdAt': '2026-09-08T08:00:00.000Z',
  'format': 'photo',
  'storagePath': _storagePath,
  'blobSha256': 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
  'blobBytes': 3,
  'state': 'pending',
};
final _publishParams = <String, Object?>{
  'p_entry_id': _metadata.id,
  'p_family_id': _metadata.familyId,
  'p_author_member_id': _metadata.authorId,
  'p_created_at': '2026-09-08T08:00:00.000Z',
  'p_format': 'photo',
  'p_storage_path': _storagePath,
  'p_blob_sha256': 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
  'p_blob_bytes': 3,
};

final class _RpcError {
  const _RpcError(this.error);

  final Object error;
}

final class _WeeklyClient
    implements SupabaseCloudClient, SupabaseWeeklyRevealClient {
  final uploads = <({String path, Uint8List bytes, String sha256})>[];
  final downloads = <String>[];
  final rpcCalls = <({String function, Map<String, Object?> params})>[];
  final operations = <String>[];
  final rpcOutcomes = <Object?>[];
  final events = StreamController<String>.broadcast(sync: true);
  Object? rpcValue;
  Uint8List downloadValue = Uint8List(0);

  Future<void> dispose() => events.close();

  @override
  String? get authenticatedAccountId => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  @override
  String? get authenticatedEmail => 'member@example.com';

  @override
  Future<void> requestEmailOtp(
    String email, {
    required String emailRedirectTo,
  }) async {}

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {}

  @override
  Future<Object?> rpc(
    String function, {
    required Map<String, Object?> params,
  }) async {
    operations.add('rpc:$function');
    rpcCalls.add((function: function, params: params));
    final outcome = rpcOutcomes.isEmpty ? rpcValue : rpcOutcomes.removeAt(0);
    if (outcome case _RpcError(:final error)) {
      throw error;
    }
    return outcome;
  }

  @override
  Future<void> uploadWeeklyRevealBlob({
    required String path,
    required Uint8List bytes,
    required String sha256,
  }) async {
    operations.add('upload:$path');
    uploads.add((path: path, bytes: Uint8List.fromList(bytes), sha256: sha256));
  }

  @override
  Future<Uint8List> downloadWeeklyRevealBlob(String path) async {
    downloads.add(path);
    return Uint8List.fromList(downloadValue);
  }

  @override
  Stream<void> watchWeeklyRevealEntries(String familyId) => events.stream
      .where((changedFamilyId) => changedFamilyId == familyId)
      .map((_) {});
}
