# Keepers

Keepers is an offline-first family-memory application created for **SMAC Summer
2026** at Khalifa University. Its theme is **“AI for Stronger Family Bonds”**
and its tagline is **“Every family has a keeper.”**

The idea is simple: family members collect photos, voice notes, journal entries,
and recipes during the week. Those memories remain sealed until a family
gathering—the Unlock Ceremony—where everyone reviews and discusses them, then
chooses which memories to keep.

## Team

- Christian Sabatini — GitHub [cchristiansabatinii-eng](https://github.com/cchristiansabatinii-eng) — coded the large majority of the application.
- Maria Martins — no GitHub account — contributed significantly to product design, UI/UX, and the wider application design.

## What is implemented

Keepers currently includes encrypted capture and storage; account and
family-code onboarding; weekly family presence and reveal synchronization;
capsule-task unlocks; archive, observatory, and navigation experiences; launch
branding; and local AI conversation sparks. These are implemented feature areas,
not a statement that every release gate has been completed.

## Repository layout

- [`app/`](app/) — the Flutter Android and iOS client.
- [`supabase/`](supabase/) — Supabase schema, functions, local test setup, and
  operational notes.
- [`docs/`](docs/) — the historical concept brief, maintained delivery records,
  implementation plans, and project evidence.
- [`.github/workflows/`](.github/workflows/) — continuous-integration workflows.

## Requirements

- Flutter stable and a Dart SDK compatible with `^3.13.2`.
- Android and/or iOS platform tooling for the devices being used.
- A Supabase project and client configuration for a new installation.
- For applicable local backend tests: Supabase CLI plus Docker and PostgreSQL
  tooling.

## Configure and run

Create the ignored `app/config/supabase.local.json` with these two client
configuration values:

- `KEEPERS_SUPABASE_URL`
- `KEEPERS_SUPABASE_PUBLISHABLE_KEY`

Never use or document a service-role secret. The ignored configuration file is
required for a new installation to complete account setup and use the normal
family/local-memory flow.

From `app/`, run:

```powershell
flutter pub get
flutter run --dart-define-from-file=config/supabase.local.json
```

## Test

From `app/`, run:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos
flutter test
```

From the repository root, the available local Supabase flow is:

```powershell
supabase start
supabase db reset --local
supabase test db --local
```

The POSIX race harness requires Bash. Where this Windows host lacks the needed
tools, CI is authoritative; there is no invented PowerShell equivalent.

## Demo path

1. Configure Supabase, then run Keepers on the demo device or devices.
2. Create or sign in to an account and family, then capture a memory.
3. For multiple devices, use the reliable manual family-code entry path to
   join the family.
4. Demonstrate the weekly gathering, unlock, and reveal flow.
5. Archive or keep an item, then show a conversation spark.

Physical BLE and two-device paths remain release-gated where they have not been
validated.

## Privacy and encryption

The SQLCipher database is encrypted at rest with a random 256-bit database key
protected by Android Keystore or Apple Keychain. Media blobs are encrypted.
Family and member keys, along with private journal content, remain device-held.
Supabase receives metadata and ciphertext rather than plaintext memory payloads
or encryption keys.

## Known limitations

Repository evidence still identifies production throttling and purge operations,
production signing and verified links, two-physical-phone family-code
validation, iOS runtime/accessibility, and the physical BLE proximity matrix as
release gates. Manual code entry is the reliable demo path.

Capsule payloads, assignments, and task-completion state are local to the
capturing device; cross-device Capsule delivery and unlock synchronization are
not implemented.
