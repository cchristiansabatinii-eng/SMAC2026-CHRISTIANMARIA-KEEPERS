# Task 8 report — requester join flow and restart restoration

## Delivered

- Replaced the legacy capability-invite requester controller with the family-code join-request state machine.
- Preserved signed-in event auth resume and added manual, `forCode(FamilyCode)`, and malformed screen entry points.
- Persisted one canonical proposed member UUID and X25519 joining key for idempotent retries and restart recovery.
- Treated Realtime as invalidation only and refreshed every displayed decision through `getOwnJoinRequest()`.
- Validated approval context before decryption, installed locally, zeroed mutable family-key buffers, and delegated ordered cloud completion/key cleanup to Task 3 recovery.
- Made Setup's Join action functional and sequenced StartupGate as completion recovery, identity lookup, then own-request restoration.
- Kept previews limited to family name and sanitized avatar artwork, with 48dp essential controls, focus recovery, live regions, and stable async/error layout.

## TDD evidence

- Controller tests were replaced first and observed failing against the legacy API/state machine before implementation.
- Screen tests were replaced first and observed failing for the missing constructor/state contracts before implementation.
- Setup/Startup restoration tests were added before the production routing and recovery sequence.

## Verification

- `flutter test --no-pub test/features/family/application/family_join_controller_test.dart test/features/family/presentation/family_join_screen_test.dart test/features/onboarding/presentation/setup_screen_test.dart` — 32 passed.
- `flutter test --no-pub test/features/family/application/pending_join_completion_controller_test.dart test/features/family/data/approved_family_join_installer_test.dart` — 11 passed.
- Scoped `flutter analyze --no-pub` over all seven Task 8 production/test files — no issues found.
- `dart format` over all seven Task 8 files — clean.
- `git diff --check` over all seven Task 8 files — clean.
- Frontend Design Premium strict audit — 0 findings, 0 warnings, 0 violations.
- Source audit found no shadows, gradients, backdrop filters, image filters, or blur effects in the Task 8 surfaces.

## Out-of-scope integration notes

- The repository-wide analyzer still reports failures in concurrently owned Task 7/9/12 integration files; none are in Task 8's scoped files.
- Three ordinary-startup fixtures in Task 11-owned `app_test.dart` still need to override `familyJoinCompletionRecoveryProvider` with an idle recovery, because StartupGate now correctly runs Task 3 recovery before identity lookup. Task 11's family-link routing slice is green.
