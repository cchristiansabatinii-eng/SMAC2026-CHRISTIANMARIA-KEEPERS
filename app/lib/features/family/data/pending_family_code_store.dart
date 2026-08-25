import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/storage/database_key_store.dart';

abstract interface class PendingFamilyCodeStore {
  Future<void> remember(FamilyCode code);

  Future<FamilyCode?> find();

  Future<void> forget();
}

final class SecurePendingFamilyCodeStore implements PendingFamilyCodeStore {
  SecurePendingFamilyCodeStore(this._values);

  static const _reference = 'keepers.family-join.pending-code.v1';

  final SecureValueStore _values;

  @override
  Future<void> remember(FamilyCode code) =>
      _values.write(_reference, code.normalized);

  @override
  Future<FamilyCode?> find() async {
    final encoded = await _values.read(_reference);
    if (encoded == null) return null;
    try {
      return FamilyCode.parse(encoded);
    } on FormatException {
      await _values.delete(_reference);
      return null;
    }
  }

  @override
  Future<void> forget() => _values.delete(_reference);
}
