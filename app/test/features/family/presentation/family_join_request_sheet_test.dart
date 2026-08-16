import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/presentation/family_join_request_sheet.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

void main() {
  testWidgets(
    'shows only requester identity and disables both decisions while resolving',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = _SheetController(
        FamilyJoinRequestsState(
          requests: [_request],
          resolvingRequestId: _requestId,
        ),
      );
      await _pumpSheet(tester, controller);

      expect(find.text('Mariam wants to join'), findsOneWidget);
      expect(find.bySemanticsLabel('Mariam profile'), findsOneWidget);
      expect(find.textContaining('memory'), findsNothing);
      expect(find.textContaining('Rahman'), findsNothing);
      for (final key in const [
        'approve-join-request',
        'decline-join-request',
      ]) {
        final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
        expect(button.onPressed, isNull, reason: key);
        expect(
          tester.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(48),
        );
      }
      final close = tester.widget<TextButton>(
        find.byKey(const Key('close-join-request-sheet')),
      );
      expect(close.onPressed, isNull);
      expect(
        tester
            .getSize(find.byKey(const Key('close-join-request-sheet')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('join-request-status')))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('decline requires confirmation and cancel restores focus', (
    tester,
  ) async {
    final controller = _SheetController(
      FamilyJoinRequestsState(requests: [_request]),
    );
    await _pumpSheet(tester, controller);

    await tester.tap(find.byKey(const Key('decline-join-request')));
    await tester.pumpAndSettle();
    expect(find.text("Decline Mariam's request?"), findsOneWidget);
    expect(
      find.textContaining("Mariam won't join this family"),
      findsOneWidget,
    );
    expect(controller.declineCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.declineCalls, 0);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const Key('decline-join-request')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('decline-join-request')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline').last);
    await tester.pumpAndSettle();
    expect(controller.declineCalls, 1);
  });

  testWidgets('progress and error keep geometry and restore action focus', (
    tester,
  ) async {
    final gate = Completer<void>();
    final controller = _SheetController(
      FamilyJoinRequestsState(requests: [_request]),
      approveGate: gate,
      approveFailure: const FamilyJoinFailure(
        FamilyJoinFailureCode.networkUnavailable,
      ),
    );
    await _pumpSheet(tester, controller);
    final idleHeight = tester
        .getSize(find.byKey(const Key('family-join-request-sheet-body')))
        .height;

    await tester.tap(find.byKey(const Key('approve-join-request')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('family-join-request-sheet-body')))
          .height,
      idleHeight,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Keepers is offline. Try again.'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('family-join-request-sheet-body')))
          .height,
      idleHeight,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const Key('approve-join-request')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets(
    'authoritative resolution announces, closes, and restores trigger focus',
    (tester) async {
      final messages = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
        SystemChannels.accessibility,
        (message) async {
          messages.add(message);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler(SystemChannels.accessibility, null),
      );
      final controller = _SheetController(
        FamilyJoinRequestsState(requests: [_request]),
        resolveApprove: true,
      );
      await _pumpLauncher(tester, controller);

      await tester.tap(find.byKey(const Key('open-request-sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-join-request')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('family-join-request-sheet-body')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('open-request-sheet')))
            .focusNode
            ?.hasFocus,
        isTrue,
      );
      expect(messages.toString(), contains('Mariam request resolved'));
    },
  );

  testWidgets('idle Close exits the sheet and restores trigger focus', (
    tester,
  ) async {
    final controller = _SheetController(
      FamilyJoinRequestsState(requests: [_request]),
    );
    await _pumpLauncher(tester, controller);
    await tester.tap(find.byKey(const Key('open-request-sheet')));
    await tester.pumpAndSettle();

    final closeFinder = find.byKey(const Key('close-join-request-sheet'));
    final close = tester.widget<TextButton>(closeFinder);
    expect(find.text('Close'), findsOneWidget);
    expect(close.onPressed, isNotNull);
    expect(tester.getSize(closeFinder).height, greaterThanOrEqualTo(48));

    await tester.tap(closeFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('family-join-request-sheet-body')),
      findsNothing,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('open-request-sheet')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets('resolving sheet ignores back, barrier, and drag dismissal', (
    tester,
  ) async {
    final controller = _SheetController(
      FamilyJoinRequestsState(
        requests: [_request],
        resolvingRequestId: _requestId,
      ),
    );
    await _pumpLauncher(tester, controller);
    await tester.tap(find.byKey(const Key('open-request-sheet')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final sheetFinder = find.byKey(const Key('family-join-request-sheet-body'));
    final route = ModalRoute.of(tester.element(sheetFinder));
    expect(route, isA<ModalBottomSheetRoute<void>>());
    expect(
      [
        (route! as ModalBottomSheetRoute<void>).isDismissible,
        tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      ],
      [false, false],
    );

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('family-join-request-sheet-body')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('family-join-request-sheet-body')),
      findsOneWidget,
    );

    await tester.dragFrom(const Offset(400, 205), const Offset(0, 380));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('family-join-request-sheet-body')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  _SheetController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        familyJoinRequestsControllerProvider(_familyId)
            .overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: KeepersTheme.daylight(),
        home: Scaffold(
          body: FamilyJoinRequestSheet(familyId: _familyId, request: _request),
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
  final triggerFocus = FocusNode(debugLabel: 'request sheet trigger');
  addTearDown(triggerFocus.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        familyJoinRequestsControllerProvider(_familyId)
            .overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: KeepersTheme.daylight(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-request-sheet'),
              focusNode: triggerFocus,
              onPressed: () => FamilyJoinRequestSheet.show(
                context,
                familyId: _familyId,
                request: _request,
              ),
              child: const Text('Open request'),
            ),
          ),
        ),
      ),
    ),
  );
  triggerFocus.requestFocus();
  await tester.pump();
}

final class _SheetController extends FamilyJoinRequestsController {
  _SheetController(
    this.initial, {
    this.approveGate,
    this.approveFailure,
    this.resolveApprove = false,
  }) : super(_familyId);

  final FamilyJoinRequestsState initial;
  final Completer<void>? approveGate;
  final FamilyJoinFailure? approveFailure;
  final bool resolveApprove;
  var approveCalls = 0;
  var declineCalls = 0;

  @override
  FamilyJoinRequestsState build() => initial;

  @override
  Future<void> approve(String requestId) async {
    approveCalls += 1;
    state = FamilyJoinRequestsState(
      requests: state.requests,
      resolvingRequestId: requestId,
    );
    await approveGate?.future;
    if (approveFailure != null) {
      state = FamilyJoinRequestsState(
        requests: state.requests,
        failure: approveFailure,
      );
    } else if (resolveApprove) {
      state = const FamilyJoinRequestsState();
    }
  }

  @override
  Future<void> decline(String requestId) async {
    declineCalls += 1;
  }
}

final _request = PendingFamilyJoinRequest.validated(
  requestId: _requestId,
  familyId: _familyId,
  requesterAccountId: '33333333-3333-4333-8333-333333333333',
  memberId: '44444444-4444-4444-8444-444444444444',
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'clay',
  avatar: const AvatarConfig.defaults(
    seed: '44444444-4444-4444-8444-444444444444',
  ),
  joiningPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  codeVersion: 1,
  state: FamilyJoinRequestState.pending,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
);

const _familyId = '11111111-1111-4111-8111-111111111111';
const _requestId = '22222222-2222-4222-8222-222222222222';
