import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/family_wheel_screen.dart';
import 'package:keepers/ui/keepers_app_background.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';

void main() {
  testWidgets('family wheel uses dark system icons on its light surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: FamilyWheelScreen(
          familyName: 'Sabati family',
          currentMemberName: 'Chris',
          yourContribution: 0,
          members: const [],
          onCapture: () {},
          onMemberSelected: (_) {},
        ),
      ),
    );

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const ValueKey('family-wheel-system-ui')),
    );
    expect(region.value.statusBarIconBrightness, Brightness.dark);
    expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('product mark leads the family title in the home hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(_testWheel());
    await tester.pump();

    final wordmark = find.byKey(const ValueKey('keepers-wordmark'));
    final familyTitle = find.text('SABATI FAMILY');

    expect(wordmark, findsOneWidget);
    expect(familyTitle, findsOneWidget);
    expect(
      tester.getTopLeft(wordmark).dy,
      lessThan(tester.getTopLeft(familyTitle).dy),
    );
    expect(
      tester.getSize(wordmark).width,
      lessThan(tester.getSize(familyTitle).width),
    );
  });

  testWidgets('product mark is centered without a header surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testWheel(
        mediaQueryData: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();

    final bar = find.byKey(const ValueKey('keepers-home-brand-bar'));
    final wordmark = find.byKey(const ValueKey('keepers-wordmark'));
    final familyTitle = find.byKey(const ValueKey('home-family-title'));

    expect(bar, findsOneWidget);
    expect(tester.widget(bar), isA<SizedBox>());
    expect(tester.getSize(bar).width, 390);
    expect(
      tester.getRect(wordmark).center.dx,
      closeTo(tester.getRect(bar).center.dx, .1),
    );
    expect(
      tester.getTopLeft(familyTitle).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(bar).dy),
    );
  });

  testWidgets('keeps wordmark centered while code is top-right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testWheel(
        familyCode: 'K7M4-P2Q8',
        onFamilyCodeTap: () {},
        mediaQueryData: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Family code'), findsOneWidget);
    expect(find.text('K7M4-P2Q8'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Family code K 7 M 4 P 2 Q 8'),
      findsOneWidget,
    );
    final wordmark = tester.getCenter(
      find.byKey(const ValueKey('keepers-wordmark')),
    );
    expect(wordmark.dx, closeTo(195, 1));
    expect(
      tester.getSize(find.byKey(const ValueKey('family-code-action'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('places a join notice between presence and the bubble field', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _testWheel(
        pendingJoinRequestName: 'Mariam',
        onPendingJoinRequestTap: () => taps += 1,
      ),
    );
    await tester.pump();

    final presence = find.byKey(const ValueKey('family-presence-meter'));
    final notice = find.byKey(const ValueKey('family-join-request-notice'));
    final field = find.byKey(const ValueKey('family-field-interactive-viewer'));
    expect(find.text('Mariam wants to join'), findsOneWidget);
    expect(
      tester.getBottomLeft(presence).dy,
      lessThanOrEqualTo(tester.getTopLeft(notice).dy),
    );
    expect(
      tester.getBottomLeft(notice).dy,
      lessThanOrEqualTo(tester.getTopLeft(field).dy),
    );
    expect(tester.getSize(notice).height, greaterThanOrEqualTo(48));

    await tester.tap(notice);
    expect(taps, 1);
  });

  testWidgets('family title no longer carries the segmented mark', (
    tester,
  ) async {
    await tester.pumpWidget(_testWheel());
    await tester.pump();

    expect(find.text('SABATI FAMILY'), findsOneWidget);
    expect(find.byKey(const ValueKey('family-mark')), findsNothing);
  });

  testWidgets('family title stays quieter than the product wordmark', (
    tester,
  ) async {
    await tester.pumpWidget(_testWheel());
    await tester.pump();

    final familyTitle = find.text('SABATI FAMILY');
    final wordmark = find.byKey(const ValueKey('keepers-wordmark'));

    expect(
      tester.getSize(familyTitle).height,
      lessThan(tester.getSize(wordmark).height),
    );

    final title = tester.widget<Text>(familyTitle);
    expect(title.style?.fontSize, 20);
    expect(title.style?.fontFamily, KeepersType.primary);
    expect(title.style?.fontWeight, FontWeight.w600);
  });

  testWidgets(
    'family title renders in title case after the kept total moves to archive',
    (tester) async {
      await tester.pumpWidget(_testWheel(familyName: 'RAHMAN'));
      await tester.pump();

      final familyName = tester.widget<Text>(find.text('RAHMAN FAMILY'));
      final paintedFamilyName = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('home-family-title')),
          matching: find.byType(RichText),
        ),
      );

      expect(familyName.style?.fontSize, 20);
      expect(familyName.style?.fontFamily, KeepersType.primary);
      expect(familyName.style?.fontWeight, FontWeight.w600);
      expect(
        familyName.style?.letterSpacing,
        KeepersType.heading.letterSpacing,
      );
      expect(familyName.style?.height, 1);
      expect(
        (paintedFamilyName.text as TextSpan).toPlainText(),
        'Rahman Family',
      );
      expect(
        find.byKey(const ValueKey('home-family-summary-row')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Rahman family'), findsOneWidget);
      expect(find.bySemanticsLabel('Family Rahman family'), findsNothing);
      expect(find.text('Rahman family'), findsNothing);
      expect(find.bySemanticsLabel('7 memories kept forever'), findsNothing);
      expect(find.text('KEPT FOREVER'), findsNothing);
      expect(find.text('KEPT'), findsNothing);
      expect(find.byKey(const ValueKey('family-mark')), findsNothing);
      expect(find.text('KEPT\nMEMORIES'), findsNothing);
      expect(find.text('SEALED'), findsNothing);
      expect(find.text('Rahman'), findsNothing);
      expect(find.text('RAHMAN'), findsNothing);
    },
  );

  testWidgets('family label grows with the user text scale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testWheel(mediaQueryData: const MediaQueryData(size: Size(390, 844))),
    );
    await tester.pump();

    final normalTop = tester.getTopLeft(find.text('SABATI FAMILY')).dy;
    final normalBottom = tester.getBottomRight(find.text('SABATI FAMILY')).dy;

    await tester.pumpWidget(
      _testWheel(
        mediaQueryData: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(1.4),
        ),
      ),
    );
    await tester.pump();

    final scaledTop = tester.getTopLeft(find.text('SABATI FAMILY')).dy;
    final scaledBottom = tester.getBottomRight(find.text('SABATI FAMILY')).dy;
    expect(
      scaledBottom - scaledTop,
      greaterThan((normalBottom - normalTop) * 1.2),
    );
  });

  testWidgets(
    'family title leads presence and the weekly experience follows the field',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testWheel(
          familyName: 'Rahman',
          members: _members,
          mediaQueryData: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 24, bottom: 24),
            disableAnimations: true,
          ),
        ),
      );
      await tester.pump();

      final familyTitle = find.byKey(const ValueKey('home-family-title'));
      final presenceSentence = find.bySemanticsLabel('Noura, you are here');
      final familyField = find.byKey(
        const ValueKey('family-field-interactive-viewer'),
      );
      final weekly = find.byKey(const ValueKey('weekly-recap-mode'));

      expect(familyTitle, findsOneWidget);
      expect(find.text('RAHMAN FAMILY'), findsOneWidget);
      expect(find.byKey(const ValueKey('family-mark')), findsNothing);
      expect(find.text('KEPT'), findsNothing);
      expect(find.bySemanticsLabel('7 kept memories'), findsNothing);
      expect(find.text('KEPT FOREVER'), findsNothing);
      expect(find.bySemanticsLabel('7 memories kept forever'), findsNothing);
      expect(
        tester.getBottomLeft(familyTitle).dy,
        lessThanOrEqualTo(tester.getTopLeft(presenceSentence).dy),
      );
      expect(
        tester.getTopLeft(presenceSentence).dy -
            tester.getBottomLeft(familyTitle).dy,
        inInclusiveRange(8, 18),
      );
      expect(
        tester.getBottomLeft(familyField).dy,
        lessThanOrEqualTo(tester.getTopLeft(weekly).dy),
      );
      expect(find.text('LEGACY LOCK'), findsNothing);
      expect(find.text('CAPSULE'), findsNothing);
    },
  );

  testWidgets('home follows the confirmed editorial content order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testWheel(
        members: _members,
        mediaQueryData: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();

    final wordmark = find.byKey(const ValueKey('keepers-wordmark'));
    final familyTitle = find.byKey(const ValueKey('home-family-title'));
    final presenceSentence = find.bySemanticsLabel('Noura, you are here');
    final presenceMarks = find.bySemanticsLabel(
      '2 of 3 family members are here',
    );
    final familyField = find.byKey(
      const ValueKey('family-field-interactive-viewer'),
    );
    final weekly = find.byKey(const ValueKey('weekly-recap-mode'));
    final actions = find.byKey(const ValueKey('home-action-group'));

    expect(
      tester.getBottomLeft(wordmark).dy,
      lessThanOrEqualTo(tester.getTopLeft(familyTitle).dy),
    );
    expect(
      tester.getTopLeft(familyTitle).dy - tester.getBottomLeft(wordmark).dy,
      inInclusiveRange(20, 36),
    );
    expect(
      tester.getBottomLeft(familyTitle).dy,
      lessThanOrEqualTo(tester.getTopLeft(presenceSentence).dy),
    );
    expect(
      tester.getBottomLeft(presenceSentence).dy,
      lessThanOrEqualTo(tester.getTopLeft(presenceMarks).dy),
    );
    expect(
      tester.getBottomLeft(presenceMarks).dy,
      lessThanOrEqualTo(tester.getTopLeft(familyField).dy),
    );
    expect(
      tester.getTopLeft(familyField).dy -
          tester.getBottomLeft(presenceMarks).dy,
      closeTo(16, 1),
    );
    expect(tester.getSize(familyField).height, 318);
    expect(
      tester.getBottomLeft(familyField).dy,
      lessThanOrEqualTo(tester.getTopLeft(weekly).dy),
    );
    expect(
      find.descendant(
        of: actions,
        matching: find.byKey(const ValueKey('home-kept-forever-strip')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: actions, matching: find.text('SABATI FAMILY')),
      findsNothing,
    );
  });

  testWidgets(
    'weekly photo progress sits between the family field and gathering prompt',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testWheel(
          members: _members,
          weeklyPhotoCount: 3,
          mediaQueryData: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 24, bottom: 24),
            disableAnimations: true,
          ),
        ),
      );
      await tester.pump();

      final familyField = find.byKey(
        const ValueKey('family-field-interactive-viewer'),
      );
      final progress = find.byKey(const ValueKey('weekly-photo-progress'));
      final gatheringPrompt = find.byKey(
        const ValueKey('family-gathering-prompt'),
      );
      final weeklyRecap = find.byKey(const ValueKey('weekly-recap-mode'));
      final navigation = find.byKey(const ValueKey('keepers-bottom-nav'));

      await tester.ensureVisible(weeklyRecap);
      await tester.pumpAndSettle();

      expect(familyField, findsOneWidget);
      expect(progress, findsOneWidget);
      expect(gatheringPrompt, findsOneWidget);
      expect(weeklyRecap, findsOneWidget);
      expect(navigation, findsOneWidget);
      expect(
        tester.getBottomLeft(familyField).dy,
        lessThanOrEqualTo(tester.getTopLeft(progress).dy),
      );
      expect(
        tester.getTopLeft(progress).dy,
        lessThanOrEqualTo(tester.getTopLeft(gatheringPrompt).dy),
      );
      expect(
        tester.getTopLeft(gatheringPrompt).dy,
        lessThanOrEqualTo(tester.getTopLeft(weeklyRecap).dy),
      );
      expect(
        tester.getTopLeft(weeklyRecap).dy,
        lessThanOrEqualTo(tester.getTopLeft(navigation).dy),
      );
    },
  );

  testWidgets('weekly experience sits above the bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testWheel(
        members: _members,
        mediaQueryData: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();

    final actions = find.byKey(const ValueKey('home-action-group'));
    final navigation = find.byKey(const ValueKey('keepers-bottom-nav'));

    expect(actions, findsOneWidget);
    expect(navigation, findsOneWidget);
    await tester.ensureVisible(actions);
    await tester.pumpAndSettle();
    final bottomGap =
        tester.getTopLeft(navigation).dy - tester.getBottomLeft(actions).dy;
    expect(bottomGap, inInclusiveRange(8, 20));
    final weeklyPanel = find.byKey(const ValueKey('weekly-recap-open'));
    expect(find.byKey(const ValueKey('weekly-recap-mode')), findsOneWidget);
    expect(tester.getSize(weeklyPanel).width, 358);
    expect(find.text('LEGACY LOCK'), findsNothing);
    expect(find.text('CAPSULE'), findsNothing);
  });

  testWidgets('weekly progress stays compact at phone large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var nudged = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 24, bottom: 24),
            textScaler: TextScaler.linear(1.4),
            disableAnimations: true,
          ),
          child: FamilyWheelScreen(
            familyName: 'Sabati family',
            currentMemberName: 'Chris',
            yourContribution: .6,
            members: _members,
            onCapture: () {},
            onMemberSelected: (_) {},
            onNudgeMissingMembers: () => nudged = true,
          ),
        ),
      ),
    );
    await tester.pump();

    final progress = find.byKey(const ValueKey('weekly-photo-progress'));
    final action = find.byKey(const ValueKey('family-gathering-prompt'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    final progressRect = tester.getRect(progress);

    expect(progressRect.height, 6);
    expect(find.text('Weekly vault'), findsNothing);
    expect(
      find.textContaining('family member needs to be present'),
      findsNothing,
    );
    expect(action.hitTestable(), findsOneWidget);
    expect(
      find.descendant(of: action, matching: find.text('Ask Mariam to come')),
      findsOneWidget,
    );
    await tester.tap(action);
    await tester.pump();
    expect(nudged, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('family home composes the approved presence story and actions', (
    tester,
  ) async {
    var captured = false;
    FamilyWheelMember? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: FamilyWheelScreen(
            familyName: 'Sabati family',
            currentMemberName: 'Chris',
            yourContribution: .6,
            members: [
              FamilyWheelMember(
                id: 'noura',
                name: 'Noura',
                color: KeepersColors.memberPalette[0],
                avatar: const AvatarConfig.defaults(seed: 'noura'),
                contribution: .8,
                presence: FamilyPresence.near,
              ),
              FamilyWheelMember(
                id: 'mariam',
                name: 'Mariam',
                color: KeepersColors.memberPalette[1],
                avatar: const AvatarConfig.defaults(seed: 'mariam'),
                contribution: .45,
                presence: FamilyPresence.far,
              ),
              FamilyWheelMember(
                id: 'youssef',
                name: 'Youssef',
                color: KeepersColors.memberPalette[3],
                avatar: const AvatarConfig.defaults(seed: 'youssef'),
                contribution: .25,
                presence: FamilyPresence.away,
              ),
            ],
            onCapture: () => captured = true,
            onMemberSelected: (member) => selected = member,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FamilyWheelPainterHost), findsOneWidget);
    expect(find.bySemanticsLabel('You, Chris, 60% sealed'), findsOneWidget);
    expect(find.bySemanticsLabel('Noura, near, 80% sealed'), findsOneWidget);
    expect(find.bySemanticsLabel('Mariam, far, 45% sealed'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('Hold to speak'), findsNothing);
    expect(find.byKey(const ValueKey('keepers-wordmark')), findsOneWidget);
    expect(find.bySemanticsLabel('Keepers'), findsOneWidget);
    expect(find.text('One more\nto open.'), findsNothing);
    expect(find.text('KEPT FOREVER'), findsNothing);
    expect(find.text('KEPT'), findsNothing);
    expect(find.text('KEPT\nMEMORIES'), findsNothing);
    expect(find.bySemanticsLabel('7 memories kept forever'), findsNothing);
    expect(find.text('OF FOUR'), findsOneWidget);
    expect(find.textContaining('NOURA'), findsWidgets);
    expect(find.text('Ask Mariam & Youssef to come'), findsOneWidget);
    expect(find.text('INVITE'), findsOneWidget);
    expect(find.bySemanticsLabel('Weekly photo progress'), findsOneWidget);
    expect(find.text('0 of 5 photos'), findsNothing);
    expect(find.bySemanticsLabel('Weekly experience locked'), findsOneWidget);
    expect(find.text('LEGACY LOCK'), findsNothing);
    expect(find.text('CAPSULE'), findsNothing);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);

    await tester.tap(find.bySemanticsLabel('You, Chris, 60% sealed'));
    expect(captured, isTrue);

    await tester.tap(find.bySemanticsLabel('Noura, near, 80% sealed'));
    expect(selected?.id, 'noura');

    captured = false;
    tester.semantics.tap(find.semantics.byLabel('You, Chris, 60% sealed'));
    await tester.pump();
    expect(captured, isTrue);
  });

  testWidgets('family wheel stays usable at 1.4x text scale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 24, bottom: 24),
            textScaler: TextScaler.linear(1.4),
            disableAnimations: true,
          ),
          child: FamilyWheelScreen(
            familyName: 'Sabati family with a long name',
            currentMemberName: 'Christopher',
            yourContribution: .4,
            members: [
              FamilyWheelMember(
                id: 'one',
                name: 'Alexandria',
                color: KeepersColors.memberPalette[0],
                avatar: const AvatarConfig.defaults(seed: 'one'),
                contribution: .5,
                presence: FamilyPresence.near,
              ),
              FamilyWheelMember(
                id: 'two',
                name: 'Mohammed',
                color: KeepersColors.memberPalette[1],
                avatar: const AvatarConfig.defaults(seed: 'two'),
                contribution: .5,
                presence: FamilyPresence.far,
              ),
              FamilyWheelMember(
                id: 'three',
                name: 'Elizabeth',
                color: KeepersColors.memberPalette[2],
                avatar: const AvatarConfig.defaults(seed: 'three'),
                contribution: .5,
                presence: FamilyPresence.away,
              ),
            ],
            onCapture: () {},
            onMemberSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('keepers-wordmark')), findsOneWidget);
    expect(find.text('Ready to\nopen.'), findsNothing);
    expect(
      find.bySemanticsLabel('Sabati family with a long name family'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('4 memories kept forever'), findsNothing);

    final title = find.text('SABATI FAMILY WITH A LONG NAME FAMILY');
    final titleWidget = tester.widget<Text>(title);
    expect(titleWidget.maxLines, 1);
    expect(titleWidget.overflow, TextOverflow.ellipsis);

    final wordmark = find.byKey(const ValueKey('keepers-wordmark'));
    final familyTitle = find.byKey(const ValueKey('home-family-title'));
    final presence = find.bySemanticsLabel('Alexandria, you are here');
    expect(
      tester.getBottomLeft(wordmark).dy,
      lessThanOrEqualTo(tester.getTopLeft(familyTitle).dy),
    );
    expect(
      tester.getBottomLeft(familyTitle).dy,
      lessThanOrEqualTo(tester.getTopLeft(presence).dy),
    );

    final weekly = find.byKey(const ValueKey('weekly-recap-mode'));
    await tester.ensureVisible(weekly);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('home-kept-forever-strip')), findsNothing);
    expect(find.byKey(const ValueKey('weekly-recap-mode')), findsOneWidget);
    expect(find.text('LEGACY LOCK'), findsNothing);
    expect(find.text('CAPSULE'), findsNothing);
  });

  testWidgets('invite node adds a member while gathering prompt only nudges', (
    tester,
  ) async {
    var added = 0;
    var nudged = 0;
    await tester.pumpWidget(
      _testWheel(
        members: const [
          FamilyWheelMember(
            id: 'mariam',
            name: 'Mariam',
            color: KeepersColors.homeGreen,
            avatar: AvatarConfig.defaults(seed: 'mariam'),
            contribution: .4,
            presence: FamilyPresence.away,
          ),
        ],
        onAddMember: () => added += 1,
        onNudgeMissingMembers: () => nudged += 1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('family-invite-node-action')));
    await tester.pump();
    expect(added, 1);
    expect(nudged, 0);

    final nudge = find.byKey(const ValueKey('family-gathering-prompt'));
    await tester.ensureVisible(nudge);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: nudge, matching: find.text('Ask Mariam to come')),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(nudge).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('weekly-recap-mode'))).dy,
      ),
    );
    await tester.tap(nudge);

    expect(added, 1);
    expect(nudged, 1);
  });

  testWidgets('an empty family wheel starts with the current member only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: FamilyWheelScreen(
            familyName: 'Sabati family',
            currentMemberName: 'Chris',
            yourContribution: 0,
            members: const [],
            onCapture: () {},
            onMemberSelected: (_) {},
            enabledDestinations: KeepersNavDestination.values.toSet(),
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('You, Chris, 0% sealed'), findsOneWidget);
    expect(find.byKey(const ValueKey('keepers-wordmark')), findsOneWidget);
    expect(find.text('Invite your\nfamily in.'), findsNothing);
    expect(find.text('YOU ARE HERE'), findsOneWidget);
    expect(find.byType(KeepersBottomNav), findsOneWidget);
    expect(find.bySemanticsLabel('Memory Key'), findsOneWidget);
    expect(find.bySemanticsLabel('Wheel, selected'), findsOneWidget);
    expect(find.bySemanticsLabel('Keep a memory'), findsOneWidget);
    expect(find.bySemanticsLabel('Archive'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(find.bySemanticsLabel('Locks'), findsNothing);
  });

  testWidgets('a one-person family can ask family to come through Invite', (
    tester,
  ) async {
    var invites = 0;
    var nudges = 0;
    await tester.pumpWidget(
      _testWheel(
        onAddMember: () => invites += 1,
        onNudgeMissingMembers: () => nudges += 1,
      ),
    );

    final invite = find.byKey(const ValueKey('family-gathering-prompt'));
    await tester.ensureVisible(invite);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: invite, matching: find.text('Ask family to come')),
      findsOneWidget,
    );
    await tester.tap(invite);

    expect(invites, 1);
    expect(nudges, 0);
    expect(find.text('Everyone is here'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-recap-mode')),
        matching: find.widgetWithText(FilledButton, 'Ask family to come'),
      ),
      findsNothing,
    );
  });

  testWidgets('gathering prompt uses the warm neutral reference treatment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testWheel(
        onAddMember: () {},
        mediaQueryData: const MediaQueryData(
          size: Size(430, 932),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          disableAnimations: true,
        ),
      ),
    );

    final prompt = find.byKey(const ValueKey('family-gathering-prompt'));
    await tester.ensureVisible(prompt);
    await tester.pumpAndSettle();

    final surfaceFinder = find.descendant(
      of: prompt,
      matching: find.byType(Material),
    );
    final surface = tester.widget<Material>(surfaceFinder);
    final shape = surface.shape! as StadiumBorder;
    final chevron = tester.widget<Icon>(
      find.descendant(
        of: prompt,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
    );

    expect(surface.color, KeepersColors.auraIvory);
    expect(tester.getSize(surfaceFinder).width, closeTo(336.6, .1));
    expect(shape.side.color, const Color(0xFFD4BBAC));
    expect(shape.side.width, 1.25);
    expect(chevron.color, const Color(0xFFD4BBAC));
  });

  testWidgets('weekly reveal blocks underlying actions until it completes', (
    tester,
  ) async {
    var captures = 0;
    var weeklyOpens = 0;
    await tester.pumpWidget(
      _testWheel(
        disableAnimations: false,
        weeklyPhotoCount: 5,
        members: [
          FamilyWheelMember(
            id: 'mariam',
            name: 'Mariam',
            color: KeepersColors.homeGreen,
            avatar: AvatarConfig.defaults(seed: 'mariam'),
            contribution: .4,
            presence: FamilyPresence.near,
          ),
        ],
        onCapture: () => captures += 1,
        onOpenWeeklyExperience: () => weeklyOpens += 1,
      ),
    );

    final open = find.byKey(const ValueKey('weekly-recap-open'));
    await tester.ensureVisible(open);
    await tester.pump();
    await tester.tap(open);
    await tester.pump();

    expect(find.byKey(const ValueKey('weekly-pastel-flood')), findsOneWidget);
    expect(find.semantics.byLabel('Keep a memory'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('keepers-nav-capture')),
      warnIfMissed: false,
    );
    expect(captures, 0);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(weeklyOpens, 1);
  });

  testWidgets('weekly reveal requires three quarters of the family present', (
    tester,
  ) async {
    var opens = 0;
    final twoOfFourPresent = [
      FamilyWheelMember(
        id: 'near',
        name: 'Near',
        color: KeepersColors.homeGreen,
        avatar: AvatarConfig.defaults(seed: 'near'),
        contribution: .4,
        presence: FamilyPresence.near,
      ),
      FamilyWheelMember(
        id: 'away-one',
        name: 'Away one',
        color: KeepersColors.homeBlue,
        avatar: AvatarConfig.defaults(seed: 'away-one'),
        contribution: .2,
        presence: FamilyPresence.away,
      ),
      FamilyWheelMember(
        id: 'away-two',
        name: 'Away two',
        color: KeepersColors.homeMauve,
        avatar: AvatarConfig.defaults(seed: 'away-two'),
        contribution: .1,
        presence: FamilyPresence.away,
      ),
    ];

    await tester.pumpWidget(
      _testWheel(
        members: twoOfFourPresent,
        weeklyPhotoCount: 5,
        onOpenWeeklyExperience: () => opens += 1,
      ),
    );

    var panel = find.byKey(const ValueKey('weekly-recap-open'));
    await tester.ensureVisible(panel);
    await tester.pump();
    expect(
      tester
          .getSemantics(panel)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );

    final threeOfFourPresent = [
      twoOfFourPresent.first,
      FamilyWheelMember(
        id: 'near-two',
        name: 'Near two',
        color: KeepersColors.homeBlue,
        avatar: AvatarConfig.defaults(seed: 'near-two'),
        contribution: .2,
        presence: FamilyPresence.near,
      ),
      twoOfFourPresent.last,
    ];
    await tester.pumpWidget(
      _testWheel(
        members: threeOfFourPresent,
        weeklyPhotoCount: 5,
        onOpenWeeklyExperience: () => opens += 1,
      ),
    );

    panel = find.byKey(const ValueKey('weekly-recap-open'));
    await tester.ensureVisible(panel);
    await tester.pump();
    expect(
      tester
          .getSemantics(panel)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
  }, semanticsEnabled: true);

  testWidgets(
    'temporary proximity policy unlocks at the same three-quarter threshold',
    (tester) async {
      var opens = 0;
      final awayMembers = [
        for (final (id, name) in const [
          ('noura', 'Noura'),
          ('mariam', 'Mariam'),
          ('layla', 'Layla'),
        ])
          FamilyWheelMember(
            id: id,
            name: name,
            color: KeepersColors.homeBlue,
            avatar: AvatarConfig.defaults(seed: id),
            contribution: null,
            presence: FamilyPresence.away,
          ),
      ];

      await tester.pumpWidget(
        _testWheel(
          members: awayMembers,
          weeklyPhotoCount: 5,
          weeklyPresencePolicy:
              WeeklyPresencePolicy.temporaryAllowUntilProximityProxy,
          onOpenWeeklyExperience: () => opens += 1,
        ),
      );

      final panel = find.byKey(const ValueKey('weekly-recap-open'));
      await tester.ensureVisible(panel);
      await tester.pump();

      expect(
        tester
            .getSemantics(panel)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        find.text('Ask Noura, Mariam & Layla to come'),
        findsOneWidget,
        reason: 'The temporary gate must not pretend away members are nearby.',
      );

      await tester.tap(panel);
      await tester.pump();
      expect(opens, 1);
    },
    semanticsEnabled: true,
  );

  test('member centers form a deterministic sparse constellation', () {
    final size = FamilyWheelGeometry.fieldSizeFor(3);
    final centers = FamilyWheelGeometry.memberCenters(
      size: size,
      memberCount: 4,
    );
    final center = Offset(size.width / 2, size.height / 2);

    expect(centers, hasLength(4));
    expect(centers[0], Offset(center.dx - 130, center.dy - 104));
    expect(centers[1], Offset(center.dx + 130, center.dy - 104));
    expect(centers[2], Offset(center.dx - 130, center.dy + 83));
    expect(centers[3], Offset(center.dx + 130, center.dy + 83));
  });

  test('large families occupy multiple rings without duplicate centers', () {
    final size = FamilyWheelGeometry.fieldSizeFor(13);
    final centers = FamilyWheelGeometry.memberCenters(
      size: size,
      memberCount: 14,
    );
    final center = Offset(size.width / 2, size.height / 2);

    expect(centers, hasLength(14));
    expect(centers.toSet(), hasLength(14));
    expect(centers.map((point) => (point - center).distance.round()).toSet(), {
      148,
      306,
    });
    final bounds = [
      for (final point in centers)
        Rect.fromCenter(center: point, width: 96, height: 100),
    ];
    for (var left = 0; left < centers.length; left += 1) {
      for (var right = left + 1; right < centers.length; right += 1) {
        expect(bounds[left].overlaps(bounds[right]), isFalse);
      }
    }
  });

  test('every deterministic ring node keeps breathing room around the current member', () {
    const breathingRoom = 8.0;

    for (var memberCount = 0; memberCount <= 40; memberCount += 1) {
      final size = FamilyWheelGeometry.fieldSizeFor(memberCount);
      final fieldCenter = Offset(size.width / 2, size.height / 2);
      final centers = FamilyWheelGeometry.memberCenters(
        size: size,
        memberCount: memberCount + 1,
      );
      final protectedCurrentBox = Rect.fromLTWH(
        fieldCenter.dx - 58,
        fieldCenter.dy - 53,
        116,
        160,
      ).inflate(breathingRoom);
      final inviteBox = Rect.fromLTWH(
        centers.first.dx - 44,
        centers.first.dy - 41,
        88,
        102,
      );

      expect(
        inviteBox.overlaps(protectedCurrentBox),
        isFalse,
        reason: 'invite overlaps current member for $memberCount relatives',
      );

      for (var index = 0; index < memberCount; index += 1) {
        final nodeSize = FamilyWheelGeometry.nodeSizeFor(index);
        final memberCenter = centers[index + 1];
        final memberBox = Rect.fromLTWH(
          memberCenter.dx - 48,
          memberCenter.dy - nodeSize / 2,
          96,
          nodeSize + 38,
        );

        expect(
          memberBox.overlaps(protectedCurrentBox),
          isFalse,
          reason:
              'relative $index overlaps current member for $memberCount relatives',
        );
      }
    }
  });

  test('invite and relative boxes never collide across family sizes', () {
    for (var memberCount = 0; memberCount <= 40; memberCount += 1) {
      final size = FamilyWheelGeometry.fieldSizeFor(memberCount);
      final centers = FamilyWheelGeometry.memberCenters(
        size: size,
        memberCount: memberCount + 1,
      );
      final boxes = <MapEntry<String, Rect>>[
        MapEntry(
          'invite',
          Rect.fromLTWH(centers.first.dx - 44, centers.first.dy - 41, 88, 102),
        ),
        for (var index = 0; index < memberCount; index += 1)
          MapEntry(
            'relative $index',
            Rect.fromLTWH(
              centers[index + 1].dx - 48,
              centers[index + 1].dy -
                  FamilyWheelGeometry.nodeSizeFor(index) / 2,
              96,
              FamilyWheelGeometry.nodeSizeFor(index) + 38,
            ),
          ),
      ];

      for (var left = 0; left < boxes.length; left += 1) {
        for (var right = left + 1; right < boxes.length; right += 1) {
          expect(
            boxes[left].value.overlaps(boxes[right].value),
            isFalse,
            reason:
                '${boxes[left].key} overlaps ${boxes[right].key} '
                'for $memberCount relatives',
          );
        }
      }
    }
  });

  test('maximum drift and focused scale keep every family node separate', () {
    for (var memberCount = 0; memberCount <= 40; memberCount += 1) {
      final size = FamilyWheelGeometry.fieldSizeFor(memberCount);
      final centers = FamilyWheelGeometry.memberCenters(
        size: size,
        memberCount: memberCount + 1,
      );
      final boxes = <MapEntry<String, Rect>>[
        MapEntry(
          'invite',
          Rect.fromLTWH(centers.first.dx - 44, centers.first.dy - 41, 88, 102),
        ),
        for (var index = 0; index < memberCount; index += 1)
          MapEntry(
            'relative $index',
            _maximumAnimatedMemberBox(center: centers[index + 1], index: index),
          ),
      ];

      for (var left = 0; left < boxes.length; left += 1) {
        for (var right = left + 1; right < boxes.length; right += 1) {
          expect(
            boxes[left].value.overlaps(boxes[right].value),
            isFalse,
            reason:
                '${boxes[left].key} overlaps ${boxes[right].key} at '
                'maximum drift/focus scale for $memberCount relatives',
          );
        }
      }
    }
  });

  testWidgets(
    'multi-ring fields initially center the current member on phone screens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final memberCount in const [5, 18]) {
        await tester.pumpWidget(
          _testWheel(
            members: _membersForCount(memberCount),
            mediaQueryData: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 24, bottom: 24),
              disableAnimations: true,
            ),
          ),
        );
        await tester.pump();

        final viewport = tester.getRect(
          find.byKey(const ValueKey('family-field-interactive-viewer')),
        );
        final current = find.bySemanticsLabel('You, Chris, 60% sealed');
        final currentRect = tester.getRect(current);
        final currentSurface = tester.getRect(
          find.byKey(const ValueKey('family-profile-surface-you')),
        );

        expect(
          currentSurface.center,
          within(distance: .1, from: viewport.center),
          reason: 'current member is off-center for $memberCount relatives',
        );
        expect(
          viewport.contains(currentRect.topLeft) &&
              viewport.contains(
                currentRect.bottomRight - const Offset(.01, .01),
              ),
          isTrue,
          reason: 'current member is clipped for $memberCount relatives',
        );
        expect(
          current.hitTestable(),
          findsOneWidget,
          reason: 'current member cannot be tapped for $memberCount relatives',
        );
      }
    },
  );

  testWidgets(
    'sparse family nodes start inside the viewport and clear the current member',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (var memberCount = 1; memberCount <= 4; memberCount += 1) {
        await tester.pumpWidget(
          _testWheel(
            members: _membersForCount(memberCount),
            onAddMember: () {},
            mediaQueryData: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 24, bottom: 24),
              disableAnimations: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final viewport = tester.getRect(
          find.byKey(const ValueKey('family-field-interactive-viewer')),
        );
        final current = find.bySemanticsLabel('You, Chris, 60% sealed');
        final protectedCurrent = tester.getRect(current).inflate(8);
        final nodes = <Finder>[
          find.bySemanticsLabel('Invite family'),
          for (var index = 0; index < memberCount; index += 1)
            find.bySemanticsLabel('Member $index, away, 50% sealed'),
        ];

        for (final node in nodes) {
          final nodeRect = tester.getRect(node);
          expect(
            viewport.contains(nodeRect.topLeft) &&
                viewport.contains(
                  nodeRect.bottomRight - const Offset(.01, .01),
                ),
            isTrue,
            reason: '$node is clipped for $memberCount relatives',
          );
          expect(node.hitTestable(), findsOneWidget);
          expect(nodeRect.overlaps(protectedCurrent), isFalse);
        }
      }
    },
  );

  testWidgets('the shared shell uses the approved flat background image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KeepersAppBackground(child: SizedBox.expand())),
    );

    final background = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == keepersBackgroundAsset &&
          widget.fit == BoxFit.cover,
    );

    expect(background, findsOneWidget);
  });

  testWidgets('family field has bounded pan and zoom', (tester) async {
    await tester.pumpWidget(_testWheel());

    final viewerFinder = find.byKey(
      const ValueKey('family-field-interactive-viewer'),
    );
    expect(viewerFinder, findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(viewer.minScale, .85);
    expect(viewer.maxScale, 1.45);
    expect(viewer.boundaryMargin, const EdgeInsets.all(72));
    expect(find.bySemanticsLabel('Reset family view'), findsNothing);
  });

  testWidgets('every home exit recenters the family field for return', (
    tester,
  ) async {
    var openedCurrentMember = false;
    var openedCapture = false;
    FamilyWheelMember? openedMember;
    await tester.pumpWidget(
      _testWheel(
        members: _members,
        onCapture: () => openedCapture = true,
        onCurrentMemberSelected: () => openedCurrentMember = true,
        onMemberSelected: (member) => openedMember = member,
      ),
    );
    await tester.pump();

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('family-field-interactive-viewer')),
    );
    var controller = viewer.transformationController!;
    final identity = Matrix4.identity().storage;

    void moveFamilyField() {
      controller.value = Matrix4.translationValues(28, -16, 0);
    }

    void expectCenteredFamilyField() {
      controller = tester
          .widget<InteractiveViewer>(
            find.byKey(const ValueKey('family-field-interactive-viewer')),
          )
          .transformationController!;
      expect(controller.value.storage, orderedEquals(identity));
    }

    moveFamilyField();
    await tester.tap(find.bySemanticsLabel('You, Chris, 60% sealed'));
    await tester.pump();
    expect(openedCurrentMember, isTrue);
    expectCenteredFamilyField();

    moveFamilyField();
    await tester.tap(find.bySemanticsLabel('Noura, near, 80% sealed'));
    await tester.pump();
    expect(openedMember?.id, 'noura');
    expectCenteredFamilyField();

    moveFamilyField();
    await tester.tap(find.bySemanticsLabel('Keep a memory'));
    await tester.pump();
    expect(openedCapture, isTrue);
    expectCenteredFamilyField();
  });

  testWidgets(
    'home exit replaces the transformed view to cancel stale motion',
    (tester) async {
      await tester.pumpWidget(_testWheel(onCapture: () {}));
      await tester.pump();

      final viewerFinder = find.byKey(
        const ValueKey('family-field-interactive-viewer'),
      );
      final viewer = tester.widget<InteractiveViewer>(viewerFinder);
      final originalController = viewer.transformationController!;
      final identity = Matrix4.identity().storage;

      originalController.value = Matrix4.translationValues(28, -16, 0);
      tester
          .widget<KeepersBottomNav>(find.byType(KeepersBottomNav))
          .onCapture!
          .call();
      await tester.pump();

      final returnedViewer = tester.widget<InteractiveViewer>(viewerFinder);
      expect(
        returnedViewer.transformationController,
        isNot(same(originalController)),
      );
      expect(
        returnedViewer.transformationController!.value.storage,
        orderedEquals(identity),
      );
    },
  );

  testWidgets('family wheel owns weekly recap instead of legacy or capsule', (
    tester,
  ) async {
    var openedWeekly = false;
    var openedPreview = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: FamilyWheelScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            yourContribution: .6,
            members: _members,
            onCapture: () {},
            onMemberSelected: (_) {},
            weeklyPhotoCount: 4,
            weeklyPreviewEnabled: true,
            onOpenWeeklyExperience: () => openedWeekly = true,
            onPreviewWeeklyExperience: () => openedPreview = true,
            enabledDestinations: KeepersNavDestination.values.toSet(),
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final weekly = find.byKey(const ValueKey('weekly-recap-mode'));
    expect(weekly, findsOneWidget);
    final progress = find.bySemanticsLabel('Weekly photo progress');
    expect(
      tester.getSemantics(progress).getSemanticsData().value,
      '4 of 5 photos. 1 photo needed. 1 more family member needs to be present',
    );
    expect(find.text('4 of 5 photos'), findsNothing);
    expect(find.text('LEGACY LOCK'), findsNothing);
    expect(find.text('CAPSULE'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('weekly-recap-preview')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('weekly-recap-preview')));
    expect(openedPreview, isTrue);
    expect(openedWeekly, isFalse);
  });

  testWidgets('family field paints no orbit or connector geometry', (
    tester,
  ) async {
    await tester.pumpWidget(_testWheel(members: _members));

    final orbitPainter = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_FamilyWheelPainter',
    );
    expect(orbitPainter, findsNothing);
  });

  testWidgets('profile bubbles use opaque surfaces without backdrop filters', (
    tester,
  ) async {
    await tester.pumpWidget(_testWheel(members: _members));
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNothing);

    for (final id in const ['you', 'noura', 'mariam']) {
      final surface = find.byKey(ValueKey('family-profile-surface-$id'));

      expect(surface, findsOneWidget);
      expect(tester.widget(surface), isA<Ink>());

      final decoration =
          tester.widget<Ink>(surface).decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border, isNotNull);
      expect(decoration.gradient, isNull);
      expect(decoration.color?.a, 1);
    }
  });

  testWidgets('profile bubbles render without shadows', (tester) async {
    await tester.pumpWidget(_testWheel(members: _members));
    await tester.pump();

    for (final id in const ['you', 'noura', 'mariam']) {
      final elevation = find.byKey(ValueKey('family-profile-elevation-$id'));
      final surface = find.byKey(ValueKey('family-profile-surface-$id'));

      expect(elevation, findsNothing);
      final decoration =
          tester.widget<Ink>(surface).decoration as BoxDecoration;
      expect(decoration.boxShadow, isNull);
    }
  });

  testWidgets('profile bubbles render the current and demo Humation avatars', (
    tester,
  ) async {
    const currentAvatar = AvatarConfig.defaults(seed: 'chris-custom');
    await tester.pumpWidget(
      _testWheel(members: _members, currentMemberAvatar: currentAvatar),
    );
    await tester.pump();

    final youAvatar = tester.widget<KeepersAvatar>(
      find.byKey(const ValueKey('family-avatar-you')),
    );
    final nouraAvatar = tester.widget<KeepersAvatar>(
      find.byKey(const ValueKey('family-avatar-noura')),
    );
    final mariamAvatar = tester.widget<KeepersAvatar>(
      find.byKey(const ValueKey('family-avatar-mariam')),
    );

    expect(youAvatar.config, currentAvatar);
    expect(nouraAvatar.config.seed, 'noura');
    expect(mariamAvatar.config.seed, 'mariam');
    expect(
      tester
          .widget<HumationAvatar>(
            find.descendant(
              of: find.byKey(const ValueKey('family-avatar-you')),
              matching: find.bySubtype<HumationAvatar>(),
            ),
          )
          .seed,
      currentAvatar.seed,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('family-avatar-noura')),
        matching: find.bySubtype<HumationAvatar>(),
      ),
      findsOneWidget,
    );
  });

  testWidgets('distance quiets profile art without fading member names', (
    tester,
  ) async {
    await tester.pumpWidget(_testWheel(members: _members));
    await tester.pump();

    final farName = find.text('MARIAM');
    final farSurface = find.byKey(
      const ValueKey('family-profile-surface-mariam'),
    );

    expect(
      find.ancestor(of: farName, matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(
      find.ancestor(of: farSurface, matching: find.byType(Opacity)),
      findsOneWidget,
    );
  });

  testWidgets('relative bubbles drift while decorative motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testWheel(members: _members, disableAnimations: false),
    );
    await tester.pump();

    final finder = find.byKey(const ValueKey('family-member-motion-noura'));
    expect(finder, findsOneWidget);
    final before = tester.widget<Transform>(finder).transform.getTranslation();
    await tester.pump(const Duration(seconds: 4));
    final after = tester.widget<Transform>(finder).transform.getTranslation();

    expect(after.x, isNot(closeTo(before.x, .01)));
  });

  testWidgets('reduced motion freezes relative bubbles', (tester) async {
    await tester.pumpWidget(_testWheel(members: _members));
    await tester.pump();

    final finder = find.byKey(const ValueKey('family-member-motion-noura'));
    expect(finder, findsOneWidget);
    final before = tester.widget<Transform>(finder).transform.getTranslation();
    await tester.pump(const Duration(seconds: 4));
    final after = tester.widget<Transform>(finder).transform.getTranslation();

    expect(after.x, closeTo(before.x, .001));
    expect(after.y, closeTo(before.y, .001));
  });

  testWidgets(
    'only a newly added roster id settles inside its positioned box',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final roster = ValueNotifier<List<FamilyWheelMember>>([_members.first]);
      addTearDown(roster.dispose);

      await tester.pumpWidget(_updatingWheel(roster, reduceMotion: false));
      await tester.pump();
      final fieldSize = tester.getSize(
        find.byKey(const ValueKey('family-field-interactive-viewer')),
      );
      expect(
        find.byKey(const ValueKey('family-member-arrival-opacity-noura')),
        findsNothing,
      );

      roster.value = _members;
      await tester.pump();

      final opacity = find.byKey(
        const ValueKey('family-member-arrival-opacity-mariam'),
      );
      final offset = find.byKey(
        const ValueKey('family-member-arrival-offset-mariam'),
      );
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      expect(
        tester.widget<Transform>(offset).transform.getTranslation().y,
        greaterThan(0),
      );
      expect(
        find.byKey(const ValueKey('family-member-arrival-opacity-noura')),
        findsNothing,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('family-field-interactive-viewer')),
        ),
        fieldSize,
      );

      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 140));
      expect(opacity, findsNothing);

      roster.value = List<FamilyWheelMember>.of(_members);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('family-member-arrival-opacity-mariam')),
        findsNothing,
      );
    },
  );

  testWidgets('reduced motion gives a new roster id a stationary short fade', (
    tester,
  ) async {
    final roster = ValueNotifier<List<FamilyWheelMember>>([_members.first]);
    addTearDown(roster.dispose);
    await tester.pumpWidget(_updatingWheel(roster, reduceMotion: true));
    await tester.pump();

    roster.value = _members;
    await tester.pump();

    final opacity = find.byKey(
      const ValueKey('family-member-arrival-opacity-mariam'),
    );
    final offset = find.byKey(
      const ValueKey('family-member-arrival-offset-mariam'),
    );
    final translation = tester
        .widget<Transform>(offset)
        .transform
        .getTranslation();
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    expect(translation.x, 0);
    expect(translation.y, 0);

    await tester.pump(const Duration(milliseconds: 45));
    expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
    expect(tester.widget<Transform>(offset).transform.getTranslation().y, 0);
    await tester.pump(const Duration(milliseconds: 55));
    expect(opacity, findsNothing);
  });

  testWidgets('relative tap finishes focus motion before opening the member', (
    tester,
  ) async {
    FamilyWheelMember? selected;
    await tester.pumpWidget(
      _testWheel(
        members: _members,
        disableAnimations: false,
        onMemberSelected: (member) => selected = member,
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Noura, near, 80% sealed'));
    expect(selected, isNull);
    await tester.pump(const Duration(milliseconds: 240));
    expect(selected?.id, 'noura');
  });
}

const _members = <FamilyWheelMember>[
  FamilyWheelMember(
    id: 'noura',
    name: 'Noura',
    color: Color(0xFFE4626F),
    avatar: AvatarConfig.defaults(seed: 'noura'),
    contribution: .8,
    presence: FamilyPresence.near,
  ),
  FamilyWheelMember(
    id: 'mariam',
    name: 'Mariam',
    color: Color(0xFF5B9BD5),
    avatar: AvatarConfig.defaults(seed: 'mariam'),
    contribution: .45,
    presence: FamilyPresence.far,
  ),
];

List<FamilyWheelMember> _membersForCount(int count) => List.generate(
  count,
  (index) => FamilyWheelMember(
    id: 'member-$index',
    name: 'Member $index',
    color: const Color(0xFF5B9BD5),
    avatar: AvatarConfig.defaults(seed: 'member-$index'),
    contribution: .5,
    presence: FamilyPresence.away,
  ),
);

Rect _maximumAnimatedMemberBox({required Offset center, required int index}) {
  final nodeSize = FamilyWheelGeometry.nodeSizeFor(index);
  final base = Rect.fromLTWH(
    center.dx - 48,
    center.dy - nodeSize / 2,
    96,
    nodeSize + 38,
  );
  final focused = Rect.fromCenter(
    center: base.center,
    width: base.width * 1.05,
    height: base.height * 1.05,
  );
  final maximumDrift = 2.5 + index % 3 * 1.1;
  return Rect.fromLTRB(
    focused.left - maximumDrift,
    focused.top - maximumDrift * .72,
    focused.right + maximumDrift,
    focused.bottom + maximumDrift * .72,
  );
}

Widget _updatingWheel(
  ValueListenable<List<FamilyWheelMember>> roster, {
  required bool reduceMotion,
}) => MaterialApp(
  theme: KeepersTheme.dark(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(390, 844),
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      disableAnimations: reduceMotion,
    ),
    child: ValueListenableBuilder<List<FamilyWheelMember>>(
      valueListenable: roster,
      builder: (context, members, _) => FamilyWheelScreen(
        familyName: 'Sabati family',
        currentMemberName: 'Chris',
        yourContribution: .6,
        members: members,
        onCapture: () {},
        onMemberSelected: (_) {},
      ),
    ),
  ),
);

Widget _testWheel({
  List<FamilyWheelMember> members = const [],
  bool disableAnimations = true,
  VoidCallback? onCapture,
  VoidCallback? onCurrentMemberSelected,
  ValueChanged<FamilyWheelMember>? onMemberSelected,
  AvatarConfig? currentMemberAvatar,
  String familyName = 'Sabati family',
  MediaQueryData? mediaQueryData,
  VoidCallback? onAddMember,
  VoidCallback? onNudgeMissingMembers,
  String? familyCode,
  VoidCallback? onFamilyCodeTap,
  String? pendingJoinRequestName,
  VoidCallback? onPendingJoinRequestTap,
  int weeklyPhotoCount = 0,
  WeeklyPresencePolicy weeklyPresencePolicy =
      WeeklyPresencePolicy.enforceNearby,
  bool weeklyPreviewEnabled = false,
  VoidCallback? onOpenWeeklyExperience,
  VoidCallback? onPreviewWeeklyExperience,
}) => MaterialApp(
  theme: KeepersTheme.dark(),
  home: MediaQuery(
    data:
        mediaQueryData ?? MediaQueryData(disableAnimations: disableAnimations),
    child: FamilyWheelScreen(
      familyName: familyName,
      currentMemberName: 'Chris',
      currentMemberAvatar: currentMemberAvatar,
      yourContribution: .6,
      members: members,
      onCapture: onCapture ?? () {},
      onCurrentMemberSelected: onCurrentMemberSelected,
      onMemberSelected: onMemberSelected ?? (_) {},
      onAddMember: onAddMember,
      onNudgeMissingMembers: onNudgeMissingMembers,
      familyCode: familyCode,
      onFamilyCodeTap: onFamilyCodeTap,
      pendingJoinRequestName: pendingJoinRequestName,
      onPendingJoinRequestTap: onPendingJoinRequestTap,
      weeklyPhotoCount: weeklyPhotoCount,
      weeklyPresencePolicy: weeklyPresencePolicy,
      weeklyPreviewEnabled: weeklyPreviewEnabled,
      onOpenWeeklyExperience: onOpenWeeklyExperience,
      onPreviewWeeklyExperience: onPreviewWeeklyExperience,
    ),
  ),
);
