import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/family/data/supabase_cloud_family_gateway.dart';
import 'package:keepers/features/vault/data/weekly_reveal_cloud_gateway.dart';

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

  test('uploads ciphertext before publishing strict reveal metadata', () async {
    client.rpcValue = _remoteResponse;
    final encrypted = Uint8List.fromList(const [1, 2, 3]);

    await gateway.publish(_metadata, encrypted);

    expect(client.uploads, hasLength(1));
    expect(
      client.uploads.single.path,
      '11111111-1111-4111-8111-111111111111/'
      '22222222-2222-4222-8222-222222222222/'
      '33333333-3333-4333-8333-333333333333.keeper',
    );
    expect(client.uploads.single.bytes, orderedEquals(encrypted));
    expect(
      client.uploads.single.sha256,
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
    );
    expect(client.rpcCalls.single.function, 'publish_weekly_reveal_entry');
    expect(client.rpcCalls.single.params, {
      'p_entry_id': _metadata.id,
      'p_family_id': _metadata.familyId,
      'p_author_member_id': _metadata.authorId,
      'p_created_at': '2026-09-08T08:00:00.000Z',
      'p_format': 'photo',
      'p_storage_path': client.uploads.single.path,
      'p_blob_sha256': 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
      'p_blob_bytes': 3,
    });
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
  'storagePath': '$_familyId/$_authorId/$_entryId.keeper',
  'blobSha256': 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
  'blobBytes': 3,
  'state': 'pending',
};

final class _WeeklyClient
    implements SupabaseCloudClient, SupabaseWeeklyRevealClient {
  final uploads = <({String path, Uint8List bytes, String sha256})>[];
  final downloads = <String>[];
  final rpcCalls = <({String function, Map<String, Object?> params})>[];
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
    rpcCalls.add((function: function, params: params));
    return rpcValue;
  }

  @override
  Future<void> uploadWeeklyRevealBlob({
    required String path,
    required Uint8List bytes,
    required String sha256,
  }) async {
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
