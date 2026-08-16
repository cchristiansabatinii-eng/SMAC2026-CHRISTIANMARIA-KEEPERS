# Humation Avatar System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Lorelei/DiceBear and deliver persistent, offline Humation avatars that users customize from their profile and see on the Family Wheel.

**Architecture:** Keep the existing encrypted `avatar_config_json`, repository update flow, `LocalIdentity.avatar`, and shared `KeepersAvatar` boundary. Replace their Lorelei-specific content with a schema-2 Humation config, a catalog backed by the bundled Humation 1 manifest, and native `HumationAvatar` rendering. Existing Settings/editor/Family Wheel shells remain the product-owned interaction and presentation layers.

**Tech Stack:** Flutter, Dart 3.13, Riverpod 3, SQLCipher SQLite, `humation_flutter: 0.1.0`, Flutter widget tests

**Spec:** `docs/superpowers/specs/2026-09-04-humation-avatar-system-design.md`

## Global Constraints

- Pin `humation_flutter` exactly to `0.1.0`; do not embed `humation.app`, add a WebView, or make runtime avatar network calls.
- Remove direct `dicebear_core`, `dicebear_styles`, and `flutter_svg` dependencies because no other app code uses them.
- Preserve the encrypted `members.avatar_config_json` column and the existing repository/controller save boundary.
- Persist canonical Humation part IDs and normalized six-character lowercase hex values.
- Empty, invalid, unknown-version, and previous style JSON fall back deterministically using the same member UUID seed.
- Keep Wheel rings, member colors, presence dots, names, motion, zoom/pan, semantics, and geometry unchanged.
- Keep the editor's explicit Save, retry, duplicate-save guard, dirty-back confirmation, safe area, and single scroll owner.
- No cultural wardrobe, photo avatars, AI generation, export, randomize, other-member editing, or avatar cloud sync.
- Important targets remain at least 44 logical pixels and all picker tiles expose selected and tap semantics.
- Run every Flutter and Dart command from `app/`; run repository/document audit commands from the worktree root.

---

### Task 1: Humation dependency, persistent model, and catalog

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/pubspec.lock`
- Modify: `app/lib/features/members/domain/avatar_config.dart`
- Modify: `app/lib/features/members/domain/avatar_catalog.dart`
- Modify: `app/test/features/members/domain/avatar_config_test.dart`
- Modify: `app/test/features/members/domain/avatar_catalog_test.dart`
- Modify: `app/THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Consumes: `Humation.manifest`, `HumationSlot`, and `getPartsForSlot` exported by `package:humation_flutter/humation_flutter.dart`.
- Produces: `AvatarConfig.defaults({required String seed})`, `AvatarConfig.decode(String raw, {required String fallbackSeed})`, `AvatarConfig.copyWith({Map<String, String>? selections, Map<String, String>? colors})`, `AvatarCategory`, `AvatarOption`, and `avatarCatalog`.

- [ ] **Step 1: Rewrite model tests to describe schema 2 before implementation**

```dart
test('Humation config round-trips canonically', () {
  const config = AvatarConfig(
    schemaVersion: 2,
    styleId: 'humation-1',
    styleRevision: 1,
    seed: 'member-1',
    selections: {'head': 'hm1-p-000001', 'body': 'hm1-p-000020'},
    colors: {'hair': '4a3728', 'skin': 'f4c9a8'},
  );
  expect(
    AvatarConfig.decode(config.encode(), fallbackSeed: 'fallback'),
    config,
  );
});

test('previous Lorelei JSON resets to a Humation default with the member seed', () {
  const previous = '{"schemaVersion":1,"styleId":"keepers-lorelei","seed":"old"}';
  expect(
    AvatarConfig.decode(previous, fallbackSeed: 'member-1'),
    const AvatarConfig.defaults(seed: 'member-1'),
  );
});
```

- [ ] **Step 2: Rewrite catalog tests around all Humation slots and colors**

```dart
test('catalog exposes the complete Humation editor order', () {
  expect(avatarCatalog.categories, const [
    AvatarCategory.head,
    AvatarCategory.body,
    AvatarCategory.bottom,
    AvatarCategory.item,
    AvatarCategory.glasses,
    AvatarCategory.colors,
  ]);
});

test('every part option resolves to a bundled manifest part', () {
  const base = AvatarConfig.defaults(seed: 'm');
  for (final category in AvatarCategory.values.where((c) => c != AvatarCategory.colors)) {
    expect(avatarCatalog.optionsFor(category), isNotEmpty);
    for (final option in avatarCatalog.optionsFor(category)) {
      final applied = option.apply(base);
      expect(
        avatarCatalog.sanitize(applied, fallbackSeed: 'm'),
        applied,
      );
    }
  }
});
```

- [ ] **Step 3: Run the focused domain tests and record the expected compile failures**

Run:

```powershell
flutter test --no-pub test/features/members/domain/avatar_config_test.dart test/features/members/domain/avatar_catalog_test.dart
```

Expected: FAIL because the old enum, fields, and Lorelei catalog do not satisfy the Humation contracts.

- [ ] **Step 4: Replace dependencies and resolve the lockfile**

Change the dependency block to contain:

```yaml
humation_flutter: 0.1.0
```

Remove `dicebear_core`, `dicebear_styles`, and `flutter_svg`, then run:

```powershell
flutter pub get
```

Expected: `pubspec.lock` resolves `humation_flutter`, `humation`, `humation_assets_humation_1`, and `xml`, with no DiceBear packages.

- [ ] **Step 5: Implement the schema-2 immutable config**

Use a pure-data shape and canonical map handling:

```dart
enum AvatarCategory { head, body, bottom, item, glasses, colors }

final class AvatarConfig {
  static const currentSchemaVersion = 2;
  static const currentStyleId = 'humation-1';
  static const currentStyleRevision = 1;

  const AvatarConfig({
    required this.schemaVersion,
    required this.styleId,
    required this.styleRevision,
    required this.seed,
    required this.selections,
    required this.colors,
  });

  const AvatarConfig.defaults({required this.seed})
      : schemaVersion = currentSchemaVersion,
        styleId = currentStyleId,
        styleRevision = currentStyleRevision,
        selections = const {},
        colors = const {};
}
```

Decode accepts only schema 2 plus the current style/revision, normalizes keys and hex values, and otherwise returns `AvatarConfig.defaults(seed: fallbackSeed)`. Implement structural map equality and a stable hash.

- [ ] **Step 6: Implement the Humation-backed catalog**

Create part options from the bundled manifest:

```dart
final parts = getPartsForSlot(Humation.manifest, slotName);
return parts.map((part) => AvatarOption(
  id: part.id,
  label: humanize(part.name),
  category: category,
  apply: (config) => config.withSelection(slotName, part.id),
));
```

Add fixed color swatches for `hair`, `skin`, `clothes`, and `bottom`. `sanitize` retains only manifest-valid part IDs, supported color keys, normalized hex values, the original non-empty seed, and current schema metadata. Define fixed, distinct seed/config presets for Noura, Mariam, Youssef, and Layla.

- [ ] **Step 7: Replace third-party notices**

Remove DiceBear/Lorelei notices and record the official Humation MIT asset/engine license plus the community Flutter port MIT license and repository links.

- [ ] **Step 8: Run and commit Task 1**

Run:

```powershell
dart format lib/features/members/domain test/features/members/domain
flutter test --no-pub test/features/members/domain/avatar_config_test.dart test/features/members/domain/avatar_catalog_test.dart
flutter analyze --no-pub
```

Expected: all focused tests pass and analysis reports no issues.

Commit:

```powershell
git add app/pubspec.yaml app/pubspec.lock app/lib/features/members/domain/avatar_config.dart app/lib/features/members/domain/avatar_catalog.dart app/test/features/members/domain/avatar_config_test.dart app/test/features/members/domain/avatar_catalog_test.dart app/THIRD_PARTY_NOTICES.md
git commit -m "feat: replace avatar model with Humation"
```

---

### Task 2: Native renderer and visible avatar surfaces

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/features/members/presentation/widgets/keepers_avatar.dart`
- Modify: `app/lib/features/members/presentation/member_page_screen.dart`
- Modify: `app/lib/ui/family_wheel_screen.dart`
- Modify: `app/lib/features/vault/presentation/observatory_screen.dart`
- Modify: `app/test/features/members/presentation/keepers_avatar_test.dart`
- Modify: `app/test/features/members/presentation/member_page_screen_test.dart`
- Modify: `app/test/ui/family_wheel_screen_test.dart`
- Modify: `app/test/features/vault/presentation/observatory_screen_test.dart`

**Interfaces:**
- Consumes: schema-2 `AvatarConfig` and `avatarCatalog` from Task 1.
- Produces: `KeepersAvatar({required AvatarConfig config, required double size, KeepersAvatarCrop crop, String? semanticLabel})`, backed synchronously by `HumationAvatar`.

- [ ] **Step 1: Replace renderer tests before implementation**

```dart
testWidgets('KeepersAvatar renders the configured Humation identity locally', (tester) async {
  const config = AvatarConfig.defaults(seed: 'member-1');
  await tester.pumpWidget(const MaterialApp(
    home: KeepersAvatar(config: config, size: 96),
  ));
  final avatar = tester.widget<HumationAvatar>(find.byType(HumationAvatar));
  expect(avatar.seed, 'member-1');
  expect(find.byType(Image), findsNothing);
});
```

Update Wheel and member-page tests to assert `HumationAvatar` descendants and the current member's exact config while preserving existing geometry, no-shadow, motion, and semantic-action assertions.

- [ ] **Step 2: Run focused renderer/surface tests and record the expected failures**

Run:

```powershell
flutter test --no-pub test/features/members/presentation/keepers_avatar_test.dart test/features/members/presentation/member_page_screen_test.dart test/ui/family_wheel_screen_test.dart
```

Expected: FAIL while `KeepersAvatar` still imports DiceBear and member detail still uses the handmade faceless avatar.

- [ ] **Step 3: Replace the shared renderer**

Implement the Humation boundary:

```dart
HumationAvatar(
  seed: config.seed,
  selections: config.selections,
  colors: config.colors,
  size: size,
)
```

Keep artwork decorative when no `semanticLabel` is provided, preserve a labeled semantics wrapper when it is, and retain a neutral fixed-size fallback if the package throws. Delete all SVG generator/cache/mapper types.

- [ ] **Step 4: Prewarm and reuse the renderer on every in-scope surface**

Call `Humation.prewarm()` before `runApp`. Continue passing `identity.avatar` into the Wheel. Use `avatarCatalog.demoFor(member.id)` for demo relatives. Replace `_FacelessAvatar` on `MemberPageScreen` with `KeepersAvatar` while retaining the page's ring and member accent.

- [ ] **Step 5: Run and commit Task 2**

Run:

```powershell
dart format lib/main.dart lib/features/members/presentation lib/ui/family_wheel_screen.dart lib/features/vault/presentation/observatory_screen.dart test/features/members/presentation test/ui/family_wheel_screen_test.dart test/features/vault/presentation/observatory_screen_test.dart
flutter test --no-pub test/features/members/presentation/keepers_avatar_test.dart test/features/members/presentation/member_page_screen_test.dart test/ui/family_wheel_screen_test.dart test/features/vault/presentation/observatory_screen_test.dart
flutter analyze --no-pub
```

Expected: all focused tests pass and analysis reports no issues.

Commit:

```powershell
git add app/lib/main.dart app/lib/features/members/presentation/widgets/keepers_avatar.dart app/lib/features/members/presentation/member_page_screen.dart app/lib/ui/family_wheel_screen.dart app/lib/features/vault/presentation/observatory_screen.dart app/test/features/members/presentation/keepers_avatar_test.dart app/test/features/members/presentation/member_page_screen_test.dart app/test/ui/family_wheel_screen_test.dart app/test/features/vault/presentation/observatory_screen_test.dart
git commit -m "feat: render Humation avatars across profiles"
```

---

### Task 3: Humation profile editor and encrypted save flow

**Files:**
- Modify: `app/lib/features/members/application/avatar_editor_controller.dart`
- Modify: `app/lib/features/members/presentation/avatar_editor_screen.dart`
- Modify: `app/lib/features/settings/presentation/settings_screen.dart`
- Modify: `app/test/features/members/application/avatar_editor_controller_test.dart`
- Modify: `app/test/features/members/presentation/avatar_editor_screen_test.dart`
- Modify: `app/test/features/settings/presentation/settings_screen_test.dart`
- Modify: `app/test/features/onboarding/data/setup_repositories_test.dart`

**Interfaces:**
- Consumes: `AvatarOption.apply`, `avatarCatalog.sanitize`, `MemberRepository.updateAvatar`, and `localIdentityProvider`.
- Produces: the existing `avatarEditorControllerProvider(identity)` save contract and a full-screen `AvatarEditorScreen(identity: identity)` with six Humation categories.

- [ ] **Step 1: Rewrite editor tests for Humation controls and previews**

```dart
testWidgets('editor exposes every Humation category', (tester) async {
  await pumpEditor(tester);
  for (final label in ['Head', 'Body', 'Bottom', 'Item', 'Glasses', 'Colors']) {
    expect(find.text(label), findsWidgets);
  }
  expect(find.text('Looks'), findsNothing);
  expect(find.text('Face'), findsNothing);
  expect(find.text('Hair'), findsNothing);
});

testWidgets('semantic part selection updates the live preview', (tester) async {
  await pumpEditor(tester);
  final before = tester.widget<KeepersAvatar>(
    find.byKey(const ValueKey('avatar-editor-preview')),
  ).config;
  final tile = find.bySemanticsLabel(contains('avatar option'));
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    tester.getSemantics(tile.first).id,
    SemanticsAction.tap,
  );
  await tester.pump();
  final after = tester.widget<KeepersAvatar>(
    find.byKey(const ValueKey('avatar-editor-preview')),
  ).config;
  expect(after, isNot(before));
});

testWidgets('save writes the selected avatar once', (tester) async {
  await pumpEditor(tester);
  final tile = find.bySemanticsLabel(contains('avatar option'));
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    tester.getSemantics(tile.first).id,
    SemanticsAction.tap,
  );
  await tester.pump();
  await tester.tap(find.text('Save avatar'));
  expect(fakeSave.calls, 1);
});
```

Retain the existing failure/retry, dirty-back, double-save, keyboard, 390 x 844, 430 x 932, and 1.4x text cases with Humation IDs.

- [ ] **Step 2: Run editor/controller/settings tests and record expected failures**

Run:

```powershell
flutter test --no-pub test/features/members/application/avatar_editor_controller_test.dart test/features/members/presentation/avatar_editor_screen_test.dart test/features/settings/presentation/settings_screen_test.dart
```

Expected: FAIL because the screen and fixtures still use Lorelei categories and recipes.

- [ ] **Step 3: Adapt controller and fixtures without changing save semantics**

Keep `AvatarSavePhase`, `isDirty`, `canSave`, the single `_inFlightSave`, exact failure copy, repository write, and identity invalidation. Update only option/config construction to schema 2. Add repository coverage proving a previous-style row reads as `AvatarConfig.defaults(seed: memberId)` and a saved Humation config survives reload.

- [ ] **Step 4: Rebuild the editor's category content**

Replace the category extension and tile rendering with the six Humation categories. Part tiles render `KeepersAvatar` using `option.apply(currentDraft)`. Color options render a clear swatch plus text while the large preview shows the whole result. Preserve selected border/check, semantic `onTap`, disabled/saving behavior, one scroll owner, and fixed footer.

- [ ] **Step 5: Verify Settings refresh and save destination**

Keep the `Your identity` row and route push. The successful save must pop only the editor, keep Settings selected, refresh the avatar in the identity row, and show the same config after navigating back to the Wheel.

- [ ] **Step 6: Run and commit Task 3**

Run:

```powershell
dart format lib/features/members/application lib/features/members/presentation/avatar_editor_screen.dart lib/features/settings/presentation/settings_screen.dart test/features/members/application test/features/members/presentation/avatar_editor_screen_test.dart test/features/settings test/features/onboarding/data/setup_repositories_test.dart
flutter test --no-pub test/features/members/application/avatar_editor_controller_test.dart test/features/members/presentation/avatar_editor_screen_test.dart test/features/settings/presentation/settings_screen_test.dart test/features/onboarding/data/setup_repositories_test.dart
flutter analyze --no-pub
```

Expected: all focused tests pass and analysis reports no issues.

Commit:

```powershell
git add app/lib/features/members/application/avatar_editor_controller.dart app/lib/features/members/presentation/avatar_editor_screen.dart app/lib/features/settings/presentation/settings_screen.dart app/test/features/members/application/avatar_editor_controller_test.dart app/test/features/members/presentation/avatar_editor_screen_test.dart app/test/features/settings/presentation/settings_screen_test.dart app/test/features/onboarding/data/setup_repositories_test.dart
git commit -m "feat: add Humation profile customizer"
```

---

### Task 4: Remove Lorelei residue and verify the Android experience

**Files:**
- Delete: `docs/superpowers/specs/2026-09-04-lorelei-avatar-system-design.md`
- Delete: `docs/superpowers/plans/2026-09-04-lorelei-avatar-system.md`
- Modify: `DESIGN.md`
- Modify: `UX-CONTRACT.md`

**Interfaces:**
- Consumes: completed Humation renderer/editor/persistence system from Tasks 1-3.
- Produces: a Lorelei-free product contract, clean full suite, Android build, and emulator screenshots.

- [ ] **Step 1: Remove obsolete documents and update maintained contracts**

Delete the superseded Lorelei spec/plan. Add to `DESIGN.md` that Humation's restrained hand-drawn full-character linework is the avatar language, while member accent colors remain outside the artwork. Add the profile-edit flow to the `UX-CONTRACT.md` ledger with save, failure, and focus outcomes.

- [ ] **Step 2: Run a residue scan**

Run:

```powershell
rg -n -i "lorelei|dicebear|keepers-lorelei|SvgPicture" app/lib app/test app/pubspec.yaml app/THIRD_PARTY_NOTICES.md DESIGN.md UX-CONTRACT.md
```

Expected: no production, dependency, notice, or current-contract matches. One explicit legacy JSON fixture in the migration test is permitted.

- [ ] **Step 3: Run static and automated verification**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
python "C:\Users\Chris\.codex\plugins\cache\openai-curated-remote\frontend-design-premium\1.4.0\skills\frontend-design-premium\scripts\audit_project.py" . --mode strict
flutter build apk --debug --no-pub
```

Expected: formatter unchanged, no analysis issues, all tests pass, strict audit has zero blocking findings, and the APK builds.

- [ ] **Step 4: Exercise the real emulator flow**

Install and open the debug APK. Verify:

1. Wheel shows distinct Humation avatars without changing bubble geometry.
2. Settings shows the current Humation avatar and opens the editor.
3. Every category changes the live preview.
4. Save returns to Settings and persists after app restart.
5. Wheel reflects the saved avatar.
6. Dirty back, save failure/retry, 390 x 844, 430 x 932, 1.4x text, and reduced motion remain usable.

Capture Wheel, Settings, and editor screenshots under `outputs/humation-avatar/` and visually inspect cropping, contrast, labels, overflow, touch geometry, and consistency with the background/navigation system.

- [ ] **Step 5: Commit Task 4**

```powershell
git add DESIGN.md UX-CONTRACT.md docs/superpowers app/lib app/test app/pubspec.yaml app/pubspec.lock app/THIRD_PARTY_NOTICES.md
git commit -m "chore: complete Humation avatar migration"
```
