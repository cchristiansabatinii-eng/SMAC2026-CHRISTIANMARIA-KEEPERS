import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/app.dart';

void main() {
  testWidgets('shows the locked weekly reveal', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KeepersApp()),
    );

    expect(find.text('KEEPERS'), findsOneWidget);
    expect(find.text('Every family has a keeper.'), findsOneWidget);
    expect(find.text('Weekly reveal'), findsOneWidget);
    expect(
      find.text('Locked until your family gathers'),
      findsOneWidget,
    );
  });
}
