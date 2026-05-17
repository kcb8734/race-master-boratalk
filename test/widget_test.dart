import 'package:flutter_test/flutter_test.dart';
import 'package:race_master/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RaceMasterApp());
    expect(find.byType(RaceMasterApp), findsOneWidget);
  });
}
