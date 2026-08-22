import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/member_page_screen.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/family_wheel_screen.dart';

void main() {
  testWidgets('member page separates sealed current week from kept history', (
    tester,
  ) async {
    const member = FamilyWheelMember(
      id: 'member-2',
      name: 'Amina',
      color: Color(0xFF48643A),
      avatar: AvatarConfig.defaults(seed: 'member-2'),
      contribution: .6,
      presence: FamilyPresence.near,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MemberPageScreen(
            member: member,
            sealedCount: 3,
            keptMemories: [
              MemberMemorySummary(
                id: 'kept-1',
                title: 'Summer kitchen',
                formatLabel: 'Voice memory',
                createdAt: DateTime(2025, 7, 2),
              ),
            ],
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Amina'), findsOneWidget);
    final sealedStatus = find.text('3 sealed this week');
    expect(sealedStatus, findsOneWidget);
    final sealedStatusText = tester.widget<RichText>(
      find.descendant(of: sealedStatus, matching: find.byType(RichText)),
    );
    final sealedStatusStyle = (sealedStatusText.text as TextSpan).style;
    expect(sealedStatusStyle?.fontSize, 16);
    expect(sealedStatusStyle?.fontWeight, FontWeight.w600);
    expect(
      sealedStatusStyle?.letterSpacing,
      isNot(KeepersType.heading.letterSpacing),
    );
    expect(
      find.text('Current-week memories stay closed until ceremony.'),
      findsOneWidget,
    );
    expect(find.text('Summer kitchen'), findsOneWidget);
    expect(find.bySubtype<HumationAvatar>(), findsOneWidget);
    expect(
      tester.widget<KeepersAvatar>(find.byType(KeepersAvatar)).config,
      member.avatar,
    );
    final decoratedContainers = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>();
    expect(
      decoratedContainers.every(
        (decoration) => decoration.boxShadow?.isEmpty ?? true,
      ),
      isTrue,
      reason: 'Member profile surfaces must not add drop shadows.',
    );
    expect(find.text('Legacy Lock'), findsNothing);
  });

  testWidgets('memorial preview explains an empty kept history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: const MediaQuery(
          data: MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(1.4),
          ),
          child: MemorialPageScreen(
            memberName: 'Christian',
            dateRange: 'Life dates supplied by family',
            memories: [],
            preview: true,
          ),
        ),
      ),
    );

    final routeTitle = find.text('Memorial preview');
    expect(routeTitle, findsOneWidget);
    final titleParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: routeTitle, matching: find.byType(RichText)),
    );
    expect(titleParagraph.didExceedMaxLines, isFalse);
    expect(find.text('A life story gathers here'), findsOneWidget);
    expect(
      find.text('Kept memories will appear here in time order.'),
      findsOneWidget,
    );
  });
}
