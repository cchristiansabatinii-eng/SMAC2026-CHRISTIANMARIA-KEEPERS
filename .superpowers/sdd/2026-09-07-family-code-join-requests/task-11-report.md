# Task 11 report

Status: implementation complete at the verified Task 11 checkpoint.

Completed under test-first development:

- `InviteLinkCoordinator` accepts only exact permanent HTTPS family-link
  candidates, emits redacted malformed events inside that namespace, ignores
  auth/legacy/unrelated URLs, bounds pending delivery, and replaces permanent
  seen-state with a one-shot cold digest that can be released on route close.
- Android has the verified `https://join.keepers.app/f/` filter while retaining
  the separate strict `keepers://auth-callback` filter.
- Both signed iOS entitlement files contain
  `applinks:join.keepers.app`; the existing auth URL scheme remains unchanged.
- Root navigation uses `FamilyJoinScreen.forCode`, retains the active code while
  its route is open, coalesces active/pending duplicates, clears the mutex on
  close, and preserves a bounded queue for distinct later links.
- Root-navigation tests cover cold/warm routing, active-code
  coalescing, later deliberate reopen, queued distinct codes, malformed
  neutrality, and ignored auth/legacy inputs.

Verification evidence:

- Before production edits, the rewritten coordinator and platform tests failed
  for the missing permanent-link event/API and platform associations.
- `flutter test --no-pub test/features/family/data/invite_link_coordinator_test.dart test/platform/invite_link_platform_contract_test.dart`
  passes: 13 tests.
- `flutter test --no-pub test/app_test.dart --name '(cold verified|cold active|pre-resolved|active warm|different warm|auth callback|malformed family|legacy capability)'`
  passes: 8 tests.
- `flutter analyze --no-pub lib/app.dart lib/features/family/data/invite_link_coordinator.dart test/app_test.dart test/features/family/data/invite_link_coordinator_test.dart test/platform/invite_link_platform_contract_test.dart`
  passes with no issues.

The whole `app_test.dart` file is not claimed as green at this checkpoint. Its
non-Task-11 setup, launch, and established-identity cases currently depend on
concurrent Task 8 `StartupGate` changes and fail or wait in that in-flight test
harness. The Task 11 cases use bounded pumps and pass independently; the parent
explicitly requested committing this green focused checkpoint without waiting
for the unrelated Task 8 harness.

`Info.plist` required no delta: it already retains the single `keepers` auth
scheme and disables Flutter's automatic deep-link handling.

External AASA/assetlinks documents and signing fingerprints remain Task 12
release gates and are not included here.
