import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/app.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';

void main() {
  testWidgets('routes a first run to the family setup', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name your family space'), findsOneWidget);
    expect(find.text('Enter the Observatory'), findsOneWidget);
  });

  testWidgets('routes an established identity to the solo Observatory', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWithValue(
            const AsyncValue.data(
              LocalIdentity(
                familyId: 'family-1',
                familyName: 'Sabati',
                familyKeyRef: 'family-key',
                memberId: 'member-1',
                memberName: 'Chris',
                memberKeyRef: 'member-key',
                colorToken: 'ochre',
              ),
            ),
          ),
          vaultEntriesProvider.overrideWithValue(const AsyncValue.data([])),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('The Observatory'), findsOneWidget);
    expect(find.text('No memories yet.'), findsOneWidget);
  });
}
