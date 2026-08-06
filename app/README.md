# Keepers Flutter app

The mobile client is generated from Flutter stable and targets Android and iOS.

## Foundation

- Riverpod owns dependency lifecycles from the root ProviderScope.
- SQLCipher encrypts the SQLite database at rest.
- A random 256-bit database key is stored through Android Keystore or Apple Keychain via flutter_secure_storage.
- The normalized v1 schema mirrors every entity in Section 4.2 of the Keepers specification.
- Database opening is lazy; the home screen does not touch device storage until a feature requests the database provider.

## Native encrypted-storage contract

- Production persistence is native-gated for Android x64/arm64, iOS arm64, Linux x64, and macOS x64/arm64. Every other ABI fails before filesystem mutation.
- Each removal gets a freshly created, euid-owned `0700` directory capability that is never adopted from disk. Cooperative app writers therefore never share a candidate pathname.
- Mobile sandboxing and app-private roots exclude other principals. Hostile or non-cooperating same-euid writers are outside this contract: POSIX discretionary permissions cannot provide mandatory exclusion from the owning identity.
- Physical Android and iOS acceptance remains part of the Phase 0 Task 9 device matrix; CI runs the same production persistence smoke on an Android emulator and iOS simulator.

## Commands

Run these from this directory:

    flutter pub get
    flutter analyze --fatal-infos
    flutter test

Do not add family content, database files, secrets, or exported keys to source control.
