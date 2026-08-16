# P0-03 Capture and Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first complete one-device Keepers loop: create a local family/member, capture photo/voice/text memories, encrypt them with the correct privacy key, and reopen them from the solo Observatory after relaunch.

**Architecture:** Extend the existing Riverpod + SQLCipher foundation with focused `features/onboarding`, `features/capture`, and `features/vault` slices. Keep encryption and file finalization behind repository/service boundaries, then project stored metadata into a pure Observatory scene model so later visual iterations do not change domain or persistence contracts.

**Tech Stack:** Flutter 3 / Dart 3.13, Riverpod 3.4, SQLCipher via `sqflite_sqlcipher`, Keychain/Keystore via `flutter_secure_storage`, AES-256-GCM via `cryptography` + `cryptography_flutter`, `image_picker`, `record`, `audioplayers`, UUID v4, Flutter unit/widget/integration tests.

**Spec:** `docs/superpowers/specs/2026-09-01-p0-03-capture-vault-design.md`

## Global Constraints

- A memory has exactly one primary format: `photo`, `voice`, or `text`; the caption is optional and encrypted inside the payload.
- The privacy selector is always visible and defaults to `Weekly Reveal`.
- `journal` resolves the author member key; `reveal` and `legacy` resolve the family key.
- Entry payloads use AES-256-GCM with a fresh 96-bit nonce and authenticated entry/family/author/type/privacy/timestamp metadata.
- Only relative encrypted blob references are stored in SQLCipher; primary content, caption, and text never enter plaintext database columns.
- Save success and the seal animation occur only after encrypted-file finalization and SQLCipher insertion complete.
- A failed insert removes the finalized encrypted blob; save/discard removes capture plaintext; duplicate Save taps create one entry.
- First run creates one family and one `adult` member; the solo Observatory never invents other members.
- The v0 visual target is the selected “Living Orrery” direction, but tokens, orbit layout, motion, and format renderers remain replaceable for later design iterations.
- Fraunces is used for emotional/memory copy; Schibsted Grotesk is used for controls and metadata.
- Brass `#C9A227` is reserved for sealing/permanence; member color is stable identity; daylight and reduced-motion modes are functional.
- The near-black ground uses one real, bundled raster grain texture; do not approximate visible assets with emoji, handcrafted SVG, generic boxes, or procedural surrogate art.
- Do not use purple-blue gradients, glassmorphism, confetti, generic card grids, or a floating action button.
- Touch targets are at least 44 logical pixels; the layout remains usable at 1.4x text scaling; the vault list supplies deterministic reading/focus order.
- Android minimum SDK remains 24; validate on one physical Android device and one physical iOS device.
- Do not implement invitations, fake members, BLE/quorum/ceremony behavior, transcription, embeddings, sync, scan, recipe, edit, or delete.

## File Structure

### Existing files to modify

- `app/pubspec.yaml` — add capture, playback, cryptography, UUID, integration-test, and font assets.
- `app/lib/app.dart` — use the Observatory themes and replace the current landing screen with `StartupGate`.
- `app/lib/storage/database_key_store.dart` — add secure-value deletion.
- `app/lib/storage/schema.dart` — add schema v2 member-key/color fields.
- `app/lib/storage/database_providers.dart` — expose dependencies reused by feature providers.
- `app/android/app/src/main/AndroidManifest.xml` — declare camera and microphone permissions.
- `app/ios/Runner/Info.plist` — add photo-library, camera, and microphone usage copy.
- `app/test/app_test.dart` — replace the original landing-screen assertion with startup routing coverage.
- `docs/implementation-board.md` — mark P0-03 only after automation and both physical-device checks pass.

### New foundation and design-system files

- `app/assets/fonts/Fraunces.ttf`, `app/assets/fonts/SchibstedGrotesk.ttf`, and `app/assets/fonts/OFL.txt` — bundled OFL fonts for offline rendering.
- `app/assets/textures/observatory-grain.png` — seamless low-contrast raster grain for the near-black Observatory ground.
- `app/lib/design_system/observatory/observatory_theme.dart` — dark/daylight themes plus brass, member-color, surface, typography, and motion tokens.
- `app/lib/design_system/observatory/orbit_scene.dart` — storage-independent member and memory scene records.
- `app/lib/design_system/observatory/orbit_layout.dart` — pure orbit geometry.
- `app/lib/design_system/observatory/motion_policy.dart` — normal/reduced-motion decisions.
- `app/lib/design_system/observatory/observatory_view.dart` — presentation-only orbital scene.

### New onboarding files

- `app/lib/features/onboarding/domain/local_identity.dart` — setup input, created keys, and current local identity models.
- `app/lib/features/onboarding/data/family_repository.dart` — family SQL.
- `app/lib/features/onboarding/data/member_repository.dart` — member SQL and identity lookup.
- `app/lib/features/onboarding/data/identity_key_service.dart` — family/member key create, resolve, and rollback.
- `app/lib/features/onboarding/application/onboarding_providers.dart` — repository, clock, UUID, identity, and setup providers.
- `app/lib/features/onboarding/application/setup_controller.dart` — validation and recoverable setup orchestration.
- `app/lib/features/onboarding/presentation/startup_gate.dart` — loading/error/setup/Observatory routing.
- `app/lib/features/onboarding/presentation/setup_screen.dart` — minimal two-field first run.

### New capture files

- `app/lib/features/capture/domain/capture_models.dart` — formats, privacy tiers, draft state, metadata, payload, and save request/result.
- `app/lib/features/capture/data/entry_payload_codec.dart` — canonical version-one payload serialization.
- `app/lib/features/capture/data/entry_cipher.dart` — AES-GCM envelope and authenticated metadata.
- `app/lib/features/capture/data/entry_key_resolver.dart` — privacy-tier key routing.
- `app/lib/features/capture/data/encrypted_blob_store.dart` — encrypted staging/finalization/rollback.
- `app/lib/features/capture/data/entry_repository.dart` — entry metadata inserts.
- `app/lib/features/capture/data/entry_persistence_service.dart` — ordered secure-save transaction and cleanup.
- `app/lib/features/capture/data/photo_capture_adapter.dart` — camera/library picker boundary and Android lost-data recovery.
- `app/lib/features/capture/data/voice_capture_adapter.dart` — microphone recording boundary, duration/amplitude, and cleanup.
- `app/lib/features/capture/data/audio_playback_adapter.dart` — pre-save and opened-memory audio playback.
- `app/lib/features/capture/application/capture_providers.dart` — injectable adapter/service providers.
- `app/lib/features/capture/application/capture_controller.dart` — draft transitions, validation, permissions, save, and duplicate suppression.
- `app/lib/features/capture/presentation/capture_sheet.dart` — format picker, content editors, caption, privacy selector, error/progress/discard states.

### New vault and Observatory composition files

- `app/lib/features/vault/domain/vault_models.dart` — ordered metadata and in-memory opened payload.
- `app/lib/features/vault/data/vault_repository.dart` — local-family entry queries.
- `app/lib/features/vault/application/vault_providers.dart` — ordered metadata and viewer controller providers.
- `app/lib/features/vault/application/vault_controller.dart` — key resolution, authenticated decrypt, payload decode, and unavailable states.
- `app/lib/features/vault/presentation/vault_list.dart` — deterministic accessible list.
- `app/lib/features/vault/presentation/memory_viewer.dart` — photo, voice, and text renderers behind one format switch.
- `app/lib/features/vault/presentation/observatory_screen.dart` — current-member node, orbital marks, Add Memory entry point, seal feedback, and vault fallback.

### New tests and evidence

- Unit tests mirror each data/application file under `app/test/`.
- Widget tests cover setup, capture, Observatory, vault list/viewers, semantics, 1.4x text, daylight, and reduced motion.
- `app/integration_test/p0_capture_flow_test.dart` — clean-install setup, text save, provider restart, and reopen.
- `docs/evidence/p0-03-device-gate.md` — exact Android/iOS manual evidence matrix.

---

### Task 1: Offline visual foundation and platform dependencies

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/app.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/ios/Runner/Info.plist`
- Create: `app/assets/fonts/Fraunces.ttf`
- Create: `app/assets/fonts/SchibstedGrotesk.ttf`
- Create: `app/assets/fonts/OFL.txt`
- Create: `app/assets/textures/observatory-grain.png`
- Create: `app/lib/design_system/observatory/observatory_theme.dart`
- Test: `app/test/design_system/observatory_theme_test.dart`

**Interfaces:**
- Consumes: existing `KeepersApp` and Flutter Material theming.
- Produces: `ObservatoryTokens`, `KeepersTheme.dark()`, and `KeepersTheme.daylight()` for all later presentation tasks.

- [ ] **Step 1: Write the failing token and typography test**

```dart
testWidgets('Observatory themes expose stable identity and typography', (tester) async {
  await tester.pumpWidget(MaterialApp(theme: KeepersTheme.dark(), home: const SizedBox()));
  final context = tester.element(find.byType(SizedBox));
  final tokens = Theme.of(context).extension<ObservatoryTokens>()!;

  expect(tokens.brass, const Color(0xFFC9A227));
  expect(tokens.memberColors['ochre'], isNotNull);
  expect(Theme.of(context).textTheme.bodyMedium!.fontFamily, 'Schibsted Grotesk');
  expect(Theme.of(context).textTheme.headlineMedium!.fontFamily, 'Fraunces');

  final daylight = KeepersTheme.daylight();
  expect(daylight.brightness, Brightness.light);
  expect(daylight.extension<ObservatoryTokens>()!.brass, tokens.brass);
  for (final theme in [KeepersTheme.dark(), KeepersTheme.daylight()]) {
    final values = theme.extension<ObservatoryTokens>()!;
    for (final color in values.memberColors.values) {
      expect(_contrastRatio(color, values.ground), greaterThanOrEqualTo(3));
    }
  }
});

double _contrastRatio(Color a, Color b) {
  final lighter = max(a.computeLuminance(), b.computeLuminance());
  final darker = min(a.computeLuminance(), b.computeLuminance());
  return (lighter + .05) / (darker + .05);
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `cd app && flutter test test/design_system/observatory_theme_test.dart`

Expected: FAIL because `observatory_theme.dart`, `KeepersTheme`, and `ObservatoryTokens` do not exist.

- [ ] **Step 3: Add exact dependencies and offline font declarations**

```yaml
dependencies:
  audioplayers: ^6.8.1
  cryptography: ^2.9.0
  cryptography_flutter: ^2.3.4
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.4.2
  flutter_secure_storage: ^11.0.0
  image_picker: ^1.2.3
  path: ^1.9.1
  path_provider: ^2.1.6
  record: ^7.1.1
  sqflite_sqlcipher: ^3.4.1
  uuid: ^4.6.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  sqflite_common: ^2.5.11
  sqflite_common_ffi: ^2.4.2+1

flutter:
  uses-material-design: true
  assets:
    - assets/textures/observatory-grain.png
  fonts:
    - family: Fraunces
      fonts:
        - asset: assets/fonts/Fraunces.ttf
    - family: Schibsted Grotesk
      fonts:
        - asset: assets/fonts/SchibstedGrotesk.ttf
```

Download and commit the official OFL assets; do not enable runtime font fetching:

```bash
mkdir -p app/assets/fonts
curl -L 'https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/Fraunces%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf' -o app/assets/fonts/Fraunces.ttf
curl -L 'https://raw.githubusercontent.com/google/fonts/main/ofl/schibstedgrotesk/SchibstedGrotesk%5Bwght%5D.ttf' -o app/assets/fonts/SchibstedGrotesk.ttf
curl -L 'https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/OFL.txt' -o app/assets/fonts/OFL.txt
```

Use the `imagegen` skill once to create `app/assets/textures/observatory-grain.png` at 512×512 with this exact direction: “seamless monochrome film grain texture, transparent-to-near-black, extremely subtle low contrast, no shapes, no stars, no vignette, no text, tileable edges.” Inspect the raster at original resolution and reject it if a visible seam, object, or high-contrast speck appears.

- [ ] **Step 4: Implement the theme extension and dark/daylight themes**

```dart
@immutable
final class ObservatoryTokens extends ThemeExtension<ObservatoryTokens> {
  const ObservatoryTokens({
    required this.brass,
    required this.ground,
    required this.memorySurface,
    required this.memberColors,
    required this.idleDrift,
    required this.sealDuration,
  });

  final Color brass;
  final Color ground;
  final Color memorySurface;
  final Map<String, Color> memberColors;
  final double idleDrift;
  final Duration sealDuration;

  Color memberColor(String token) => memberColors[token] ?? memberColors['ochre']!;

  @override
  ObservatoryTokens copyWith({
    Color? brass,
    Color? ground,
    Color? memorySurface,
    Map<String, Color>? memberColors,
    double? idleDrift,
    Duration? sealDuration,
  }) => ObservatoryTokens(
    brass: brass ?? this.brass,
    ground: ground ?? this.ground,
    memorySurface: memorySurface ?? this.memorySurface,
    memberColors: memberColors ?? this.memberColors,
    idleDrift: idleDrift ?? this.idleDrift,
    sealDuration: sealDuration ?? this.sealDuration,
  );

  @override
  ObservatoryTokens lerp(covariant ObservatoryTokens? other, double t) {
    if (other == null) return this;
    return ObservatoryTokens(
      brass: Color.lerp(brass, other.brass, t)!,
      ground: Color.lerp(ground, other.ground, t)!,
      memorySurface: Color.lerp(memorySurface, other.memorySurface, t)!,
      memberColors: memberColors,
      idleDrift: lerpDouble(idleDrift, other.idleDrift, t)!,
      sealDuration: t < .5 ? sealDuration : other.sealDuration,
    );
  }
}

final class KeepersTheme {
  static const _brass = Color(0xFFC9A227);
  static const _darkMemberColors = <String, Color>{
    'ochre': Color(0xFFD29B42),
    'sage': Color(0xFF8FA77A),
    'clay': Color(0xFFC67961),
    'sea': Color(0xFF5D93A6),
  };
  static const _daylightMemberColors = <String, Color>{
    'ochre': Color(0xFF765015),
    'sage': Color(0xFF48643A),
    'clay': Color(0xFF854331),
    'sea': Color(0xFF2E6173),
  };

  static ThemeData dark() => _build(
    Brightness.dark,
    const Color(0xFF10120F),
    const Color(0xFF1A1D18),
    _darkMemberColors,
  );
  static ThemeData daylight() => _build(
    Brightness.light,
    const Color(0xFFF4F0E5),
    const Color(0xFFFFFCF3),
    _daylightMemberColors,
  );

  static ThemeData _build(
    Brightness brightness,
    Color ground,
    Color memorySurface,
    Map<String, Color> memberColors,
  ) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: memberColors['sage']!, brightness: brightness),
      scaffoldBackgroundColor: ground,
      fontFamily: 'Schibsted Grotesk',
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(fontFamily: 'Fraunces'),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontFamily: 'Fraunces'),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontFamily: 'Fraunces'),
      ),
      extensions: <ThemeExtension<dynamic>>[
        ObservatoryTokens(
          brass: _brass,
          ground: ground,
          memorySurface: memorySurface,
          memberColors: memberColors,
          idleDrift: 4,
          sealDuration: const Duration(milliseconds: 420),
        ),
      ],
    );
  }
}
```

Update `KeepersApp` to use `theme: KeepersTheme.dark()` and `darkTheme: KeepersTheme.dark()`; Task 4 replaces the temporary `HomeScreen`.

- [ ] **Step 5: Add platform permission copy**

```xml
<!-- AndroidManifest.xml, as direct children of <manifest> -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<!-- Info.plist, inside <dict> -->
<key>NSCameraUsageDescription</key>
<string>Keepers uses the camera when you choose to capture a photo memory.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Keepers lets you choose a photo memory from your library.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Keepers uses the microphone when you choose to record a voice memory.</string>
```

- [ ] **Step 6: Fetch packages, format, analyze, and run the test**

Run: `cd app && flutter pub get && dart format lib test && flutter analyze && flutter test test/design_system/observatory_theme_test.dart`

Expected: dependency resolution succeeds, analyze reports no issues, and the theme test passes.

- [ ] **Step 7: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/assets/fonts app/lib/app.dart app/lib/design_system app/android/app/src/main/AndroidManifest.xml app/ios/Runner/Info.plist app/test/design_system
git commit -m "feat: add offline Observatory visual foundation"
```

### Task 2: Schema v2 and recoverable secure values

**Files:**
- Modify: `app/lib/storage/database_key_store.dart`
- Modify: `app/lib/storage/schema.dart`
- Modify: `app/test/storage/database_key_store_test.dart`
- Modify: `app/test/storage/schema_test.dart`

**Interfaces:**
- Consumes: existing `SecureValueStore`, `KeepersSchema.statementsForUpgrade`, and SQLCipher open/upgrade callbacks.
- Produces: `SecureValueStore.delete(String key)`, schema version 2, `KeepersSchema.versionTwoStatements`, nullable `members.member_key_ref`, and non-null `members.color_token`.

- [ ] **Step 1: Add failing schema-v2 and secure-delete tests**

```dart
test('v2 upgrades members with key reference and stable color', () async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  addTearDown(database.close);
  for (final statement in KeepersSchema.versionOneStatements) {
    await database.execute(statement);
  }
  for (final statement in KeepersSchema.statementsForUpgrade(1, 2)) {
    await database.execute(statement);
  }
  final columns = await database.rawQuery('PRAGMA table_info(members)');
  expect(columns.map((row) => row['name']), containsAll(['member_key_ref', 'color_token']));
  final color = columns.singleWhere((row) => row['name'] == 'color_token');
  expect(color['notnull'], 1);
  expect(color['dflt_value'], "'ochre'");
});

test('secure values can be deleted for rollback', () async {
  final store = _MemorySecureValueStore()..values['temporary'] = 'secret';
  await store.delete('temporary');
  expect(await store.read('temporary'), isNull);
});
```

- [ ] **Step 2: Run the storage tests and confirm they fail**

Run: `cd app && flutter test test/storage/schema_test.dart test/storage/database_key_store_test.dart`

Expected: FAIL because schema version 2 and `SecureValueStore.delete` are absent.

- [ ] **Step 3: Add deletion to the secure-store abstraction**

```dart
abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

@override
Future<void> delete(String key) => _storage.delete(key: key);
```

Add the same method to every in-memory fake:

```dart
@override
Future<void> delete(String key) async {
  values.remove(key);
}
```

- [ ] **Step 4: Implement the sequential schema migration**

```dart
static const int version = 2;

static const List<String> versionTwoStatements = [
  'ALTER TABLE members ADD COLUMN member_key_ref TEXT',
  "ALTER TABLE members ADD COLUMN color_token TEXT NOT NULL DEFAULT 'ochre'",
];

if (oldVersion < 1 && newVersion >= 1) {
  statements.addAll(versionOneStatements);
}
if (oldVersion < 2 && newVersion >= 2) {
  statements.addAll(versionTwoStatements);
}
```

Update upgrade assertions so `0 -> 2` returns v1 followed by v2, `1 -> 2` returns only v2, and same-version/backward/out-of-range upgrades throw.

- [ ] **Step 5: Run the complete storage suite**

Run: `cd app && dart format lib/storage test/storage && flutter analyze && flutter test test/storage`

Expected: all storage tests pass and both fresh-create `0 -> 2` and upgrade `1 -> 2` paths execute.

- [ ] **Step 6: Commit**

```bash
git add app/lib/storage app/test/storage
git commit -m "feat: add member key and color schema migration"
```

### Task 3: Identity keys and setup repositories

**Files:**
- Create: `app/lib/features/onboarding/domain/local_identity.dart`
- Create: `app/lib/features/onboarding/data/family_repository.dart`
- Create: `app/lib/features/onboarding/data/member_repository.dart`
- Create: `app/lib/features/onboarding/data/identity_key_service.dart`
- Create: `app/lib/features/onboarding/application/onboarding_providers.dart`
- Modify: `app/lib/storage/database_providers.dart`
- Test: `app/test/features/onboarding/data/identity_key_service_test.dart`
- Test: `app/test/features/onboarding/data/setup_repositories_test.dart`

**Interfaces:**
- Consumes: `SecureValueStore.read/write/delete`, `databaseProvider`, SQL `families`/`members`, `Uuid.v4()`, and a UTC clock.
- Produces: `SetupInput`, `CreatedIdentityKeys`, `LocalIdentity`, `IdentityKeyService.createFor/resolve/rollback`, `FamilyRepository.insert`, `MemberRepository.insert/findLocalIdentity`, and `localIdentityProvider`.

- [ ] **Step 1: Write failing key creation, routing, and rollback tests**

```dart
test('creates independent 256-bit keys with stable references', () async {
  final store = MemorySecureValueStore();
  var nextByte = 1;
  final service = IdentityKeyService(
    store,
    randomBytesFactory: (length) => List<int>.filled(length, nextByte++),
  );

  final keys = await service.createFor(familyId: 'family-1', memberId: 'member-1');

  expect(keys.familyKeyRef, 'keepers.family.family-1.entry-key.v1');
  expect(keys.memberKeyRef, 'keepers.member.member-1.entry-key.v1');
  expect(await service.resolve(keys.familyKeyRef), hasLength(32));
  expect(await service.resolve(keys.memberKeyRef), hasLength(32));
  expect(await service.resolve(keys.familyKeyRef), isNot(await service.resolve(keys.memberKeyRef)));
});

test('rolls back both references when setup cannot commit', () async {
  final store = MemorySecureValueStore();
  final service = IdentityKeyService(store, randomBytesFactory: (length) => List<int>.filled(length, 7));
  final keys = await service.createFor(familyId: 'f', memberId: 'm');
  await service.rollback(keys);
  expect(await store.read(keys.familyKeyRef), isNull);
  expect(await store.read(keys.memberKeyRef), isNull);
});
```

- [ ] **Step 2: Write a failing repository round-trip test**

```dart
test('family and adult member round-trip as one local identity', () async {
  final db = await openSchemaV2Database();
  addTearDown(db.close);
  final families = FamilyRepository();
  final members = MemberRepository();

  await db.transaction((txn) async {
    await families.insert(
      txn,
      id: 'family-1',
      name: 'Sabati',
      familyKeyRef: 'family-key',
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await members.insert(
      txn,
      id: 'member-1',
      familyId: 'family-1',
      name: 'Chris',
      memberKeyRef: 'member-key',
      colorToken: 'ochre',
      createdAt: DateTime.utc(2026, 9, 1),
    );
  });

  expect(
    await members.findLocalIdentity(db),
    const LocalIdentity(
      familyId: 'family-1',
      familyName: 'Sabati',
      familyKeyRef: 'family-key',
      memberId: 'member-1',
      memberName: 'Chris',
      memberKeyRef: 'member-key',
      colorToken: 'ochre',
    ),
  );
});
```

- [ ] **Step 3: Run the tests and confirm missing-interface failures**

Run: `cd app && flutter test test/features/onboarding/data`

Expected: FAIL because the onboarding models, repositories, and key service do not exist.

- [ ] **Step 4: Implement immutable identity models**

```dart
final class SetupInput {
  const SetupInput({required this.familyName, required this.memberName});
  final String familyName;
  final String memberName;
  bool get isValid => familyName.trim().isNotEmpty && memberName.trim().isNotEmpty;
}

final class CreatedIdentityKeys {
  const CreatedIdentityKeys({required this.familyKeyRef, required this.memberKeyRef});
  final String familyKeyRef;
  final String memberKeyRef;
}

final class LocalIdentity {
  const LocalIdentity({
    required this.familyId,
    required this.familyName,
    required this.familyKeyRef,
    required this.memberId,
    required this.memberName,
    required this.memberKeyRef,
    required this.colorToken,
  });
  final String familyId;
  final String familyName;
  final String familyKeyRef;
  final String memberId;
  final String memberName;
  final String memberKeyRef;
  final String colorToken;

  @override
  bool operator ==(Object other) => other is LocalIdentity &&
      other.familyId == familyId &&
      other.familyName == familyName &&
      other.familyKeyRef == familyKeyRef &&
      other.memberId == memberId &&
      other.memberName == memberName &&
      other.memberKeyRef == memberKeyRef &&
      other.colorToken == colorToken;

  @override
  int get hashCode => Object.hash(
    familyId, familyName, familyKeyRef, memberId, memberName, memberKeyRef, colorToken,
  );
}
```

- [ ] **Step 5: Implement identity-key creation, resolution, and rollback**

```dart
final class IdentityKeyService {
  IdentityKeyService(this._store, {RandomBytesFactory? randomBytesFactory})
      : _randomBytesFactory = randomBytesFactory ?? _secureBytes;

  final SecureValueStore _store;
  final RandomBytesFactory _randomBytesFactory;

  Future<CreatedIdentityKeys> createFor({required String familyId, required String memberId}) async {
    final familyRef = 'keepers.family.$familyId.entry-key.v1';
    final memberRef = 'keepers.member.$memberId.entry-key.v1';
    try {
      await _store.write(familyRef, base64UrlEncode(_randomBytesFactory(32)));
      await _store.write(memberRef, base64UrlEncode(_randomBytesFactory(32)));
      return CreatedIdentityKeys(familyKeyRef: familyRef, memberKeyRef: memberRef);
    } catch (_) {
      await _store.delete(memberRef);
      await _store.delete(familyRef);
      rethrow;
    }
  }

  Future<List<int>> resolve(String reference) async {
    final encoded = await _store.read(reference);
    if (encoded == null) throw StateError('Missing identity key: $reference');
    final bytes = base64Url.decode(encoded);
    if (bytes.length != 32) throw StateError('Invalid identity key: $reference');
    return List<int>.unmodifiable(bytes);
  }

  Future<void> rollback(CreatedIdentityKeys keys) async {
    await _store.delete(keys.memberKeyRef);
    await _store.delete(keys.familyKeyRef);
  }

  static List<int> _secureBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256), growable: false);
  }
}
```

- [ ] **Step 6: Implement exact repository SQL and providers**

```dart
Future<void> insert(
  DatabaseExecutor db, {
  required String id,
  required String name,
  required String familyKeyRef,
  required DateTime createdAt,
}) async {
  await db.insert('families', {
    'id': id,
    'name': name.trim(),
    'family_key_ref': familyKeyRef,
    'quorum': 1,
    'created_at': createdAt.millisecondsSinceEpoch,
  });
}

Future<void> insert(
  DatabaseExecutor db, {
  required String id,
  required String familyId,
  required String name,
  required String memberKeyRef,
  required String colorToken,
  required DateTime createdAt,
}) async {
  await db.insert('members', {
    'id': id,
    'family_id': familyId,
    'name': name.trim(),
    'role': 'adult',
    'member_key_ref': memberKeyRef,
    'color_token': colorToken,
    'created_at': createdAt.millisecondsSinceEpoch,
  });
}
```

`MemberRepository.findLocalIdentity(DatabaseExecutor db)` runs one `members JOIN families` query ordered by member creation time and returns `null` if no row or the member key reference is missing. Add these providers:

```dart
final familyRepositoryProvider = Provider((ref) => FamilyRepository());
final memberRepositoryProvider = Provider((ref) => MemberRepository());
final identityKeyServiceProvider = Provider(
  (ref) => IdentityKeyService(ref.watch(secureValueStoreProvider)),
);
final idFactoryProvider = Provider<String Function()>((ref) => const Uuid().v4);
final utcNowProvider = Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());
final localIdentityProvider = FutureProvider<LocalIdentity?>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ref.watch(memberRepositoryProvider).findLocalIdentity(db);
});
```

- [ ] **Step 7: Run onboarding data tests and the full storage suite**

Run: `cd app && dart format lib/features/onboarding test/features/onboarding && flutter analyze && flutter test test/features/onboarding/data test/storage`

Expected: all tests pass; keys remain independent and repository round trips return the stable color/key references.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/onboarding app/lib/storage/database_providers.dart app/test/features/onboarding
git commit -m "feat: add local family identity persistence"
```

### Task 4: Recoverable first-run setup and startup routing

**Files:**
- Create: `app/lib/features/onboarding/application/setup_controller.dart`
- Modify: `app/lib/features/onboarding/application/onboarding_providers.dart`
- Create: `app/lib/features/onboarding/presentation/startup_gate.dart`
- Create: `app/lib/features/onboarding/presentation/setup_screen.dart`
- Modify: `app/lib/app.dart`
- Modify: `app/test/app_test.dart`
- Test: `app/test/features/onboarding/application/setup_controller_test.dart`
- Test: `app/test/features/onboarding/presentation/setup_screen_test.dart`

**Interfaces:**
- Consumes: `SetupInput`, identity/repository/database/UUID/clock providers, and `localIdentityProvider`.
- Produces: `SetupPhase`, `SetupState`, `setupControllerProvider`, `SetupController.submit`, `StartupGate`, and `SetupScreen`.

- [ ] **Step 1: Write failing controller tests for validation, commit, and rollback**

```dart
test('invalid names never start setup', () async {
  final container = buildOnboardingContainer();
  addTearDown(container.dispose);
  final controller = container.read(setupControllerProvider.notifier);

  await controller.submit(const SetupInput(familyName: '  ', memberName: 'Chris'));

  expect(container.read(setupControllerProvider).phase, SetupPhase.idle);
  expect(container.read(setupControllerProvider).validationMessage, 'Enter both names');
  expect(await container.read(localIdentityProvider.future), isNull);
});

test('database failure rolls back created family and member keys', () async {
  final store = MemorySecureValueStore();
  final container = buildOnboardingContainer(
    secureStore: store,
    database: ThrowingTransactionDatabase(),
  );
  addTearDown(container.dispose);

  await container.read(setupControllerProvider.notifier).submit(
    const SetupInput(familyName: 'Sabati', memberName: 'Chris'),
  );

  expect(container.read(setupControllerProvider).phase, SetupPhase.failed);
  expect(store.values, isEmpty);
});
```

- [ ] **Step 2: Write a failing first-run widget test**

```dart
testWidgets('first run validates two names and enters the Observatory', (tester) async {
  final overrides = await inMemoryOnboardingOverrides();
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: const KeepersApp()));
  await tester.pumpAndSettle();

  expect(find.text('Name your family space'), findsOneWidget);
  expect(tester.widget<FilledButton>(find.text('Enter the Observatory')).onPressed, isNull);

  await tester.enterText(find.byKey(const Key('family-name')), 'Sabati');
  await tester.enterText(find.byKey(const Key('member-name')), 'Chris');
  await tester.tap(find.text('Enter the Observatory'));
  await tester.pumpAndSettle();

  expect(find.text('Every family has a keeper.'), findsOneWidget);
});
```

- [ ] **Step 3: Run the focused tests and confirm they fail**

Run: `cd app && flutter test test/features/onboarding/application/setup_controller_test.dart test/features/onboarding/presentation/setup_screen_test.dart test/app_test.dart`

Expected: FAIL because setup state/controller and startup screens do not exist.

- [ ] **Step 4: Implement setup state and recoverable orchestration**

```dart
enum SetupPhase { idle, submitting, failed }

final class SetupState {
  const SetupState({this.phase = SetupPhase.idle, this.validationMessage, this.errorMessage});
  final SetupPhase phase;
  final String? validationMessage;
  final String? errorMessage;
  bool get isSubmitting => phase == SetupPhase.submitting;
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(SetupController.new);

final class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  Future<void> submit(SetupInput input) async {
    if (!input.isValid) {
      state = const SetupState(validationMessage: 'Enter both names');
      return;
    }
    if (state.isSubmitting) return;
    state = const SetupState(phase: SetupPhase.submitting);

    final familyId = ref.read(idFactoryProvider)();
    final memberId = ref.read(idFactoryProvider)();
    CreatedIdentityKeys? keys;
    try {
      keys = await ref.read(identityKeyServiceProvider).createFor(
        familyId: familyId,
        memberId: memberId,
      );
      final db = await ref.read(databaseProvider.future);
      final createdAt = ref.read(utcNowProvider)();
      await db.transaction((txn) async {
        await ref.read(familyRepositoryProvider).insert(
          txn,
          id: familyId,
          name: input.familyName,
          familyKeyRef: keys!.familyKeyRef,
          createdAt: createdAt,
        );
        await ref.read(memberRepositoryProvider).insert(
          txn,
          id: memberId,
          familyId: familyId,
          name: input.memberName,
          memberKeyRef: keys.memberKeyRef,
          colorToken: 'ochre',
          createdAt: createdAt,
        );
      });
      ref.invalidate(localIdentityProvider);
      state = const SetupState();
    } catch (_) {
      if (keys != null) await ref.read(identityKeyServiceProvider).rollback(keys);
      state = const SetupState(
        phase: SetupPhase.failed,
        errorMessage: 'Your family space could not be secured. Try again.',
      );
    }
  }
}
```

- [ ] **Step 5: Implement startup routing and the minimal setup form**

```dart
final class StartupGate extends ConsumerWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(localIdentityProvider).when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => StartupError(
        message: 'Keepers could not open local storage.',
        onRetry: () => ref.invalidate(localIdentityProvider),
      ),
      data: (identity) => identity == null ? const SetupScreen() : const HomeScreen(),
    );
  }
}
```

`SetupScreen` owns two `TextEditingController` instances, trims only at submission, uses keys `family-name` and `member-name`, disables its 44-pixel-or-taller `FilledButton` until both values contain non-whitespace text, shows the controller’s retryable inline error, and labels the button `Enter the Observatory`. Replace `KeepersApp.home` with `const StartupGate()`. The authenticated branch deliberately reuses the existing `HomeScreen` until Task 8 replaces it with the complete Observatory, keeping this task compilable and reviewable.

- [ ] **Step 6: Run onboarding and existing tests**

Run: `cd app && dart format lib/features/onboarding lib/app.dart test/features/onboarding test/app_test.dart && flutter analyze && flutter test`

Expected: all tests pass; a failed transaction leaves no secure keys, and successful setup invalidates startup state and routes forward.

- [ ] **Step 7: Commit**

```bash
git add app/lib/app.dart app/lib/features/onboarding app/test/app_test.dart app/test/features/onboarding
git commit -m "feat: add recoverable first-run setup"
```

### Task 5: Versioned entry encryption and atomic persistence

**Files:**
- Create: `app/lib/features/capture/domain/capture_models.dart`
- Create: `app/lib/features/capture/data/entry_payload_codec.dart`
- Create: `app/lib/features/capture/data/entry_cipher.dart`
- Create: `app/lib/features/capture/data/entry_key_resolver.dart`
- Create: `app/lib/features/capture/data/encrypted_blob_store.dart`
- Create: `app/lib/features/capture/data/entry_repository.dart`
- Create: `app/lib/features/capture/data/entry_persistence_service.dart`
- Test: `app/test/features/capture/data/entry_payload_codec_test.dart`
- Test: `app/test/features/capture/data/entry_cipher_test.dart`
- Test: `app/test/features/capture/data/entry_key_resolver_test.dart`
- Test: `app/test/features/capture/data/entry_persistence_service_test.dart`

**Interfaces:**
- Consumes: `LocalIdentity`, `IdentityKeyService.resolve`, `databaseProvider`, app-support-directory access, and `cryptography.AesGcm.with256bits()`.
- Produces: `MemoryFormat`, `PrivacyTier`, `EntryMetadata`, `EntryPayload`, `EntrySaveRequest`, `EntryPayloadCodec`, `EntryCipher`, `EntryKeyResolver`, `EncryptedBlobStore`, `EntryRepository`, and `EntryPersistenceService.save`.

- [ ] **Step 1: Write failing canonical payload tests**

```dart
test('payload v1 round-trips text, media bytes, caption, and metadata', () {
  const codec = EntryPayloadCodec();
  final payload = EntryPayload(
    format: MemoryFormat.photo,
    primaryBytes: Uint8List.fromList([1, 2, 3]),
    text: null,
    caption: 'First morning',
    mediaExtension: 'jpg',
    mediaDurationMs: null,
  );

  expect(codec.decode(codec.encode(payload)), payload);
});

test('unknown payload versions are rejected', () {
  const codec = EntryPayloadCodec();
  expect(
    () => codec.decode(Uint8List.fromList(utf8.encode('{"v":99}'))),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Write failing AES-GCM behavior tests**

```dart
test('AES-GCM rejects wrong key and modified authenticated metadata', () async {
  final cipher = EntryCipher(nonceFactory: () => Uint8List.fromList(List<int>.generate(12, (i) => i)));
  final metadata = entryMetadata(privacy: PrivacyTier.journal);
  final encrypted = await cipher.encrypt(
    plaintext: Uint8List.fromList([10, 20, 30]),
    keyBytes: List<int>.filled(32, 1),
    metadata: metadata,
    keyScope: EntryKeyScope.member,
  );

  expect(
    cipher.decrypt(envelopeBytes: encrypted, keyBytes: List<int>.filled(32, 2), metadata: metadata),
    throwsA(isA<SecretBoxAuthenticationError>()),
  );
  expect(
    cipher.decrypt(
      envelopeBytes: encrypted,
      keyBytes: List<int>.filled(32, 1),
      metadata: metadata.copyWith(authorId: 'different'),
    ),
    throwsA(isA<SecretBoxAuthenticationError>()),
  );
});

test('every encryption receives a fresh 96-bit nonce', () async {
  var seed = 0;
  final cipher = EntryCipher(
    nonceFactory: () => Uint8List.fromList(List<int>.filled(12, seed++)),
  );
  final first = await cipher.encrypt(
    plaintext: Uint8List(0),
    keyBytes: List<int>.filled(32, 1),
    metadata: entryMetadata(),
    keyScope: EntryKeyScope.family,
  );
  final second = await cipher.encrypt(
    plaintext: Uint8List(0),
    keyBytes: List<int>.filled(32, 1),
    metadata: entryMetadata(),
    keyScope: EntryKeyScope.family,
  );
  expect(first, isNot(second));
});
```

- [ ] **Step 3: Write failing key-routing and rollback-order tests**

```dart
test('journal uses member key while reveal and legacy use family key', () async {
  final resolver = EntryKeyResolver(FakeIdentityKeyService());
  expect((await resolver.resolve(PrivacyTier.journal, identity)).scope, EntryKeyScope.member);
  expect((await resolver.resolve(PrivacyTier.reveal, identity)).scope, EntryKeyScope.family);
  expect((await resolver.resolve(PrivacyTier.legacy, identity)).scope, EntryKeyScope.family);
});

test('database failure deletes finalized encrypted blob and source plaintext', () async {
  final events = <String>[];
  final service = persistenceHarness(events: events, failInsert: true);

  await expectLater(service.save(saveRequest()), throwsStateError);

  expect(events, [
    'encode',
    'resolve-key',
    'encrypt',
    'stage',
    'finalize',
    'insert',
    'rollback-final',
    'delete-plaintext',
  ]);
});
```

- [ ] **Step 4: Run the focused tests and confirm they fail**

Run: `cd app && flutter test test/features/capture/data`

Expected: FAIL because the capture domain and encryption/persistence services do not exist.

- [ ] **Step 5: Implement the domain contracts**

```dart
enum MemoryFormat { photo, voice, text }
enum PrivacyTier { journal, reveal, legacy }
enum EntryKeyScope { member, family }

final class EntryMetadata {
  const EntryMetadata({
    required this.id,
    required this.familyId,
    required this.authorId,
    required this.createdAt,
    required this.format,
    required this.privacy,
    this.blobRef,
  });
  final String id;
  final String familyId;
  final String authorId;
  final DateTime createdAt;
  final MemoryFormat format;
  final PrivacyTier privacy;
  final String? blobRef;

  Map<String, Object> authenticatedMap(EntryKeyScope scope) => {
    'author_id': authorId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'entry_id': id,
    'entry_type': format.name,
    'family_id': familyId,
    'key_scope': scope.name,
    'privacy_tier': privacy.name,
  };
}

final class EntryPayload {
  const EntryPayload({
    required this.format,
    required this.primaryBytes,
    required this.text,
    required this.caption,
    required this.mediaExtension,
    required this.mediaDurationMs,
  });
  final MemoryFormat format;
  final Uint8List? primaryBytes;
  final String? text;
  final String? caption;
  final String? mediaExtension;
  final int? mediaDurationMs;
}

final class EntrySaveRequest {
  const EntrySaveRequest({
    required this.metadata,
    required this.payload,
    required this.identity,
    required this.plaintextPaths,
  });
  final EntryMetadata metadata;
  final EntryPayload payload;
  final LocalIdentity identity;
  final List<String> plaintextPaths;
}
```

Define value equality for `EntryPayload` using `listEquals` for bytes, plus `EntryMetadata.copyWith` used by tests.

- [ ] **Step 6: Implement canonical payload and AES-GCM envelopes**

```dart
final class EntryPayloadCodec {
  const EntryPayloadCodec();
  static const version = 1;

  Uint8List encode(EntryPayload payload) => Uint8List.fromList(utf8.encode(jsonEncode({
    'v': version,
    'format': payload.format.name,
    'primary': payload.primaryBytes == null ? null : base64UrlEncode(payload.primaryBytes!),
    'text': payload.text,
    'caption': payload.caption,
    'extension': payload.mediaExtension,
    'duration_ms': payload.mediaDurationMs,
  })));

  EntryPayload decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (map['v'] != version) throw const FormatException('Unsupported entry payload version');
    final format = MemoryFormat.values.byName(map['format'] as String);
    return EntryPayload(
      format: format,
      primaryBytes: map['primary'] == null ? null : Uint8List.fromList(base64Url.decode(map['primary'] as String)),
      text: map['text'] as String?,
      caption: map['caption'] as String?,
      mediaExtension: map['extension'] as String?,
      mediaDurationMs: map['duration_ms'] as int?,
    );
  }
}
```

`EntryCipher` writes a UTF-8 JSON envelope with exactly `v`, `scope`, `nonce`, `ciphertext`, and `tag`; all binary values use unpadded base64url. It derives AAD with `utf8.encode(jsonEncode(SplayTreeMap.of(metadata.authenticatedMap(scope))))`, verifies envelope version and scope before decrypting, uses `AesGcm.with256bits(nonceLength: 12)`, and constructs `SecretBox(cipherText, nonce: nonce, mac: Mac(tag))`.

- [ ] **Step 7: Implement key routing and encrypted blob lifecycle**

```dart
final class ResolvedEntryKey {
  const ResolvedEntryKey(this.scope, this.bytes);
  final EntryKeyScope scope;
  final List<int> bytes;
}

Future<ResolvedEntryKey> resolve(PrivacyTier privacy, LocalIdentity identity) async {
  final memberScoped = privacy == PrivacyTier.journal;
  final reference = memberScoped ? identity.memberKeyRef : identity.familyKeyRef;
  return ResolvedEntryKey(
    memberScoped ? EntryKeyScope.member : EntryKeyScope.family,
    await _identityKeys.resolve(reference),
  );
}
```

`EncryptedBlobStore` creates `p.join(supportDirectory.path, 'entries', 'staging', '$entryId.part')`, writes only encrypted bytes with `flush: true`, atomically renames it to `p.join(supportDirectory.path, 'entries', 'blobs', '$entryId.keeper')`, and returns `p.join('entries', 'blobs', '$entryId.keeper')`. `resolve(relativeRef)` rejects absolute paths and any normalized path escaping the support directory. `rollback(relativeRef)` and `deletePlaintext(paths)` ignore missing files but surface other I/O failures to tests.

- [ ] **Step 8: Implement metadata insertion and the ordered persistence service**

```dart
Future<void> insert(DatabaseExecutor db, EntryMetadata metadata, String blobRef) async {
  await db.insert('entries', {
    'id': metadata.id,
    'family_id': metadata.familyId,
    'author_id': metadata.authorId,
    'created_at': metadata.createdAt.millisecondsSinceEpoch,
    'entry_type': metadata.format.name,
    'privacy_tier': metadata.privacy.name,
    'blob_ref': blobRef,
    'transcript': null,
    'embedding': null,
    'state': 'pending',
    'expires_at': null,
    'revealed_at': null,
    'kept_at': null,
  });
}
```

`EntryPersistenceService.save` performs: encode payload → resolve key → encrypt → write staging → finalize → insert inside `database.transaction` → return metadata with blob ref. A `catch` after finalization invokes `rollback(finalRef)`; a `finally` always invokes `deletePlaintext(request.plaintextPaths)`. It never stores caption/text in SQL and never reports success before insert completion.

- [ ] **Step 9: Run capture-data tests plus the storage suite**

Run: `cd app && dart format lib/features/capture test/features/capture && flutter analyze && flutter test test/features/capture/data test/storage`

Expected: all codec, authentication, wrong-key, modified-AAD, nonce, routing, insert, rollback, and plaintext-cleanup tests pass.

- [ ] **Step 10: Commit**

```bash
git add app/lib/features/capture/domain app/lib/features/capture/data app/test/features/capture/data
git commit -m "feat: encrypt and atomically persist memory entries"
```

### Task 6: Capture adapters and deterministic draft controller

**Files:**
- Create: `app/lib/features/capture/data/photo_capture_adapter.dart`
- Create: `app/lib/features/capture/data/voice_capture_adapter.dart`
- Create: `app/lib/features/capture/data/audio_playback_adapter.dart`
- Create: `app/lib/features/capture/application/capture_providers.dart`
- Create: `app/lib/features/capture/application/capture_controller.dart`
- Modify: `app/lib/features/capture/domain/capture_models.dart`
- Test: `app/test/features/capture/application/capture_controller_test.dart`
- Test: `app/test/features/capture/data/photo_capture_adapter_test.dart`
- Test: `app/test/features/capture/data/voice_capture_adapter_test.dart`

**Interfaces:**
- Consumes: `EntryPersistenceService.save`, `localIdentityProvider`, ID/clock providers, `ImagePicker`, `AudioRecorder`, `AudioPlayer`, and temporary-directory access.
- Produces: `PhotoSource`, `CapturePhase`, `CaptureDraft`, `PhotoCaptureAdapter`, `VoiceCaptureAdapter`, `AudioPlaybackAdapter`, `captureControllerProvider`, and all draft transition methods.

- [ ] **Step 1: Write failing default, format, and validation tests**

```dart
test('draft defaults to photo and Weekly Reveal', () {
  final container = captureContainer();
  addTearDown(container.dispose);
  final state = container.read(captureControllerProvider);
  expect(state.format, MemoryFormat.photo);
  expect(state.privacy, PrivacyTier.reveal);
  expect(state.canSave, isFalse);
});

test('exactly one primary format survives switching', () {
  final container = captureContainer();
  final controller = container.read(captureControllerProvider.notifier);
  controller.acceptPhoto('/tmp/photo.jpg');
  controller.selectFormat(MemoryFormat.text);
  controller.updateText('A small memory');
  final state = container.read(captureControllerProvider);
  expect(state.photoPath, isNull);
  expect(state.voicePath, isNull);
  expect(state.text, 'A small memory');
});
```

- [ ] **Step 2: Write failing voice and duplicate-save tests**

```dart
test('voice uses tap start then tap stop', () async {
  final recorder = FakeVoiceCaptureAdapter();
  final container = captureContainer(recorder: recorder);
  final controller = container.read(captureControllerProvider.notifier);
  controller.selectFormat(MemoryFormat.voice);

  await controller.toggleRecording();
  expect(container.read(captureControllerProvider).isRecording, isTrue);
  await controller.toggleRecording();
  expect(container.read(captureControllerProvider).isRecording, isFalse);
  expect(container.read(captureControllerProvider).voicePath, '/tmp/voice.m4a');
});

test('rapid save taps persist one entry', () async {
  final persistence = BlockingPersistenceService();
  final container = captureContainer(persistence: persistence);
  final controller = container.read(captureControllerProvider.notifier);
  controller.selectFormat(MemoryFormat.text);
  controller.updateText('Only once');

  final first = controller.save();
  final second = controller.save();
  persistence.complete();
  await Future.wait([first, second]);

  expect(persistence.calls, 1);
  expect(container.read(captureControllerProvider).phase, CapturePhase.saved);
});
```

- [ ] **Step 3: Run controller/adapter tests and confirm they fail**

Run: `cd app && flutter test test/features/capture/application test/features/capture/data/photo_capture_adapter_test.dart test/features/capture/data/voice_capture_adapter_test.dart`

Expected: FAIL because adapters, state, and controller do not exist.

- [ ] **Step 4: Implement the immutable draft state**

```dart
enum PhotoSource { camera, library }
enum CapturePhase { editing, picking, recording, saving, saved, failed }

final class CaptureDraft {
  const CaptureDraft({
    this.format = MemoryFormat.photo,
    this.privacy = PrivacyTier.reveal,
    this.caption = '',
    this.photoPath,
    this.voicePath,
    this.voiceDuration = Duration.zero,
    this.text = '',
    this.phase = CapturePhase.editing,
    this.errorMessage,
    this.savedEntry,
  });
  final MemoryFormat format;
  final PrivacyTier privacy;
  final String caption;
  final String? photoPath;
  final String? voicePath;
  final Duration voiceDuration;
  final String text;
  final CapturePhase phase;
  final String? errorMessage;
  final EntryMetadata? savedEntry;

  bool get isRecording => phase == CapturePhase.recording;
  bool get hasPrimary => switch (format) {
    MemoryFormat.photo => photoPath != null,
    MemoryFormat.voice => voicePath != null && voiceDuration > Duration.zero,
    MemoryFormat.text => text.trim().isNotEmpty,
  };
  bool get canSave => hasPrimary && !isRecording && phase != CapturePhase.saving;
  bool get hasDraft => hasPrimary || caption.trim().isNotEmpty || isRecording;
}
```

Implement `copyWith` with explicit clear flags for nullable paths so format switching cannot accidentally retain prior media.

- [ ] **Step 5: Implement plugin adapters behind injectable interfaces**

```dart
abstract interface class PhotoCaptureAdapter {
  Future<String?> pick(PhotoSource source);
  Future<String?> recoverLostPhoto();
}

abstract interface class VoiceCaptureAdapter {
  Stream<double> get amplitudes;
  Future<bool> hasPermission();
  Future<void> start();
  Future<VoiceRecording?> stop();
  Future<void> cancel();
}

final class VoiceRecording {
  const VoiceRecording({required this.path, required this.duration});
  final String path;
  final Duration duration;
}

abstract interface class AudioPlaybackAdapter {
  Future<void> playFile(String path);
  Future<void> playBytes(Uint8List bytes);
  Future<void> stop();
}
```

`ImagePickerPhotoCaptureAdapter.pick` maps `PhotoSource.camera/library` to `ImageSource.camera/gallery`, uses `requestFullMetadata: false`, returns `null` on cancellation, and maps `PlatformException` to a typed `CapturePermissionException`. `recoverLostPhoto` calls `retrieveLostData()`, returns the first recovered file, and surfaces its exception.

`RecordVoiceCaptureAdapter.start` first calls `hasPermission()`, writes AAC-LC to `p.join(temporaryDirectory.path, 'keepers-capture', '$recordingId.m4a')` with one channel, tracks a `Stopwatch`, and exposes `onAmplitudeChanged(100ms).map((a) => a.current.clamp(-60, 0))`. `stop` returns the path and elapsed duration. `cancel` stops recording and deletes the temporary file. `AudioplayersPlaybackAdapter` uses `DeviceFileSource` for drafts and `BytesSource` for decrypted vault audio.

- [ ] **Step 6: Implement controller transitions and secure save invocation**

```dart
final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureDraft>(CaptureController.new);

final class CaptureController extends Notifier<CaptureDraft> {
  @override
  CaptureDraft build() => const CaptureDraft();

  void selectFormat(MemoryFormat format) {
    if (state.phase == CapturePhase.saving || state.isRecording) return;
    state = CaptureDraft(format: format, privacy: state.privacy, caption: state.caption);
  }

  void updateText(String value) => state = state.copyWith(text: value, errorMessage: null);
  void updateCaption(String value) => state = state.copyWith(caption: value, errorMessage: null);
  void setPrivacy(PrivacyTier value) => state = state.copyWith(privacy: value, errorMessage: null);

  Future<void> save() async {
    if (!state.canSave || state.phase == CapturePhase.saving) return;
    final frozen = state;
    state = state.copyWith(phase: CapturePhase.saving, errorMessage: null);
    try {
      final identity = await ref.read(localIdentityProvider.future);
      if (identity == null) throw StateError('Local identity is unavailable');
      final metadata = EntryMetadata(
        id: ref.read(idFactoryProvider)(),
        familyId: identity.familyId,
        authorId: identity.memberId,
        createdAt: ref.read(utcNowProvider)(),
        format: frozen.format,
        privacy: frozen.privacy,
      );
      final savedEntry = await ref.read(entryPersistenceServiceProvider).save(
        frozen.toSaveRequest(metadata: metadata, identity: identity),
      );
      state = frozen.copyWith(phase: CapturePhase.saved, savedEntry: savedEntry);
    } catch (_) {
      state = frozen.copyWith(
        phase: CapturePhase.failed,
        errorMessage: 'This memory could not be sealed. Your draft is still here.',
      );
    }
  }
}
```

Add `pickPhoto`, `acceptPhoto`, `toggleRecording`, `playVoice`, `replacePrimary`, and `discard`. Cancellation keeps the draft unchanged; typed denial errors show camera/library/microphone-specific copy while other formats remain selectable. `discard` stops playback/recording, deletes selected media paths, then resets to `const CaptureDraft()`.

- [ ] **Step 7: Run adapter/controller tests**

Run: `cd app && dart format lib/features/capture test/features/capture && flutter analyze && flutter test test/features/capture`

Expected: all transition, cancellation, denial, interruption, duplicate-save, retry, recovered-photo, recording, and cleanup tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/capture app/test/features/capture
git commit -m "feat: add photo voice and text capture state"
```

### Task 7: Capture sheet, privacy consequences, and discard behavior

**Files:**
- Create: `app/lib/features/capture/presentation/capture_sheet.dart`
- Test: `app/test/features/capture/presentation/capture_sheet_test.dart`
- Test: `app/test/features/capture/presentation/capture_accessibility_test.dart`

**Interfaces:**
- Consumes: `captureControllerProvider`, `CaptureDraft`, adapter actions, and `ObservatoryTokens.memberColor`.
- Produces: `CaptureSheet.show(BuildContext)` returning the persisted `EntryMetadata` only after success, plus photo/voice/text editors and a visible three-option privacy selector.

- [ ] **Step 1: Write failing format and privacy widget tests**

```dart
testWidgets('shows all formats and defaults to Weekly Reveal', (tester) async {
  await tester.pumpWidget(captureHarness());
  expect(find.text('Photo'), findsOneWidget);
  expect(find.text('Voice'), findsOneWidget);
  expect(find.text('Text'), findsOneWidget);
  expect(find.text('Private Journal'), findsOneWidget);
  expect(find.text('Weekly Reveal'), findsOneWidget);
  expect(find.text('Legacy Milestone'), findsOneWidget);

  final reveal = tester.widget<RadioListTile<PrivacyTier>>(
    find.byKey(const Key('privacy-reveal')),
  );
  expect(reveal.groupValue, PrivacyTier.reveal);
});

testWidgets('text plus optional caption enables Save', (tester) async {
  await tester.pumpWidget(captureHarness());
  await tester.tap(find.text('Text'));
  await tester.enterText(find.byKey(const Key('memory-text')), 'The kitchen smelled like cardamom.');
  await tester.enterText(find.byKey(const Key('memory-caption')), 'Friday morning');
  await tester.pump();

  final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Seal memory'));
  expect(save.onPressed, isNotNull);
});
```

- [ ] **Step 2: Write failing voice, error, and discard tests**

```dart
testWidgets('voice control is tap-to-start and tap-to-stop', (tester) async {
  await tester.pumpWidget(captureHarness(recorder: FakeVoiceCaptureAdapter()));
  await tester.tap(find.text('Voice'));
  await tester.tap(find.byKey(const Key('record-toggle')));
  await tester.pump();
  expect(find.text('Tap to stop'), findsOneWidget);
  await tester.tap(find.byKey(const Key('record-toggle')));
  await tester.pump();
  expect(find.text('Play recording'), findsOneWidget);
});

testWidgets('non-empty back action requires discard confirmation', (tester) async {
  await tester.pumpWidget(captureHarness());
  await tester.tap(find.text('Text'));
  await tester.enterText(find.byKey(const Key('memory-text')), 'Keep me');
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.text('Discard this memory?'), findsOneWidget);
  expect(find.text('Keep editing'), findsOneWidget);
  expect(find.text('Discard'), findsOneWidget);
});
```

- [ ] **Step 3: Run presentation tests and confirm they fail**

Run: `cd app && flutter test test/features/capture/presentation`

Expected: FAIL because `CaptureSheet` and its editors do not exist.

- [ ] **Step 4: Implement the sheet shell and format switcher**

```dart
static Future<EntryMetadata?> show(BuildContext context) {
  return showModalBottomSheet<EntryMetadata>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => const CaptureSheet(),
  );
}
```

The sheet uses `PopScope(canPop: !state.hasDraft)`; when a non-empty draft attempts to pop, show an `AlertDialog` with `Keep editing` and `Discard`, then await `controller.discard()` before closing. The format switcher uses three labeled `SegmentedButton` segments with Material camera, microphone, and text icons; no meaning depends on icons alone.

- [ ] **Step 5: Implement the three primary editors**

```dart
Widget _primaryEditor(CaptureDraft state, CaptureController controller) => switch (state.format) {
  MemoryFormat.photo => PhotoEditor(
    path: state.photoPath,
    onCamera: () => controller.pickPhoto(PhotoSource.camera),
    onLibrary: () => controller.pickPhoto(PhotoSource.library),
    onReplace: controller.replacePrimary,
  ),
  MemoryFormat.voice => VoiceEditor(
    isRecording: state.isRecording,
    duration: state.voiceDuration,
    hasRecording: state.voicePath != null,
    amplitudes: controller.amplitudes,
    onToggle: controller.toggleRecording,
    onPlay: controller.playVoice,
    onRerecord: controller.replacePrimary,
  ),
  MemoryFormat.text => TextField(
    key: const Key('memory-text'),
    minLines: 5,
    maxLines: 10,
    autofocus: true,
    onChanged: controller.updateText,
    decoration: const InputDecoration(
      labelText: 'Memory',
      hintText: 'Write what you want to remember…',
    ),
  ),
};
```

`PhotoEditor` shows labeled `Camera` and `Photo Library` actions before selection, an `Image.file` preview with `fit: BoxFit.contain` after selection, and `Replace`/`Continue` labels. `VoiceEditor` has one 56-pixel circular control keyed `record-toggle`, announces start/stop through `SemanticsService.sendAnnouncement`, displays elapsed `mm:ss`, and renders amplitude bars in the current member color without putting capture logic in the painter.

- [ ] **Step 6: Implement caption, privacy consequences, progress, and errors**

```dart
const privacyCopy = {
  PrivacyTier.journal: ('Private Journal', 'Only you can open this memory on this device.'),
  PrivacyTier.reveal: ('Weekly Reveal', 'Sealed for your family’s future reveal.'),
  PrivacyTier.legacy: ('Legacy Milestone', 'Sealed with the family key for a future milestone.'),
};
```

Render the optional caption `TextField` with key `memory-caption` below the primary editor. Render all three privacy options as radio tiles keyed `privacy-journal`, `privacy-reveal`, and `privacy-legacy` with the exact consequence copy above. Keep the selector visible while the keyboard is open.

`Seal memory` is disabled unless `state.canSave`; saving replaces its label with `Sealing…` and a progress indicator. Failure renders the controller’s inline error plus `Try again`. When `state.phase == CapturePhase.saved`, pop exactly once with `state.savedEntry!`; the sheet itself does not animate success or trigger haptics.

- [ ] **Step 7: Add accessibility and large-text assertions**

```dart
testWidgets('capture remains reachable at 1.4x text scale', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
      child: captureHarness(),
    ),
  );
  await tester.scrollUntilVisible(find.text('Seal memory'), 200);
  expect(tester.takeException(), isNull);
  expect(tester.getSize(find.byKey(const Key('record-toggle'))).shortestSide, greaterThanOrEqualTo(44));
});
```

- [ ] **Step 8: Run capture presentation tests**

Run: `cd app && dart format lib/features/capture/presentation test/features/capture/presentation && flutter analyze && flutter test test/features/capture`

Expected: all format, picker cancellation, denial alternatives, voice, caption, privacy, progress, retry, semantics, text-scale, and discard tests pass.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/capture/presentation app/test/features/capture/presentation
git commit -m "feat: build the secure capture sheet"
```

### Task 8: Vault decryption and the solo Living Orrery

**Files:**
- Create: `app/lib/features/vault/domain/vault_models.dart`
- Create: `app/lib/features/vault/data/vault_repository.dart`
- Create: `app/lib/features/vault/application/vault_providers.dart`
- Create: `app/lib/features/vault/application/vault_controller.dart`
- Create: `app/lib/features/vault/presentation/vault_list.dart`
- Create: `app/lib/features/vault/presentation/memory_viewer.dart`
- Create: `app/lib/features/vault/presentation/observatory_screen.dart`
- Modify: `app/lib/features/onboarding/presentation/startup_gate.dart`
- Create: `app/lib/design_system/observatory/orbit_scene.dart`
- Create: `app/lib/design_system/observatory/orbit_layout.dart`
- Create: `app/lib/design_system/observatory/motion_policy.dart`
- Create: `app/lib/design_system/observatory/observatory_view.dart`
- Test: `app/test/features/vault/data/vault_repository_test.dart`
- Test: `app/test/features/vault/application/vault_controller_test.dart`
- Test: `app/test/features/vault/presentation/observatory_screen_test.dart`
- Test: `app/test/features/vault/presentation/memory_viewer_test.dart`
- Test: `app/test/design_system/observatory/orbit_layout_test.dart`
- Test: `app/test/design_system/observatory/motion_policy_test.dart`

**Interfaces:**
- Consumes: `EntryMetadata`, `EntryCipher`, `EntryPayloadCodec`, `EntryKeyResolver`, `EncryptedBlobStore.resolve`, `localIdentityProvider`, `CaptureSheet.show`, and Observatory themes.
- Produces: `VaultEntryMetadata`, `OpenedMemory`, `VaultRepository.listForFamily`, `vaultEntriesProvider`, `VaultController.open`, `OrbitSceneModel`, `OrbitLayout.positions`, `MotionPolicy.fromMediaQuery`, `MemoryViewer`, and `ObservatoryScreen`.

- [ ] **Step 1: Write failing ordered-vault and authenticated-open tests**

```dart
test('vault returns newest family entries first without plaintext', () async {
  final db = await seededEntryDatabase();
  final rows = await VaultRepository().listForFamily(db, 'family-1');
  expect(rows.map((entry) => entry.id), ['newer', 'older']);
  expect(rows.every((entry) => entry.caption == null), isTrue);
});

test('open resolves the tier key and decrypts only in memory', () async {
  final harness = vaultHarness();
  final memory = await harness.controller.open(harness.metadata);
  expect(memory, isA<OpenedMemory>());
  expect(memory.payload.text, 'Only in memory');
  expect(harness.createdPlaintextFiles, isEmpty);
});

test('corrupt payload becomes unavailable without partial content', () async {
  final harness = vaultHarness(corruptTag: true);
  final memory = await harness.controller.open(harness.metadata);
  expect(memory, isA<UnavailableMemory>());
  expect((memory as UnavailableMemory).message, 'This memory cannot be opened safely.');
});
```

- [ ] **Step 2: Write failing pure geometry and reduced-motion tests**

```dart
test('one member stays centered and memories remain inside the orbit bounds', () {
  final layout = OrbitLayout.positions(
    size: const Size(320, 320),
    memoryCount: 6,
    phase: 0,
  );
  expect(layout.memberCenter, const Offset(160, 160));
  expect(layout.memoryCenters, hasLength(6));
  expect(layout.memoryCenters.every((point) => const Rect.fromLTWH(0, 0, 320, 320).contains(point)), isTrue);
});

testWidgets('platform disableAnimations removes drift and travel', (tester) async {
  late MotionPolicy policy;
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (context) {
        policy = MotionPolicy.fromMediaQuery(MediaQuery.of(context));
        return const SizedBox();
      }),
    ),
  );
  expect(policy.idleDrift, 0);
  expect(policy.parallax, 0);
  expect(policy.useSealTravel, isFalse);
});
```

- [ ] **Step 3: Write a failing solo Observatory widget test**

```dart
testWidgets('solo Observatory has one real member and an accessible vault', (tester) async {
  await tester.pumpWidget(observatoryHarness(entries: [photoMetadata(), textMetadata()]));
  await tester.pumpAndSettle();

  expect(find.bySemanticsLabel('Current member Chris'), findsOneWidget);
  expect(find.bySemanticsLabel('Family member'), findsOneWidget);
  expect(find.text('Add a memory'), findsOneWidget);
  expect(find.text('Photo memory'), findsOneWidget);
  expect(find.text('Text memory'), findsOneWidget);
  expect(find.textContaining('Mother'), findsNothing);
  expect(find.textContaining('Father'), findsNothing);
});
```

- [ ] **Step 4: Run vault/design tests and confirm they fail**

Run: `cd app && flutter test test/features/vault test/design_system/observatory`

Expected: FAIL because vault and Observatory models, repositories, controllers, and widgets do not exist.

- [ ] **Step 5: Implement metadata queries and authenticated in-memory open**

```dart
Future<List<VaultEntryMetadata>> listForFamily(DatabaseExecutor db, String familyId) async {
  final rows = await db.query(
    'entries',
    columns: ['id', 'family_id', 'author_id', 'created_at', 'entry_type', 'privacy_tier', 'blob_ref', 'state'],
    where: 'family_id = ?',
    whereArgs: [familyId],
    orderBy: 'created_at DESC, id DESC',
  );
  return rows.map(VaultEntryMetadata.fromRow).toList(growable: false);
}
```

`vaultEntriesProvider` awaits `localIdentityProvider`, returns an empty list when identity is absent, then queries `VaultRepository`. `VaultController.open` reconstructs `EntryMetadata`, resolves the expected key from privacy, reads the encrypted blob, authenticates/decrypts it, decodes the payload, and returns `OpenedMemory(metadata, payload)`. It catches missing keys, invalid refs, format errors, and authentication failures and returns `UnavailableMemory('This memory cannot be opened safely.')` without exposing exception text or plaintext.

- [ ] **Step 6: Implement scene records, pure layout, and motion policy**

```dart
final class OrbitSceneModel {
  const OrbitSceneModel({required this.member, required this.memories});
  final OrbitMemberNode member;
  final List<OrbitMemoryMark> memories;
}

final class OrbitMemberNode {
  const OrbitMemberNode({required this.id, required this.name, required this.colorToken});
  final String id;
  final String name;
  final String colorToken;
}

final class OrbitMemoryMark {
  const OrbitMemoryMark({
    required this.id,
    required this.format,
    required this.privacy,
    required this.createdAt,
    required this.colorToken,
  });
  final String id;
  final MemoryFormat format;
  final PrivacyTier privacy;
  final DateTime createdAt;
  final String colorToken;
}
```

`OrbitLayout.positions` centers the member, places each memory at base angle `-pi/2 + index * 2*pi/max(count,1)` and radius `min(width,height) * 0.34`, then adds a tangential drift offset of `Offset(-sin(angle), cos(angle)) * 4 * phase.clamp(-1, 1)`. The phase therefore moves a node by at most four logical pixels instead of rotating the orbit. It adds no database/UI dependencies. `MotionPolicy.fromMediaQuery` returns zero drift/parallax and opacity-scale seal feedback when `disableAnimations` or `accessibleNavigation` is true; otherwise it uses four-pixel drift, zero gyroscope parallax for v0, and 420ms seal travel. The zero parallax choice intentionally preserves the optional seam without adding a sensor/toolchain dependency in P0-03.

- [ ] **Step 7: Implement Observatory presentation with stable fallback list**

```dart
final scene = OrbitSceneModel(
  member: OrbitMemberNode(
    id: identity.memberId,
    name: identity.memberName,
    colorToken: identity.colorToken,
  ),
  memories: entries.map((entry) => OrbitMemoryMark(
    id: entry.id,
    format: entry.format,
    privacy: entry.privacy,
    createdAt: entry.createdAt,
    colorToken: identity.colorToken,
  )).toList(growable: false),
);
```

`ObservatoryView` receives only `OrbitSceneModel`, `MotionPolicy`, and callbacks. It uses a central 56-pixel member node with semantic label `'Current member ${scene.member.name}'`, an integrated labeled `Add a memory` action, restrained ring/mark geometry, and Material format/lock icons. Its ground uses the bundled raster without turning it into business state:

```dart
DecoratedBox(
  decoration: BoxDecoration(
    color: tokens.ground,
    image: const DecorationImage(
      image: AssetImage('assets/textures/observatory-grain.png'),
      repeat: ImageRepeat.repeat,
      opacity: .04,
    ),
  ),
  child: orbitalScene,
)
```

The view has no repositories, providers, or capture code.

`StartupGate` now routes a non-null identity to `ObservatoryScreen(identity: identity)`. `ObservatoryScreen` watches `vaultEntriesProvider`, calls `CaptureSheet.show`, and only when it returns non-null invalidates `vaultEntriesProvider`, awaits the refreshed list, then animates the returned entry’s format object from the center toward its computed orbital mark over 420ms. A brass `Icons.verified_rounded` seal lands at the target, followed by two `HapticFeedback.selectionClick()` calls separated by 80ms. Reduced motion replaces travel with one short opacity/scale change but retains the labeled brass completion state. Below the scene, `VaultList` always renders entries in deterministic order and opens `MemoryViewer`; loading, empty, retry, and unavailable states have text labels.

- [ ] **Step 8: Implement format renderers behind one viewer switch**

```dart
Widget buildMemoryContent(OpenedMemory memory) => switch (memory.metadata.format) {
  MemoryFormat.photo => Image.memory(memory.payload.primaryBytes!, fit: BoxFit.contain),
  MemoryFormat.voice => VoiceMemoryView(
    bytes: memory.payload.primaryBytes!,
    duration: Duration(milliseconds: memory.payload.mediaDurationMs!),
  ),
  MemoryFormat.text => SelectableText(memory.payload.text!),
};
```

`MemoryViewer` renders caption only when non-empty, supplies created-at/privacy labels, uses `AudioPlaybackAdapter.playBytes` for voice, stops playback on dispose, and never writes decrypted media to disk. Each renderer remains its own private widget so later tactile styling does not change controller or payload code.

- [ ] **Step 9: Add daylight, reduced-motion, semantic-order, and 1.4x tests**

```dart
testWidgets('daylight and 1.4x fallback list render without clipping', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: KeepersTheme.daylight(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4), disableAnimations: true),
        child: observatoryHarness(entries: sixEntries()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(VaultList), findsOneWidget);
  expect(find.bySemanticsLabel('Add a memory'), findsOneWidget);
});
```

- [ ] **Step 10: Run vault, design-system, and full application tests**

Run: `cd app && dart format lib/features/vault lib/design_system test/features/vault test/design_system && flutter analyze && flutter test`

Expected: all tests pass; vault ordering survives provider refresh, corrupt content is unavailable, one-member scenes remain honest, and both visual modes render.

- [ ] **Step 11: Commit**

```bash
git add app/lib/features/vault app/lib/design_system app/test/features/vault app/test/design_system
git commit -m "feat: open memories in the solo Observatory vault"
```

### Task 9: Relaunch integration, device gate, and acceptance evidence

**Files:**
- Create: `app/integration_test/p0_capture_flow_test.dart`
- Create: `docs/evidence/p0-03-device-gate.md`
- Modify: `docs/implementation-board.md`

**Interfaces:**
- Consumes: complete onboarding/capture/vault flow and real Android/iOS plugins.
- Produces: repeatable one-device integration coverage and an evidence record that gates P0-03/P0-GATE completion.

- [ ] **Step 1: Write the clean-install text integration test**

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('setup, seal text, rebuild providers, and reopen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KeepersApp()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('family-name')), 'Device Gate Family');
    await tester.enterText(find.byKey(const Key('member-name')), 'Gate Member');
    await tester.tap(find.text('Enter the Observatory'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.enterText(find.byKey(const Key('memory-text')), 'Persists after provider restart');
    await tester.enterText(find.byKey(const Key('memory-caption')), 'Encrypted caption');
    expect(
      tester.widget<RadioListTile<PrivacyTier>>(find.byKey(const Key('privacy-reveal'))).groupValue,
      PrivacyTier.reveal,
    );
    await tester.tap(find.text('Seal memory'));
    await tester.pumpAndSettle();
    expect(find.text('Text memory'), findsOneWidget);

    await tester.pumpWidget(const ProviderScope(child: KeepersApp()));
    await tester.pumpAndSettle();
    expect(find.text('Gate Member'), findsWidgets);
    await tester.tap(find.text('Text memory'));
    await tester.pumpAndSettle();
    expect(find.text('Persists after provider restart'), findsOneWidget);
    expect(find.text('Encrypted caption'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run automation on an emulator/simulator before physical devices**

Run:

```bash
cd app
flutter analyze
flutter test
flutter devices
flutter test integration_test/p0_capture_flow_test.dart -d "$KEEPERS_TEST_DEVICE_ID"
```

Set `KEEPERS_TEST_DEVICE_ID` to the exact emulator or simulator identifier printed by `flutter devices` before the final command. Expected: analyze and all unit/widget tests pass; the integration test creates setup, seals one reveal text memory, rebuilds Riverpod state, and reopens content.

- [ ] **Step 3: Create the exact physical-device evidence matrix**

```markdown
# P0-03 physical-device gate

| Check | Android device / OS / build | iOS device / OS / build |
|---|---|---|
| Clean install: family + adult member | Pending | Pending |
| Relaunch returns to solo Observatory | Pending | Pending |
| Camera photo: preview, caption, each privacy tier | Pending | Pending |
| Library photo: preview, replace, save, reopen | Pending | Pending |
| Voice: tap start, tap stop, playback, re-record, reopen | Pending | Pending |
| Text: caption, default Weekly Reveal, reopen | Pending | Pending |
| Journal resolves member key | Pending | Pending |
| Reveal and legacy resolve family key | Pending | Pending |
| Payload bytes contain no recognizable plaintext | Pending | Pending |
| Camera/library/microphone deny then grant | Pending | Pending |
| Interrupted recording remains recoverable | Pending | Pending |
| Forced failed save shows retry and leaves no orphan | Pending | Pending |
| Reduced motion, semantics, and 1.4x text | Pending | Pending |

Evidence for each completed cell: tester, UTC timestamp, commit SHA, device model,
OS version, screen recording or screenshot path, and a one-sentence result.
```

- [ ] **Step 4: Run the Android physical-device gate**

Run: `cd app && flutter run -d "$KEEPERS_ANDROID_DEVICE_ID"`

Set `KEEPERS_ANDROID_DEVICE_ID` to the exact physical Android identifier printed by `flutter devices`, then execute every Android column check. Inspect one `.keeper` blob copied from app-private storage in a debug build with a hex/string viewer and record that the known text/caption is absent. Force a save failure using a test override for `EntryRepository`, verify no new blob remains, then restore the production provider before capturing final evidence.

Expected: every Android cell changes from `Pending` to `Pass` with the required evidence fields; no workaround changes production privacy behavior.

- [ ] **Step 5: Run the iOS physical-device gate**

Run: `cd app && flutter run -d "$KEEPERS_IOS_DEVICE_ID"`

Set `KEEPERS_IOS_DEVICE_ID` to the exact physical iOS identifier printed by `flutter devices`, then execute every iOS column check, including photo-library limited-access behavior, microphone interruption via an incoming system audio event, app relaunch, and the same encrypted-blob/plaintext inspection.

Expected: every iOS cell changes from `Pending` to `Pass` with the required evidence fields.

- [ ] **Step 6: Mark backlog completion only after both columns pass**

```markdown
- [x] **P0-03 · Capture flow v0 (R3)** — Capture photo, voice, and text entries into encrypted storage and display them in the personal vault. **Acceptance:** capture → store → display works for all three types.
- [x] **P0-GATE · Two-device capture gate (All)** — Demonstrate capture → store → display on two physical devices, using iOS and Android when available.
```

If either platform has a failing cell, leave both relevant backlog items unchecked and link the failure evidence from the PR.

- [ ] **Step 7: Run final verification**

Run:

```bash
cd app
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter test integration_test/p0_capture_flow_test.dart -d "$KEEPERS_ANDROID_DEVICE_ID"
flutter test integration_test/p0_capture_flow_test.dart -d "$KEEPERS_IOS_DEVICE_ID"
```

Expected: formatting is unchanged; analyze reports no issues; all unit/widget tests pass; integration passes on both physical devices; the evidence matrix contains no `Pending` or `Fail` cells.

- [ ] **Step 8: Commit**

```bash
git add app/integration_test docs/evidence/p0-03-device-gate.md docs/implementation-board.md
git commit -m "test: verify P0 capture flow on iOS and Android"
```

## Review and Pull Request Gate

Before moving PR #3 out of draft:

1. Rebase or retarget after PR #2 merges so the branch is based on the merged P0-02 foundation.
2. Confirm the PR contains only the approved spec, this plan, P0-03 implementation, tests, and evidence.
3. Run the final verification commands from Task 9 and attach CI plus device evidence.
4. Check that no plaintext primary content/caption appears in SQL, logs, fixtures, screenshots, or committed test artifacts.
5. Check that the Observatory has one real member, that the accessible list reaches every memory, and that reduced motion removes drift/travel.
6. Request code review only after all automated checks and both physical-device columns pass.

## Primary References

- Package versions and platform requirements: `https://pub.dev/packages/cryptography`, `https://pub.dev/packages/cryptography_flutter`, `https://pub.dev/packages/image_picker`, `https://pub.dev/packages/record`, `https://pub.dev/packages/audioplayers`, and `https://pub.dev/packages/uuid`.
- Official offline fonts and OFL license: `https://github.com/google/fonts/tree/main/ofl/fraunces` and `https://github.com/google/fonts/tree/main/ofl/schibstedgrotesk`.
- Canonical product requirements: `docs/superpowers/specs/2026-09-01-p0-03-capture-vault-design.md`.

