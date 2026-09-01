import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/features/vault/presentation/observatory_screen.dart';
import 'package:keepers/features/vault/presentation/vault_list.dart';

const _identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Sabati',
  familyKeyRef: 'family-key',
  memberId: 'member-1',
  memberName: 'Chris',
  memberKeyRef: 'member-key',
  colorToken: 'ochre',
);

void main() {
  testWidgets('solo Observatory has one real member and an accessible vault', (
    tester,
  ) async {
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(MemoryFormat.photo, 2),
          _metadata(MemoryFormat.text, 1),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Current member Chris'), findsOneWidget);
    expect(find.bySemanticsLabel('Family member'), findsOneWidget);
    expect(find.text('Add a memory'), findsOneWidget);
    expect(find.text('Photo memory'), findsOneWidget);
    expect(find.text('Text memory'), findsOneWidget);
    expect(find.textContaining('Mother'), findsNothing);
    expect(find.textContaining('Father'), findsNothing);
  });

  testWidgets('daylight and 1.4x fallback list render without clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _observatory(
        entries: List.generate(
          6,
          (index) => _metadata(MemoryFormat.values[index % 3], 6 - index),
        ),
        theme: KeepersTheme.daylight(),
        mediaQuery: const MediaQueryData(
          textScaler: TextScaler.linear(1.4),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(VaultList), findsOneWidget);
    expect(find.bySemanticsLabel('Add a memory'), findsOneWidget);
  });

  testWidgets('vault error and empty states stay labeled and retryable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWithValue(
          AsyncValue.error(
            StateError('database unavailable'),
            StackTrace.empty,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vault unavailable.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.pumpWidget(_observatory(entries: const []));
    await tester.pumpAndSettle();
    expect(find.text('No memories yet.'), findsOneWidget);
  });

  testWidgets('capture success refreshes the vault before seal feedback', (
    tester,
  ) async {
    final saved = _entryMetadata(MemoryFormat.text, 3);
    final refreshed = _metadata(MemoryFormat.text, 3);
    final refresh = Completer<List<VaultEntryMetadata>>();
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var loads = 0;
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWith((ref) async {
          loads += 1;
          return loads == 1 ? const [] : refresh.future;
        }),
        showCapture: (_) async => saved,
        theme: _motionTheme(),
        mediaQuery: const MediaQueryData(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a memory'));
    await tester.pump();
    expect(find.bySemanticsLabel('Memory sealed'), findsNothing);
    expect(haptics, isEmpty);
    refresh.complete([refreshed]);
    await tester.pump();

    expect(loads, 2);
    expect(find.text('Text memory'), findsOneWidget);
    final actor = find.byKey(const ValueKey('seal-actor-entry-text-3'));
    final member = find.byKey(const ValueKey('orbit-member-node'));
    final mark = find.byKey(const ValueKey('orbit-memory-entry-text-3'));
    final badge = find.byKey(const ValueKey('seal-badge-entry-text-3'));
    expect(actor, findsOneWidget);
    expect(
      find.descendant(of: actor, matching: find.byIcon(Icons.notes_rounded)),
      findsOneWidget,
    );
    expect(tester.getCenter(actor), tester.getCenter(member));
    expect(mark, findsNothing);
    expect(badge, findsNothing);
    expect(haptics, isEmpty);

    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getCenter(actor), isNot(tester.getCenter(member)));
    expect(mark, findsNothing);
    expect(badge, findsNothing);
    expect(haptics, isEmpty);

    await tester.pump(const Duration(milliseconds: 250));
    expect(mark, findsNothing);
    expect(badge, findsOneWidget);
    expect(find.bySemanticsLabel('Memory sealed'), findsOneWidget);
    expect(haptics, isEmpty);

    await tester.pump(const Duration(milliseconds: 249));
    expect(haptics, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(mark, findsOneWidget);
    expect(actor, findsNothing);
    expect(haptics, hasLength(1));
    await tester.pump(const Duration(milliseconds: 79));
    expect(haptics, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(haptics, hasLength(2));
  });

  testWidgets('capture cancellation neither refreshes nor seals', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWith((ref) async {
          loads += 1;
          return const [];
        }),
        showCapture: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(find.bySemanticsLabel('Memory sealed'), findsNothing);
  });
}

Widget _observatory({
  required List<VaultEntryMetadata> entries,
  ThemeData? theme,
  MediaQueryData? mediaQuery,
}) => _observatoryWithOverride(
  vaultEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
  theme: theme,
  mediaQuery: mediaQuery,
);

Widget _observatoryWithOverride(
  dynamic override, {
  ThemeData? theme,
  MediaQueryData? mediaQuery,
  Future<EntryMetadata?> Function(BuildContext)? showCapture,
}) => ProviderScope(
  overrides: [override],
  child: MaterialApp(
    theme: theme ?? KeepersTheme.dark(),
    home: MediaQuery(
      data: mediaQuery ?? const MediaQueryData(disableAnimations: true),
      child: ObservatoryScreen(identity: _identity, showCapture: showCapture),
    ),
  ),
);

ThemeData _motionTheme() {
  final theme = KeepersTheme.dark();
  final tokens = theme.extension<ObservatoryTokens>()!;
  return theme.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      tokens.copyWith(idleDrift: 0, sealDuration: const Duration(seconds: 1)),
    ],
  );
}

VaultEntryMetadata _metadata(MemoryFormat format, int day) =>
    VaultEntryMetadata(
      id: 'entry-${format.name}-$day',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 8, day),
      format: format,
      privacy: PrivacyTier.reveal,
      blobRef: 'entries/blobs/entry-${format.name}-$day.keeper',
      state: 'pending',
    );

EntryMetadata _entryMetadata(MemoryFormat format, int day) => EntryMetadata(
  id: 'entry-${format.name}-$day',
  familyId: 'family-1',
  authorId: 'member-1',
  createdAt: DateTime.utc(2026, 8, day),
  format: format,
  privacy: PrivacyTier.reveal,
  blobRef: 'entries/blobs/entry-${format.name}-$day.keeper',
);
