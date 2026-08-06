import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/app.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

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

  testWidgets('routes an established identity to the Observatory placeholder', (
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
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Every family has a keeper.'), findsOneWidget);
  });
}
