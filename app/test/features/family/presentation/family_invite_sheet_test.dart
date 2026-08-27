import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/domain/family_join_failure.dart';
import 'package:keepers/features/family/presentation/family_invite_sheet.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  testWidgets('shows sharing actions and creator-only regeneration', (
    tester,
  ) async {
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.ready,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
      ),
    );
    await _pump(tester, controller);

    expect(find.text('K7M4-P2Q8'), findsOneWidget);
    expect(find.text('Share family link'), findsOneWidget);
    expect(find.text('Copy family code'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Regenerate code'), findsOneWidget);

    await tester.tap(find.text('Regenerate code'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('previous code and pending requests'),
      findsOneWidget,
    );
    expect(controller.regenerateCalls, 0);
    await tester.tap(find.text('Regenerate').last);
    await tester.pumpAndSettle();
    expect(controller.regenerateCalls, 1);
  });

  testWidgets('non-creator can share but cannot regenerate', (tester) async {
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.ready,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
      ),
    );
    await _pump(tester, controller);

    expect(find.text('Share family link'), findsOneWidget);
    expect(find.text('Regenerate code'), findsNothing);
  });

  testWidgets('announces the family code as grouped characters', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.ready,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
      ),
    );
    await _pump(tester, controller);

    expect(
      find.bySemanticsLabel('Family code K 7 M 4 P 2 Q 8'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('copy and share actions invoke only their explicit boundary', (
    tester,
  ) async {
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.ready,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
      ),
    );
    await _pump(tester, controller);

    expect(controller.shareCalls, 0);
    expect(controller.copyCodeCalls, 0);
    expect(controller.copyLinkCalls, 0);
    await tester.tap(find.text('Copy family code'));
    await tester.pump();
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    await tester.tap(find.text('Share family link'));
    await tester.pump();

    expect(controller.copyCodeCalls, 1);
    expect(controller.copyLinkCalls, 1);
    expect(controller.shareCalls, 1);
  });

  testWidgets('regeneration disables decisions and preserves sheet height', (
    tester,
  ) async {
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.regenerating,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
      ),
    );
    await _pump(tester, controller);

    for (final key in const [
      'share-family-link',
      'copy-family-code',
      'copy-family-link',
      'regenerate-family-code',
    ]) {
      final button = tester.widget<TextButton>(find.byKey(Key(key)));
      expect(button.onPressed, isNull, reason: key);
    }
    final regeneratingHeight = tester
        .getSize(find.byKey(const Key('family-invite-sheet-body')))
        .height;

    controller.emit(
      const FamilyCodeState(
        phase: FamilyCodePhase.failed,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
        failure: FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
      ),
    );
    await tester.pump();

    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('family-invite-sheet-body'))).height,
      regeneratingHeight,
    );
  });

  testWidgets('cached code cannot regenerate while cloud loading is active', (
    tester,
  ) async {
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.loading,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
      ),
    );
    await _pump(tester, controller);

    final regenerate = tester.widget<TextButton>(
      find.byKey(const Key('regenerate-family-code')),
    );
    expect(regenerate.onPressed, isNull);
  });

  testWidgets('regenerating modal ignores barrier drag and system back', (
    tester,
  ) async {
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.regenerating,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
      ),
    );
    await _pumpLauncher(tester, controller);
    await tester.tap(find.text('Open invite'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('family-invite-sheet-body')), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('family-invite-sheet-body')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('family-invite-sheet-body')),
      const Offset(0, 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('family-invite-sheet-body')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('family-invite-sheet-body')), findsOneWidget);
  });

  testWidgets('cancelling regeneration restores focus to its action', (
    tester,
  ) async {
    final controller = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.ready,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
      ),
    );
    await _pump(tester, controller);

    await tester.tap(find.byKey(const Key('regenerate-family-code')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final action = tester.widget<TextButton>(
      find.byKey(const Key('regenerate-family-code')),
    );
    expect(action.focusNode?.hasFocus, isTrue);
  });

  testWidgets('signed-out status authenticates then reloads the family code', (
    tester,
  ) async {
    final codeController = _SheetController(
      const FamilyCodeState(
        phase: FamilyCodePhase.failed,
        failure: FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
      ),
    );
    final inviteController = _SheetInviteController(
      const FamilyInviteState(phase: FamilyInvitePhase.needsAuthentication),
    );
    await _pump(tester, codeController, inviteController: inviteController);

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.byKey(const Key('invite-recipient-email')), findsNothing);

    inviteController.emit(
      const FamilyInviteState(phase: FamilyInvitePhase.ready),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to continue'), findsNothing);
    expect(codeController.loadCalls, 1);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _SheetController controller, {
  _SheetInviteController? inviteController,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        familyCodeControllerProvider(_familyId).overrideWith(() => controller),
        if (inviteController != null)
          familyInviteControllerProvider.overrideWith(() => inviteController),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: KeepersType.primary),
        home: Scaffold(
          body: FamilyInviteSheet(
            familyId: _familyId,
            initializeOnMount: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  _SheetController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        familyCodeControllerProvider(_familyId).overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: KeepersType.primary),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  FamilyInviteSheet.show(context, familyId: _familyId),
              child: const Text('Open invite'),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _SheetController extends FamilyCodeController {
  _SheetController(this.initial) : super(_familyId);

  final FamilyCodeState initial;
  var shareCalls = 0;
  var copyCodeCalls = 0;
  var copyLinkCalls = 0;
  var regenerateCalls = 0;
  var loadCalls = 0;

  @override
  FamilyCodeState build() => initial;

  void emit(FamilyCodeState value) => state = value;

  @override
  Future<void> load() async => loadCalls += 1;

  @override
  Future<void> copyFamilyCode() async => copyCodeCalls += 1;

  @override
  Future<void> copyFamilyLink() async => copyLinkCalls += 1;

  @override
  Future<void> shareFamilyLink({Rect? sharePositionOrigin}) async {
    shareCalls += 1;
  }

  @override
  Future<void> regenerate() async => regenerateCalls += 1;
}

final class _SheetInviteController extends FamilyInviteController {
  _SheetInviteController(this.initial);

  final FamilyInviteState initial;

  @override
  FamilyInviteState build() => initial;

  @override
  Future<void> initialize() async {}

  void emit(FamilyInviteState value) => state = value;
}

const _familyId = '11111111-1111-4111-8111-111111111111';
