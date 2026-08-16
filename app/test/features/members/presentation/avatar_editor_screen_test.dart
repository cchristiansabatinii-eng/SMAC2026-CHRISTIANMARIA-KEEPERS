import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/members/application/avatar_editor_controller.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/avatar_editor_screen.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

void main() {
  const identity = LocalIdentity(
    familyId: 'family-1',
    familyName: 'The Keepers',
    familyKeyRef: 'family-key',
    memberId: 'member-1',
    memberName: 'Sam',
    memberKeyRef: 'member-key',
    colorToken: 'sage',
    avatar: AvatarConfig.defaults(seed: 'member-1'),
  );

  group('AvatarEditorScreen', () {
    testWidgets('shows the profile editor and every Humation category', (
      tester,
    ) async {
      await _pumpEditor(tester, identity: identity);

      expect(find.text('YOUR PROFILE'), findsOneWidget);
      expect(find.text('Choose your avatar'), findsOneWidget);
      expect(find.text('Shown on your family wheel.'), findsOneWidget);
      for (final label in [
        'Head',
        'Body',
        'Bottom',
        'Item',
        'Glasses',
        'Colors',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Looks'), findsNothing);
      expect(find.text('Face'), findsNothing);
      expect(find.text('Hair'), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('avatar-editor-preview'))),
        const Size(132, 132),
      );
      expect(find.byType(KeepersAvatar), findsAtLeastNWidgets(1));
      expect(
        tester.getSize(find.byKey(const Key('avatar-category-head'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        find.bySemanticsLabel(RegExp('avatar option', caseSensitive: false)),
        findsWidgets,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save avatar'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('semantic part selection updates the live preview only', (
      tester,
    ) async {
      var saves = 0;
      await _pumpEditor(
        tester,
        identity: identity,
        onSave: ({required memberId, required avatar}) async => saves++,
      );

      final option = avatarCatalog.optionsFor(AvatarCategory.head).first;
      final before = tester
          .widget<KeepersAvatar>(
            find.byKey(const Key('avatar-editor-preview-artwork')),
          )
          .config;
      final semantics = tester.ensureSemantics();
      tester.semantics.tap(
        find.semantics.byLabel('${option.label} avatar option'),
      );
      await tester.pump();
      final preview = tester.widget<KeepersAvatar>(
        find.byKey(const Key('avatar-editor-preview-artwork')),
      );
      expect(preview.config, option.apply(identity.avatar));
      expect(preview.config, isNot(before));
      expect(saves, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save avatar'),
            )
            .onPressed,
        isNotNull,
      );
      semantics.dispose();
    });

    testWidgets('color options show a swatch and update the live preview', (
      tester,
    ) async {
      await _pumpEditor(tester, identity: identity);
      await tester.tap(find.byKey(const Key('avatar-category-colors')));
      await tester.pump();

      final color = avatarCatalog.optionsFor(AvatarCategory.colors).first;
      expect(
        find.byKey(Key('avatar-color-swatch-${color.id}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('avatar-option-${color.id}')));
      await tester.pump();

      expect(
        tester
            .widget<KeepersAvatar>(
              find.byKey(const Key('avatar-editor-preview-artwork')),
            )
            .config,
        color.apply(identity.avatar),
      );
    });

    testWidgets('saves once and returns to the calling route', (tester) async {
      var saves = 0;
      await _pumpEditor(
        tester,
        identity: identity,
        onSave: ({required memberId, required avatar}) async => saves++,
      );
      final option = avatarCatalog.optionsFor(AvatarCategory.head).first;
      await tester.tap(find.byKey(Key('avatar-option-${option.id}')));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save avatar'));
      await tester.pumpAndSettle();

      expect(saves, 1);
      expect(find.text('Origin'), findsOneWidget);
    });

    testWidgets('keeps the draft and exposes the exact error with retry', (
      tester,
    ) async {
      var calls = 0;
      await _pumpEditor(
        tester,
        identity: identity,
        onSave: ({required memberId, required avatar}) async {
          calls++;
          if (calls == 1) throw StateError('storage unavailable');
        },
      );
      final option = avatarCatalog.optionsFor(AvatarCategory.head).first;
      await tester.tap(find.byKey(Key('avatar-option-${option.id}')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save avatar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your avatar could not be saved. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(
        tester
            .widget<KeepersAvatar>(
              find.byKey(const Key('avatar-editor-preview-artwork')),
            )
            .config,
        avatarCatalog
            .optionsFor(AvatarCategory.head)
            .first
            .apply(identity.avatar),
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Origin'), findsOneWidget);
    });

    testWidgets('announces a save failure and focuses its retry action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpEditor(
        tester,
        identity: identity,
        onSave: ({required memberId, required avatar}) async {
          throw StateError('storage unavailable');
        },
      );
      final option = avatarCatalog.optionsFor(AvatarCategory.head).first;
      await tester.tap(find.byKey(Key('avatar-option-${option.id}')));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save avatar'));
      await tester.pumpAndSettle();

      final error = find.byKey(const Key('avatar-save-error-live-region'));
      expect(tester.getSemantics(error).flagsCollection.isLiveRegion, isTrue);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Try again'))
            .focusNode
            ?.hasFocus,
        isTrue,
      );
      semantics.dispose();
    });

    testWidgets('back exits immediately while the draft is clean', (
      tester,
    ) async {
      await _pumpEditor(tester, identity: identity);

      await tester.tap(find.byKey(const Key('avatar-editor-back')));
      await tester.pumpAndSettle();

      expect(find.text('Origin'), findsOneWidget);
    });

    testWidgets('dirty back requires confirmation and can discard changes', (
      tester,
    ) async {
      await _pumpEditor(tester, identity: identity);
      final option = avatarCatalog.optionsFor(AvatarCategory.head).first;
      await tester.tap(find.byKey(Key('avatar-option-${option.id}')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('avatar-editor-back')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);

      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
    });

    testWidgets(
      'saving blocks edits, back, duplicate writes, and duplicate pop',
      (tester) async {
        final save = Completer<void>();
        var calls = 0;
        await _pumpEditor(
          tester,
          identity: identity,
          onSave: ({required memberId, required avatar}) {
            calls++;
            return save.future;
          },
        );
        final firstOption = avatarCatalog.optionsFor(AvatarCategory.head).first;
        final secondOption = avatarCatalog.optionsFor(AvatarCategory.head)[1];
        await tester.tap(find.byKey(Key('avatar-option-${firstOption.id}')));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save avatar'));
        await tester.pump();

        await tester.tap(find.byKey(Key('avatar-option-${secondOption.id}')));
        await tester.tap(find.byKey(const Key('avatar-editor-back')));
        await tester.tap(find.widgetWithText(FilledButton, 'Save avatar'));
        await tester.pump();
        expect(calls, 1);
        expect(find.text('Origin'), findsNothing);
        expect(
          tester
              .widget<KeepersAvatar>(
                find.byKey(const Key('avatar-editor-preview-artwork')),
              )
              .config,
          avatarCatalog
              .optionsFor(AvatarCategory.head)
              .first
              .apply(identity.avatar),
        );

        save.complete();
        await tester.pumpAndSettle();
        expect(find.text('Origin'), findsOneWidget);
      },
    );

    testWidgets('selected options expose semantics beyond their visual check', (
      tester,
    ) async {
      await _pumpEditor(tester, identity: identity);
      final firstOption = avatarCatalog.optionsFor(AvatarCategory.head).first;
      final secondOption = avatarCatalog.optionsFor(AvatarCategory.head)[1];
      await tester.tap(find.byKey(Key('avatar-option-${firstOption.id}')));
      await tester.pump();
      final selected = find.byKey(Key('avatar-option-${firstOption.id}'));
      final semantics = tester.ensureSemantics();

      expect(
        tester.getSemantics(selected).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        find.descendant(
          of: selected,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      tester.semantics.tap(
        find.semantics.byLabel('${secondOption.label} avatar option'),
      );
      await tester.pump();
      expect(
        tester
            .widget<KeepersAvatar>(
              find.byKey(const Key('avatar-editor-preview-artwork')),
            )
            .config,
        secondOption.apply(identity.avatar),
      );
      semantics.dispose();
    });

    testWidgets('options support keyboard activation', (tester) async {
      await _pumpEditor(tester, identity: identity);
      final option = avatarCatalog.optionsFor(AvatarCategory.head)[1];
      tester
          .widget<InkWell>(find.byKey(Key('avatar-option-focus-${option.id}')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(
        tester
            .widget<KeepersAvatar>(
              find.byKey(const Key('avatar-editor-preview-artwork')),
            )
            .config,
        option.apply(identity.avatar),
      );
    });

    testWidgets('keeps the fixed footer usable at narrow and enlarged text', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        identity: identity,
        size: const Size(390, 844),
        textScale: 1.4,
      );

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, 'Save avatar'), findsOneWidget);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Save avatar')).bottom,
        lessThanOrEqualTo(844),
      );
      expect(
        tester.getSize(find.byKey(const Key('avatar-editor-back'))).height,
        greaterThanOrEqualTo(44),
      );

      await _pumpEditor(
        tester,
        identity: identity,
        size: const Size(430, 932),
        textScale: 1.4,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Save avatar')).bottom,
        lessThanOrEqualTo(932),
      );
    });
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required LocalIdentity identity,
  AvatarSave? onSave,
  Size size = const Size(430, 932),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        avatarSaveProvider.overrideWithValue(
          onSave ?? ({required memberId, required avatar}) async {},
        ),
      ],
      child: MaterialApp(
        theme: KeepersTheme.daylight(),
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('Origin'))),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: AvatarEditorScreen(identity: identity),
          ),
        ),
      ),
    ),
  );
  navigatorKey.currentState!.pushNamed('/avatar-editor');
  await tester.pumpAndSettle();
}
