import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
          requiredPresence: 1,
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
    'family title stays uppercase after the kept total moves to archive',
    (tester) async {
      await tester.pumpWidget(_testWheel(familyName: 'RAHMAN'));
      await tester.pump();

      final familyName = tester.widget<Text>(find.text('RAHMAN FAMILY'));

      expect(familyName.style?.fontSize, 20);
      expect(familyName.style?.fontFamily, KeepersType.primary);
      expect(familyName.style?.fontWeight, FontWeight.w600);
      expect(familyName.style?.letterSpacing, 4.1);
      expect(familyName.style?.height, 1);
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
    'family title leads presence and the invite leads the shortcuts',
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
      final invitePrompt = find.bySemanticsLabel('Ask Mariam to come');
      final firstShortcut = find.text('LEGACY LOCK');

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
        tester.getBottomLeft(invitePrompt).dy,
        lessThanOrEqualTo(tester.getTopLeft(firstShortcut).dy),
      );
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
    final invitePrompt = find.text('Ask Mariam to come');
    final firstShortcut = find.text('LEGACY LOCK');
    final secondShortcut = find.text('CAPSULE');
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
      lessThanOrEqualTo(tester.getTopLeft(invitePrompt).dy),
    );
    expect(
      tester.getBottomLeft(invitePrompt).dy,
      lessThanOrEqualTo(tester.getTopLeft(firstShortcut).dy),
    );
    expect(
      tester.getBottomLeft(invitePrompt).dy,
      lessThanOrEqualTo(tester.getTopLeft(secondShortcut).dy),
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

  testWidgets('invite prompt and shortcuts sit above the bottom navigation', (
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
    final bottomGap =
        tester.getTopLeft(navigation).dy - tester.getBottomLeft(actions).dy;
    expect(bottomGap, inInclusiveRange(8, 20));
    expect(find.text('LEGACY LOCK').hitTestable(), findsOneWidget);
    expect(find.text('CAPSULE').hitTestable(), findsOneWidget);
  });

  testWidgets('home shortcut copy wraps without clipping at phone large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    KeepersNavDestination? selected;
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
            requiredPresence: 3,
            members: _members,
            onCapture: () {},
            onMemberSelected: (_) {},
            enabledDestinations: KeepersNavDestination.values.toSet(),
            onDestinationSelected: (destination) => selected = destination,
          ),
        ),
      ),
    );
    await tester.pump();

    final card = find.bySemanticsLabel('LEGACY LOCK. No family condition yet');
    await tester.ensureVisible(card);
    await tester.pump();
    final title = _renderedParagraph(find.text('LEGACY LOCK'));
    final subtitle = _renderedParagraph(find.text('No family condition yet'));
    final cardRect = tester.getRect(card);

    for (final text in [title, subtitle]) {
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(cardRect.contains(tester.getRect(text).topLeft), isTrue);
      expect(
        cardRect.contains(
          tester.getRect(text).bottomRight - const Offset(.01, .01),
        ),
        isTrue,
      );
    }
    expect(card.hitTestable(), findsOneWidget);
    await tester.tap(card);
    await tester.pump();
    expect(selected, KeepersNavDestination.locks);
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
            requiredPresence: 3,
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
    expect(find.text('LEGACY LOCK'), findsOneWidget);
    expect(find.text('CAPSULE'), findsOneWidget);
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
            requiredPresence: 2,
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

    final gather = find.bySemanticsLabel('Ask Mohammed & Elizabeth to come');
    await tester.ensureVisible(gather);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('home-kept-forever-strip')), findsNothing);
    expect(find.text('LEGACY LOCK').hitTestable(), findsOneWidget);
    expect(find.text('CAPSULE').hitTestable(), findsOneWidget);
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

    await tester.tap(find.bySemanticsLabel('Ask Mariam to come'));

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
            requiredPresence: 1,
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

  testWidgets('home shortcuts open the existing lock and capsule routes', (
    tester,
  ) async {
    KeepersNavDestination? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: FamilyWheelScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            yourContribution: .6,
            requiredPresence: 3,
            members: _members,
            onCapture: () {},
            onMemberSelected: (_) {},
            enabledDestinations: KeepersNavDestination.values.toSet(),
            onDestinationSelected: (destination) => selected = destination,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('LEGACY LOCK'));
    await tester.pump();
    await tester.tap(find.text('LEGACY LOCK'));
    expect(selected, KeepersNavDestination.locks);
    await tester.ensureVisible(find.text('CAPSULE'));
    await tester.pump();
    await tester.tap(find.text('CAPSULE'));
    expect(selected, KeepersNavDestination.ceremony);
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
      requiredPresence: 2,
      members: members,
      onCapture: onCapture ?? () {},
      onCurrentMemberSelected: onCurrentMemberSelected,
      onMemberSelected: onMemberSelected ?? (_) {},
      onAddMember: onAddMember,
      onNudgeMissingMembers: onNudgeMissingMembers,
    ),
  ),
);

Finder _renderedParagraph(Finder sourceText) =>
    find.descendant(of: sourceText, matching: find.byType(RichText));
