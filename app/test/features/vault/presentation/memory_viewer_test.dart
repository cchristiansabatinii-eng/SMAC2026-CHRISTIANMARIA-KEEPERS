import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/features/vault/presentation/memory_viewer.dart';

void main() {
  testWidgets('text memory renders metadata, content, and non-empty caption', (
    tester,
  ) async {
    final playback = _FakePlayback();
    await tester.pumpWidget(
      _viewer(
        OpenedMemory(
          metadata: _metadata(format: MemoryFormat.text),
          payload: const EntryPayload(
            format: MemoryFormat.text,
            primaryBytes: null,
            text: 'Only in memory',
            caption: 'A quiet morning',
            mediaExtension: null,
            mediaDurationMs: null,
          ),
        ),
        playback,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ONLY IN MEMORY'), findsOneWidget);
    expect(find.bySemanticsLabel('Only in memory'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('A quiet morning'), findsOneWidget);
    expect(find.text('Created 2026-09-01'), findsOneWidget);
    expect(find.text('Weekly Reveal'), findsOneWidget);
  });

  testWidgets('empty caption is omitted from the viewer', (tester) async {
    await tester.pumpWidget(
      _viewer(
        OpenedMemory(
          metadata: _metadata(format: MemoryFormat.text),
          payload: const EntryPayload(
            format: MemoryFormat.text,
            primaryBytes: null,
            text: 'Uncaptioned',
            caption: '   ',
            mediaExtension: null,
            mediaDurationMs: null,
          ),
        ),
        _FakePlayback(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('memory-caption')), findsNothing);
  });

  testWidgets('photo memory renders decrypted bytes in memory', (tester) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      _viewer(
        OpenedMemory(
          metadata: _metadata(format: MemoryFormat.photo),
          payload: EntryPayload(
            format: MemoryFormat.photo,
            primaryBytes: Uint8List.fromList(bytes),
            text: null,
            caption: null,
            mediaExtension: 'png',
            mediaDurationMs: null,
          ),
        ),
        _FakePlayback(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).semanticLabel,
      'Photo memory',
    );
  });

  testWidgets('voice memory plays bytes and stops on dispose', (tester) async {
    final playback = _FakePlayback();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await tester.pumpWidget(
      _viewer(
        OpenedMemory(
          metadata: _metadata(format: MemoryFormat.voice),
          payload: EntryPayload(
            format: MemoryFormat.voice,
            primaryBytes: bytes,
            text: null,
            caption: null,
            mediaExtension: 'm4a',
            mediaDurationMs: 7000,
          ),
        ),
        playback,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('00:07'), findsOneWidget);
    await tester.tap(find.text('Play voice memory'));
    await tester.pump();
    expect(playback.playedBytes.single, bytes);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(playback.stops, 1);
  });

  testWidgets('unavailable memory exposes only the safe message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _viewer(
        const UnavailableMemory('This memory cannot be opened safely.'),
        _FakePlayback(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This memory cannot be opened safely.'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });
}

Widget _viewer(MemoryOpenResult result, AudioPlaybackAdapter playback) =>
    MaterialApp(
      theme: KeepersTheme.dark(),
      home: MemoryViewer(memory: Future.value(result), playback: playback),
    );

VaultEntryMetadata _metadata({required MemoryFormat format}) =>
    VaultEntryMetadata(
      id: 'entry-${format.name}',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 9, 1),
      format: format,
      privacy: PrivacyTier.reveal,
      blobRef: 'entries/blobs/entry-${format.name}.keeper',
      state: 'pending',
    );

final class _FakePlayback implements AudioPlaybackAdapter {
  final playedBytes = <Uint8List>[];
  var stops = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> playBytes(Uint8List bytes) async {
    playedBytes.add(bytes);
  }

  @override
  Future<void> playFile(String path) async {
    throw UnsupportedError('Vault playback is byte-only');
  }

  @override
  Future<void> stop() async {
    stops += 1;
  }
}
