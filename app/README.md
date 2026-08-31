# Keepers Flutter app

The mobile client is generated from Flutter stable and targets Android and iOS.

## Foundation

- Riverpod owns dependency lifecycles from the root ProviderScope.
- SQLCipher encrypts the SQLite database at rest.
- A random 256-bit database key is stored through Android Keystore or Apple Keychain via flutter_secure_storage.
- The normalized v1 schema mirrors every entity in Section 4.2 of the Keepers specification.
- Database opening is lazy; the home screen does not touch device storage until a feature requests the database provider.

## Commands

Run these from this directory:

    flutter pub get
    flutter analyze --fatal-infos
    flutter test

Do not add family content, database files, secrets, or exported keys to source control.
